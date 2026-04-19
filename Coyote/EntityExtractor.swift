import Foundation

private func entityLog(_ msg: String) {
    let line = "\(Date()) [Entity] \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Coyote-Entity.log")
    if let fh = try? FileHandle(forWritingTo: url) {
        fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
    } else {
        try? data.write(to: url)
    }
}

enum EntityKind: String, Sendable, Hashable, Codable {
    case person
    case company
}

struct ExtractedEntity: Sendable, Hashable {
    let kind: EntityKind
    let name: String
    let associatedCompany: String?
    let timestamp: Date
}

final class EntityExtractor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Coyote.entityExtractor")
    private var recentEntities: [String: Date] = [:]
    private let cooldown: TimeInterval = 15
    private let claudeAPIKey: String
    private let session: URLSession
    private var recentCaptions: [String] = []
    private let maxContextCaptions = 5

    init(claudeAPIKey: String = Env.claudeAPIKey) {
        self.claudeAPIKey = claudeAPIKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    func extract(from text: String, completion: @escaping @Sendable ([ExtractedEntity]) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            completion([])
            return
        }

        // Build context from recent captions
        let context: String = queue.sync {
            let ctx = recentCaptions.joined(separator: " | ")
            recentCaptions.append(trimmed)
            if recentCaptions.count > maxContextCaptions {
                recentCaptions.removeFirst()
            }
            return ctx
        }

        Task {
            let entities = await self.callClaude(text: trimmed, context: context)
            completion(entities)
        }
    }

    private func callClaude(text: String, context: String) async -> [ExtractedEntity] {
        entityLog("Claude extraction for: \(text.prefix(120))")

        let now = Date()
        let systemPrompt = """
        You are an entity extractor for a live meeting intelligence tool. The input is from speech-to-text and MAY contain transcription errors. You will receive RECENT CONTEXT (previous captions) and a NEW SEGMENT to extract from.

        Extract BOTH persons and companies/organizations:

        PERSON:
        - Any person mentioned by name. Always use their FULL name including all parts (first, middle, last). Never drop any part of a multi-part name.
        - When a person is associated with a company (via title, role, or context), include the "company" field.
        - Use BOTH the new segment AND recent context to determine associations. If a company was mentioned in context and a person is discussed in the new segment in relation to it, associate them.

        COMPANY:
        - Any company, startup, brand, product, organization, university, or business entity.
        - When you recognize a product name, also extract its parent company as a separate entity.
        - When a well-known person is mentioned, also extract their known associated companies.

        COMPOUND NAMES:
        - If two or more words together form a single product or company name, keep them as ONE entity. Do not split them.
        - When in doubt, keep words together rather than splitting them.

        SPEECH-TO-TEXT CORRECTION:
        - The input frequently garbles proper nouns. Use your world knowledge to fix them.
        - For person names: if a title/role and company are mentioned, use your knowledge of that company's actual leadership to correct garbled names to the real person who holds that role.
        - For company names: fix phonetic errors, word-splits, and misspellings to the correct official spelling.
        - Always output the correct official real-world spelling.

        Rules:
        - Do NOT extract generic words, verbs, adjectives, conversation filler, or URLs/domains.
        - Ignore speech-to-text artifacts and filler phrases.
        - Be aggressive — if something MIGHT be an entity worth looking up, include it.
        - Return ONLY valid JSON. No markdown fences, no explanation.
        - If nothing found: {"entities":[]}

        Format: {"entities":[{"kind":"person","name":"Full Name","company":"Company Name or null"},{"kind":"company","name":"Company Name"}]}
        For persons, "company" is OPTIONAL — include it ONLY when the conversation clearly ties the person to a company.
        """

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 256,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": context.isEmpty ? "Extract entities from this meeting transcript segment:\n\"\(text)\"" : "Recent context: \(context)\n\nExtract entities from this NEW segment (use context for associations):\n\"\(text)\""]
            ]
        ]

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(claudeAPIKey, forHTTPHeaderField: "x-api-key")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

            guard (200...299).contains(statusCode) else {
                let respStr = String(data: data, encoding: .utf8) ?? "?"
                entityLog("Claude HTTP \(statusCode): \(respStr.prefix(200))")
                return []
            }

            // Parse Claude response — extract text content from messages API
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let firstBlock = content.first,
                  let textContent = firstBlock["text"] as? String else {
                entityLog("Claude response parse failed")
                return []
            }

            entityLog("Claude raw: \(textContent.prefix(300))")

            // Strip markdown code fences if present
            var jsonText = textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if jsonText.hasPrefix("```") {
                // Remove opening fence (```json or ```)
                if let firstNewline = jsonText.firstIndex(of: "\n") {
                    jsonText = String(jsonText[jsonText.index(after: firstNewline)...])
                }
                // Remove closing fence
                if jsonText.hasSuffix("```") {
                    jsonText = String(jsonText.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            // Parse the JSON entities from Claude's text response
            guard let jsonData = jsonText.data(using: .utf8),
                  let parsed = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let entityList = parsed["entities"] as? [[String: Any]] else {
                entityLog("Claude JSON parse failed from: \(jsonText.prefix(200))")
                return []
            }

            var results: [ExtractedEntity] = []
            var seen = Set<String>()

            for item in entityList {
                guard let kindStr = item["kind"] as? String,
                      let kind = EntityKind(rawValue: kindStr),
                      let name = item["name"] as? String, !name.isEmpty else { continue }

                let key = "\(kind.rawValue):\(name.lowercased())"
                guard !seen.contains(key) else { continue }
                if let last = recentEntities[key], now.timeIntervalSince(last) < cooldown {
                    entityLog("Cooldown skip: \(key)")
                    continue
                }
                seen.insert(key)
                recentEntities[key] = now
                let associatedCompany = (kind == .person) ? (item["company"] as? String) : nil
                results.append(ExtractedEntity(kind: kind, name: name, associatedCompany: associatedCompany, timestamp: now))
            }

            pruneOldEntities(now: now)
            entityLog("Extraction complete: \(results.count) entities — \(results.map { "\($0.kind.rawValue):\($0.name)" }.joined(separator: ", "))")
            return results
        } catch {
            entityLog("Claude error: \(error.localizedDescription)")
            return []
        }
    }

    private func pruneOldEntities(now: Date) {
        let cutoff = now.addingTimeInterval(-cooldown * 3)
        recentEntities = recentEntities.filter { $0.value > cutoff }
    }

    func clearCooldown(for lowerName: String) {
        queue.async { [weak self] in
            self?.recentEntities = self?.recentEntities.filter { !$0.key.hasSuffix(":\(lowerName)") } ?? [:]
        }
    }

    func reset() {
        queue.async { [weak self] in
            self?.recentEntities.removeAll()
            self?.recentCaptions.removeAll()
        }
    }
}
