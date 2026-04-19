import Foundation
import SwiftUI

private func intelLog(_ msg: String) {
    let line = "\(Date()) [Intel] \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Coyote-Intel.log")
    if let fh = try? FileHandle(forWritingTo: url) {
        fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
    } else {
        try? data.write(to: url)
    }
}

struct IntelChip: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let value: String
    let icon: String
}

struct IntelligenceInsight: Identifiable, Sendable {
    let id = UUID()
    let entityName: String
    let sourceEntityName: String
    let kind: EntityKind
    let chips: [IntelChip]
    let timestamp: Date
}

struct CompanyNewsItem: Identifiable, Sendable {
    let id = UUID()
    let companyName: String
    let headline: String
    let summary: String
    let icon: String
    let timestamp: Date
}

struct IntegrationItem: Identifiable, Sendable {
    let id = UUID()
    let source: IntegrationSource
    let entityName: String
    let title: String
    let detail: String
    let timestamp: Date
}

enum IntegrationSource: String, Sendable {
    case salesforce
    case hubspot
    case slack
    case discord
}

@MainActor
final class IntelligenceEngine: ObservableObject {
    @Published var insights: [IntelligenceInsight] = []
    @Published var entityChips: [CaptionEntry] = []
    @Published var newsItems: [CompanyNewsItem] = []
    @Published var enrichingEntityNames: Set<String> = []
    @Published var integrationItems: [IntegrationItem] = []

    private let crustdata: CrustdataClient
    private let extractor = EntityExtractor()
    private var pendingKeys: Set<String> = []
    private var lookupQueue: [ExtractedEntity] = []
    private var lookupTask: Task<Void, Never>?
    private var newsSearchedCompanies: Set<String> = []
    private var enrichedEntityNames: Set<String> = []
    private var integrationGeneratedEntities: Set<String> = []

    private static let maxInsights = 8
    private static let maxChips = 10
    private static let maxNewsItems = 12
    private static let maxIntegrationItems = 8

    init(apiToken: String) {
        self.crustdata = CrustdataClient(apiToken: apiToken)
    }

    func processFinalizedCaption(_ text: String) {
        intelLog("Processing finalized caption: \(text.prefix(80))")
        extractor.extract(from: text) { [weak self] entities in
            if entities.isEmpty {
                intelLog("No entities extracted from caption")
                return
            }
            intelLog("Extracted \(entities.count) entities: \(entities.map { $0.associatedCompany != nil ? "\($0.name)@\($0.associatedCompany!)" : $0.name }.joined(separator: ", "))")
            Task { @MainActor [weak self] in
                self?.handleEntities(entities)
            }
        }
    }

    func removeEntity(named name: String) {
        let lowerName = name.lowercased()
        intelLog("Removing entity: \(name)")
        // Collect Crustdata-resolved names before removing insights
        let resolvedNames = Set(insights.filter { $0.sourceEntityName.lowercased() == lowerName }.map { $0.entityName.lowercased() })
        let allNames = resolvedNames.union([lowerName])
        // Remove the chip
        entityChips.removeAll { $0.text.lowercased() == lowerName }
        // Remove the insight
        insights.removeAll { $0.sourceEntityName.lowercased() == lowerName }
        // Remove from pending and queue
        pendingKeys = pendingKeys.filter { !$0.hasSuffix(":\(lowerName)") }
        lookupQueue.removeAll { $0.name.lowercased() == lowerName }
        // Remove associated news items and allow re-fetch
        newsItems.removeAll { allNames.contains($0.companyName.lowercased()) }
        for n in allNames { newsSearchedCompanies.remove(n) }
        // Also clear from extractor cooldown so it can be re-extracted
        extractor.clearCooldown(for: lowerName)
        // Clear enrichment tracking
        for n in allNames { enrichedEntityNames.remove(n); enrichingEntityNames.remove(n) }
        intelLog("After removal: \(insights.count) insights, \(entityChips.count) chips, \(newsItems.count) news")
    }

    func editEntity(oldName: String, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            removeEntity(named: oldName)
            return
        }
        intelLog("Editing entity: \(oldName) → \(trimmed)")
        // Preserve the old entity's kind if we had an insight for it
        let oldKind = insights.first(where: { $0.sourceEntityName.lowercased() == oldName.lowercased() })?.kind
            ?? pendingKeys.first(where: { $0.hasSuffix(":\(oldName.lowercased())") }).flatMap { key in
                EntityKind(rawValue: String(key.split(separator: ":").first ?? ""))
            }
        removeEntity(named: oldName)
        // Add chip for the new name and directly queue lookups
        addEntityChip(name: trimmed)
        if let kind = oldKind {
            // We know the kind — look up just that kind
            let entity = ExtractedEntity(kind: kind, name: trimmed, associatedCompany: nil, timestamp: Date())
            handleEntities([entity])
        } else {
            // Unknown kind — use Claude to determine it
            processFinalizedCaption(trimmed)
        }
    }

    func reset() {
        lookupTask?.cancel()
        lookupTask = nil
        lookupQueue.removeAll()
        pendingKeys.removeAll()
        insights.removeAll()
        entityChips.removeAll()
        newsItems.removeAll()
        newsSearchedCompanies.removeAll()
        integrationItems.removeAll()
        integrationGeneratedEntities.removeAll()
        extractor.reset()
        Task { await crustdata.clearCache() }
    }

    // MARK: - Private

    private func addEntityChip(name: String) {
        let lowerName = name.lowercased()
        guard !entityChips.contains(where: { $0.text.lowercased() == lowerName }) else { return }
        entityChips.append(CaptionEntry(text: name))
        while entityChips.count > Self.maxChips {
            entityChips.removeFirst()
        }
    }

    private func handleEntities(_ entities: [ExtractedEntity]) {
        var addedAny = false
        for entity in entities {
            let key = "\(entity.kind.rawValue):\(entity.name.lowercased())"
            // Skip if already pending, queued, or already have an insight
            guard !pendingKeys.contains(key) else { continue }
            let alreadyHasInsight = insights.contains { $0.sourceEntityName.lowercased() == entity.name.lowercased() }
            guard !alreadyHasInsight else { continue }

            // Add chip immediately so it's visible while lookup runs
            addEntityChip(name: entity.name)
            generateMockIntegrationItems(for: entity)

            pendingKeys.insert(key)
            lookupQueue.append(entity)
            addedAny = true
        }
        if addedAny {
            processQueue()
        }
    }

    private func processQueue() {
        guard lookupTask == nil else { return }
        lookupTask = Task { [weak self] in
            // Drain the queue and launch all lookups in parallel
            var entities: [ExtractedEntity] = []
            await MainActor.run {
                guard let self else { return }
                entities = self.lookupQueue
                self.lookupQueue.removeAll()
            }
            guard !entities.isEmpty else {
                await MainActor.run { [weak self] in self?.lookupTask = nil }
                return
            }
            await withTaskGroup(of: Void.self) { group in
                for entity in entities {
                    group.addTask { [weak self] in
                        guard let self else { return }
                        guard !Task.isCancelled else { return }
                        await self.lookup(entity)
                        await MainActor.run {
                            let key = "\(entity.kind.rawValue):\(entity.name.lowercased())"
                            self.pendingKeys.remove(key)
                        }
                    }
                }
            }
            await MainActor.run { [weak self] in
                self?.lookupTask = nil
                // Check if more entities were queued while we were looking up
                if let self, !self.lookupQueue.isEmpty {
                    self.processQueue()
                }
            }
        }
    }

    private func lookup(_ entity: ExtractedEntity) async {
        switch entity.kind {
        case .company:
            await lookupCompany(entity)
        case .person:
            await lookupPerson(entity)
        }
    }

    private func lookupCompany(_ entity: ExtractedEntity) async {
        intelLog("Searching company: \(entity.name)")
        let searchResults = await crustdata.searchCompany(name: entity.name)
        if let first = searchResults.first {
            intelLog("Search found company: \(first.name)")
            await MainActor.run { [weak self] in
                guard let self, self.entityChips.contains(where: { $0.text.lowercased() == entity.name.lowercased() }) else {
                    intelLog("Discarding insight for \(entity.name) — chip no longer active")
                    return
                }
                self.addInsight(from: first, entityName: entity.name)
            }
        } else {
            // Fallback: try enrich endpoint
            intelLog("Search empty, trying enrich for company: \(entity.name)")
            let enrichResult = await crustdata.enrichCompany(name: entity.name)
            if let result = enrichResult {
                intelLog("Enrich found company: \(result.name)")
                await MainActor.run { [weak self] in
                    guard let self, self.entityChips.contains(where: { $0.text.lowercased() == entity.name.lowercased() }) else {
                        intelLog("Discarding insight for \(entity.name) — chip no longer active")
                        return
                    }
                    self.addInsight(from: result, entityName: entity.name)
                }
            } else {
                intelLog("No Crustdata results for company: \(entity.name), keeping chip")
                // Keep the chip — don't remove it just because Crustdata has no data
                // Still fetch news even without Crustdata enrichment
                let name = entity.name
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.entityChips.contains(where: { $0.text.lowercased() == name.lowercased() }) else { return }
                    let key = name.lowercased()
                    if !self.newsSearchedCompanies.contains(key) {
                        self.newsSearchedCompanies.insert(key)
                        Task { await self.fetchCompanyNews(name) }
                    }
                }
            }
        }
    }

    private func lookupPerson(_ entity: ExtractedEntity) async {
        if let company = entity.associatedCompany {
            intelLog("Searching person: \(entity.name) at \(company)")
        } else {
            intelLog("Searching person: \(entity.name)")
        }

        // Step 1: Search with company filter (if available)
        var searchResults = await crustdata.searchPerson(name: entity.name, companyName: entity.associatedCompany)
        var wasCompanyFiltered = entity.associatedCompany != nil && !searchResults.isEmpty

        // Step 2: If company-filtered search returned nothing, retry without company filter
        if searchResults.isEmpty, entity.associatedCompany != nil {
            intelLog("Company-filtered search empty, retrying without company for: \(entity.name)")
            searchResults = await crustdata.searchPerson(name: entity.name, companyName: nil)
            wasCompanyFiltered = false
        }

        // Step 3: Pick the best result — if we have an associated company, prefer a result that mentions it
        let bestResult: CrustdataPersonResult? = pickBestPersonResult(searchResults, associatedCompany: entity.associatedCompany, wasCompanyFiltered: wasCompanyFiltered)

        if let person = bestResult {
            intelLog("Search found person: \(person.fullName) (title: \(person.title ?? "nil"), company: \(person.company?.name ?? "nil"))")
            await MainActor.run { [weak self] in
                guard let self, self.entityChips.contains(where: { $0.text.lowercased() == entity.name.lowercased() }) else {
                    intelLog("Discarding insight for \(entity.name) — chip no longer active")
                    return
                }
                self.addInsight(from: person, entityName: entity.name)
            }
        } else {
            // Fallback: try enrich endpoint (without company — name-only)
            let parts = entity.name.split(separator: " ", maxSplits: 1)
            let firstName = parts.first.map(String.init) ?? entity.name
            let lastName = parts.count > 1 ? String(parts[1]) : ""
            intelLog("Search empty, trying enrich for person: \(firstName) \(lastName)")
            let enrichResult = await crustdata.enrichPerson(firstName: firstName, lastName: lastName, companyName: nil)
            if let result = enrichResult {
                // Accept enrich result if name matches the query (enrich is name-based, so trust it)
                let nameMatches = result.fullName.lowercased().contains(entity.name.lowercased().split(separator: " ").first.map(String.init) ?? "")
                if !nameMatches, let company = entity.associatedCompany, !personMatchesCompany(result, company: company) {
                    intelLog("Enrich result \(result.fullName) doesn't match \(company), skipping")
                } else {
                    intelLog("Enrich found person: \(result.fullName)")
                    await MainActor.run { [weak self] in
                        guard let self, self.entityChips.contains(where: { $0.text.lowercased() == entity.name.lowercased() }) else {
                            intelLog("Discarding insight for \(entity.name) — chip no longer active")
                            return
                        }
                        self.addInsight(from: result, entityName: entity.name)
                    }
                }
            } else {
                intelLog("No Crustdata results for person: \(entity.name), keeping chip")
            }
        }
    }

    private func pickBestPersonResult(_ results: [CrustdataPersonResult], associatedCompany: String?, wasCompanyFiltered: Bool = false) -> CrustdataPersonResult? {
        guard !results.isEmpty else { return nil }
        guard let company = associatedCompany?.lowercased(), !company.isEmpty else {
            return results.first // No company context — just return first
        }
        // Prefer a result whose company name or title mentions the associated company
        if let matched = results.first(where: { personMatchesCompany($0, company: company) }) {
            return matched
        }
        // If the API already filtered by company, trust the first result even if
        // our heuristic doesn't match (Crustdata's filter is more reliable)
        if wasCompanyFiltered {
            intelLog("Company heuristic didn't match but API was company-filtered, trusting first result for '\(company)'")
            return results.first
        }
        // No match found — don't show a wrong person
        intelLog("No person result matches company '\(company)', discarding \(results.count) results")
        return nil
    }

    private func personMatchesCompany(_ person: CrustdataPersonResult, company: String) -> Bool {
        let c = company.lowercased()
        if let companyName = person.company?.name.lowercased(), companyName.contains(c) || c.contains(companyName) {
            return true
        }
        if let title = person.title?.lowercased(), title.contains(c) {
            return true
        }
        return false
    }

    private func addInsight(from company: CrustdataCompanyResult, entityName: String) {
        let chips = buildCompanyChips(company)
        guard !chips.isEmpty else { return }
        addEntityChip(name: entityName)
        let insight = IntelligenceInsight(
            entityName: company.name,
            sourceEntityName: entityName,
            kind: .company,
            chips: chips,
            timestamp: Date()
        )
        insertInsight(insight)
        // Trigger web search for company news
        let companyKey = company.name.lowercased()
        if !newsSearchedCompanies.contains(companyKey) {
            newsSearchedCompanies.insert(companyKey)
            let name = company.name
            Task { await self.fetchCompanyNews(name) }
        }
    }

    private func addInsight(from person: CrustdataPersonResult, entityName: String) {
        var chips = buildPersonChips(person)
        if let company = person.company {
            chips.append(contentsOf: buildCompanyChips(company))
        }
        guard !chips.isEmpty else { return }
        // Use the original searched name (from Claude) if it's longer/more complete than Crustdata's
        let displayName = entityName.count >= person.fullName.count ? entityName : person.fullName
        addEntityChip(name: entityName)
        let insight = IntelligenceInsight(
            entityName: displayName,
            sourceEntityName: entityName,
            kind: .person,
            chips: chips,
            timestamp: Date()
        )
        insertInsight(insight)
    }

    // MARK: - Full Enrich

    func fullEnrich(insightId: UUID) {
        guard let insight = insights.first(where: { $0.id == insightId }) else { return }
        let key = insight.entityName.lowercased()
        guard !enrichedEntityNames.contains(key) else {
            intelLog("Already enriched: \(insight.entityName)")
            return
        }
        enrichingEntityNames.insert(key)
        intelLog("Starting full enrich for \(insight.entityName) (kind=\(insight.kind))")

        Task {
            if insight.kind == .person {
                await fullEnrichPerson(insight: insight)
            } else {
                await fullEnrichCompany(insight: insight)
            }
        }
    }

    nonisolated private func fullEnrichPerson(insight: IntelligenceInsight) async {
        // Need LinkedIn URL to call person/enrich
        var linkedinUrl = insight.chips.first(where: { $0.label == "LinkedIn" })?.value
        let key = insight.entityName.lowercased()

        // Fallback: if no LinkedIn URL in chips, do a person search by name to discover it
        if linkedinUrl == nil || linkedinUrl!.isEmpty {
            intelLog("No LinkedIn URL in chips for \(insight.entityName), searching by name to discover it")
            let searchResults = await crustdata.searchPerson(name: insight.entityName, companyName: nil)
            linkedinUrl = searchResults.first?.linkedinUrl
        }

        guard let url = linkedinUrl, !url.isEmpty else {
            intelLog("No LinkedIn URL found for \(insight.entityName) even after search, cannot full enrich")
            await MainActor.run { [weak self] in
                self?.enrichingEntityNames.remove(key)
            }
            return
        }

        let normalizedUrl = url.hasPrefix("http") ? url : "https://\(url)"
        let enriched = await crustdata.fullEnrichPerson(linkedinUrl: normalizedUrl)

        await MainActor.run { [weak self] in
            guard let self else { return }
            self.enrichingEntityNames.remove(key)
            guard let enriched else {
                intelLog("Full enrich failed for person: \(insight.entityName)")
                return
            }
            // Re-fetch the current insight in case it was updated while enriching
            let currentInsight = self.insights.first(where: { $0.entityName.lowercased() == key }) ?? insight
            var newChips = self.buildPersonChips(enriched)
            if let company = enriched.company {
                newChips.append(contentsOf: self.buildCompanyChips(company))
            }
            let merged = self.mergeChips(existing: currentInsight.chips, enriched: newChips)
            let updated = IntelligenceInsight(
                entityName: currentInsight.entityName,
                sourceEntityName: currentInsight.sourceEntityName,
                kind: currentInsight.kind,
                chips: merged,
                timestamp: currentInsight.timestamp
            )
            self.insertInsight(updated)
            self.enrichedEntityNames.insert(key)
            intelLog("Full enrich complete for person \(insight.entityName): \(merged.count) chips")
        }
    }

    nonisolated private func fullEnrichCompany(insight: IntelligenceInsight) async {
        let domain = insight.chips.first(where: { $0.label == "Web" })?.value
        let key = insight.entityName.lowercased()
        let enriched = await crustdata.fullEnrichCompany(domain: domain, name: insight.entityName)

        await MainActor.run { [weak self] in
            guard let self else { return }
            self.enrichingEntityNames.remove(key)
            guard let enriched else {
                intelLog("Full enrich failed for company: \(insight.entityName)")
                return
            }
            let currentInsight = self.insights.first(where: { $0.entityName.lowercased() == key }) ?? insight
            let newChips = self.buildCompanyChips(enriched)
            let merged = self.mergeChips(existing: currentInsight.chips, enriched: newChips)
            let updated = IntelligenceInsight(
                entityName: currentInsight.entityName,
                sourceEntityName: currentInsight.sourceEntityName,
                kind: currentInsight.kind,
                chips: merged,
                timestamp: currentInsight.timestamp
            )
            self.insertInsight(updated)
            self.enrichedEntityNames.insert(key)
            intelLog("Full enrich complete for company \(insight.entityName): \(merged.count) chips")
        }
    }

    private func mergeChips(existing: [IntelChip], enriched: [IntelChip]) -> [IntelChip] {
        // Labels that can have multiple values
        let multiValueLabels: Set<String> = ["Email", "Education", "Past Role"]
        var result = existing
        let existingPairs = Set(existing.map { "\($0.label)|\($0.value.lowercased())" })

        for chip in enriched {
            let pairKey = "\(chip.label)|\(chip.value.lowercased())"
            if multiValueLabels.contains(chip.label) {
                // Allow multiple, but skip exact duplicates
                if !existingPairs.contains(pairKey) {
                    result.append(chip)
                }
            } else if let idx = result.firstIndex(where: { $0.label == chip.label }) {
                // Single-value label: update if enriched value is longer
                if chip.value.count > result[idx].value.count {
                    result[idx] = chip
                }
            } else {
                result.append(chip)
            }
        }
        return result
    }

    func isEnriched(entityName: String) -> Bool {
        enrichedEntityNames.contains(entityName.lowercased())
    }

    func isEnriching(entityName: String) -> Bool {
        enrichingEntityNames.contains(entityName.lowercased())
    }

    private func removeEntityChip(name: String) {
        entityChips.removeAll { $0.text.lowercased() == name.lowercased() }
    }

    private func insertInsight(_ insight: IntelligenceInsight) {
        intelLog("Inserting insight for \(insight.entityName) with \(insight.chips.count) chips: \(insight.chips.map { $0.label + "=" + $0.value.prefix(40) }.joined(separator: ", "))")
        if let idx = insights.firstIndex(where: { $0.entityName.lowercased() == insight.entityName.lowercased() }) {
            insights[idx] = insight
        } else {
            insights.insert(insight, at: 0)
        }
        if insights.count > Self.maxInsights {
            insights = Array(insights.prefix(Self.maxInsights))
        }
        intelLog("Total insights now: \(self.insights.count)")
    }

    // MARK: - Mock Integration Items

    private func generateMockIntegrationItems(for entity: ExtractedEntity) {
        let key = entity.name.lowercased()
        guard !integrationGeneratedEntities.contains(key) else { return }
        integrationGeneratedEntities.insert(key)

        let now = Date()
        var items: [IntegrationItem] = []

        if entity.kind == .company {
            let templates: [(IntegrationSource, String, String)] = [
                (.salesforce, "Open Deal", "Enterprise renewal  •  $\(Int.random(in: 50...500))K ARR  •  Stage: \(["Discovery", "Proposal", "Negotiation", "Closing"].randomElement()!)"),
                (.hubspot, "Contact Activity", "\(Int.random(in: 2...12)) contacts tracked  •  Last touch \(Int.random(in: 1...14))d ago  •  \(Int.random(in: 3...25)) emails exchanged"),
                (.slack, "#deals", "\"\(entity.name) just came up in the call — anyone have context on their \(["renewal", "expansion", "pilot", "POC"].randomElement()!)?\""),
            ]
            for (source, title, detail) in templates {
                items.append(IntegrationItem(source: source, entityName: entity.name, title: title, detail: detail, timestamp: now))
            }
        } else {
            let templates: [(IntegrationSource, String, String)] = [
                (.salesforce, "Contact Record", "\(["VP Sales", "Head of Engineering", "CTO", "Director of Product", "CEO"].randomElement()!)  •  Last meeting \(Int.random(in: 1...30))d ago"),
                (.slack, "#team-intel", "\"Has anyone connected with \(entity.name) recently? They were just mentioned in a live call.\""),
            ]
            for (source, title, detail) in templates {
                items.append(IntegrationItem(source: source, entityName: entity.name, title: title, detail: detail, timestamp: now))
            }
        }

        integrationItems.insert(contentsOf: items, at: 0)
        if integrationItems.count > Self.maxIntegrationItems {
            integrationItems = Array(integrationItems.prefix(Self.maxIntegrationItems))
        }
    }

    private func buildPersonChips(_ person: CrustdataPersonResult) -> [IntelChip] {
        var chips: [IntelChip] = []

        if let title = person.title, !title.isEmpty {
            chips.append(IntelChip(label: "Title", value: title, icon: "person.text.rectangle"))
        }
        if let headline = person.headline, !headline.isEmpty, headline != person.title {
            chips.append(IntelChip(label: "Headline", value: headline, icon: "text.quote"))
        }
        if let email = person.email, !email.isEmpty {
            chips.append(IntelChip(label: "Email", value: email, icon: "envelope"))
        }
        for extraEmail in person.businessEmails.dropFirst().prefix(2) {
            chips.append(IntelChip(label: "Email", value: extraEmail, icon: "envelope"))
        }
        if let linkedin = person.linkedinUrl, !linkedin.isEmpty {
            chips.append(IntelChip(label: "LinkedIn", value: linkedin, icon: "link"))
        }
        if let location = person.location, !location.isEmpty {
            chips.append(IntelChip(label: "Location", value: location, icon: "mappin.and.ellipse"))
        }
        if let twitter = person.twitterHandle, !twitter.isEmpty {
            chips.append(IntelChip(label: "Twitter", value: "@\(twitter)", icon: "at"))
        }
        if let github = person.githubUrl, !github.isEmpty {
            chips.append(IntelChip(label: "GitHub", value: github, icon: "chevron.left.forwardslash.chevron.right"))
        }
        if let followers = person.linkedinFollowers, followers > 0 {
            chips.append(IntelChip(label: "Followers", value: formatFollowers(followers), icon: "person.2"))
        }
        if let summary = person.summary, !summary.isEmpty {
            chips.append(IntelChip(label: "About", value: String(summary.prefix(200)), icon: "doc.text"))
        }
        for edu in person.education.prefix(3) {
            var eduStr = edu.school
            if let degree = edu.degree, !degree.isEmpty {
                eduStr += " — \(degree)"
            }
            if let field = edu.fieldOfStudy, !field.isEmpty {
                eduStr += ", \(field)"
            }
            chips.append(IntelChip(label: "Education", value: eduStr, icon: "graduationcap"))
        }
        if !person.skills.isEmpty {
            chips.append(IntelChip(label: "Skills", value: person.skills.prefix(10).joined(separator: ", "), icon: "star"))
        }
        for emp in person.pastEmployment.prefix(3) {
            var empStr = emp.company
            if let title = emp.title, !title.isEmpty {
                empStr += " — \(title)"
            }
            chips.append(IntelChip(label: "Past Role", value: empStr, icon: "clock.arrow.circlepath"))
        }
        if !person.languages.isEmpty {
            chips.append(IntelChip(label: "Languages", value: person.languages.joined(separator: ", "), icon: "globe"))
        }

        return chips
    }

    private func formatFollowers(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    private func buildCompanyChips(_ company: CrustdataCompanyResult) -> [IntelChip] {
        var chips: [IntelChip] = []

        if let industry = company.industry, !industry.isEmpty {
            chips.append(IntelChip(label: "Industry", value: industry, icon: "building.2"))
        }
        if let range = company.employeeRange, !range.isEmpty {
            chips.append(IntelChip(label: "Headcount", value: range, icon: "person.3"))
        } else if let count = company.employeeCount {
            chips.append(IntelChip(label: "Headcount", value: "\(count)", icon: "person.3"))
        }
        if let revenue = company.revenueRangePrinted, !revenue.isEmpty {
            chips.append(IntelChip(label: "Revenue", value: revenue, icon: "dollarsign.circle"))
        }
        if let funding = company.totalFunding, !funding.isEmpty {
            var fundingStr = funding
            if let stage = company.latestFundingStage, !stage.isEmpty {
                fundingStr += " (\(stage))"
            }
            chips.append(IntelChip(label: "Funding", value: fundingStr, icon: "banknote"))
        }
        if let founded = company.founded {
            chips.append(IntelChip(label: "Founded", value: "\(founded)", icon: "calendar"))
        }
        if let type = company.type, !type.isEmpty {
            chips.append(IntelChip(label: "Type", value: type, icon: "tag"))
        }
        if let location = company.location, !location.isEmpty {
            chips.append(IntelChip(label: "HQ", value: location, icon: "mappin.and.ellipse"))
        }
        if let website = company.website, !website.isEmpty {
            chips.append(IntelChip(label: "Web", value: website, icon: "globe"))
        }
        if let desc = company.descriptionAi, !desc.isEmpty {
            chips.append(IntelChip(label: "About", value: String(desc.prefix(120)), icon: "doc.text"))
        }
        if !company.investors.isEmpty {
            chips.append(IntelChip(label: "Investors", value: company.investors.prefix(5).joined(separator: ", "), icon: "dollarsign.arrow.circlepath"))
        }
        if !company.specialities.isEmpty {
            chips.append(IntelChip(label: "Specialities", value: company.specialities.prefix(8).joined(separator: ", "), icon: "list.bullet"))
        }

        return chips
    }

    // MARK: - Crustdata News (/web/search/live)

    nonisolated private func fetchCompanyNews(_ companyName: String) async {
        intelLog("Fetching news for company: \(companyName)")

        var newItems: [CompanyNewsItem] = []

        // Use /web/search/live for real-time news results
        let webResults = await crustdata.webSearch(query: "\(companyName) latest news")
        for result in webResults.prefix(5) {
            guard let title = result.title, !title.isEmpty else { continue }
            newItems.append(CompanyNewsItem(
                companyName: companyName,
                headline: title,
                summary: result.snippet ?? result.url ?? "",
                icon: "globe",
                timestamp: Date()
            ))
        }

        guard !newItems.isEmpty else {
            intelLog("No news found for \(companyName)")
            return
        }

        await MainActor.run { [weak self, newItems] in
            guard let self else { return }
            // Discard if entity was removed/edited while news was in-flight
            let chipExists = self.entityChips.contains { $0.text.lowercased() == companyName.lowercased() }
            let insightExists = self.insights.contains { $0.sourceEntityName.lowercased() == companyName.lowercased() || $0.entityName.lowercased() == companyName.lowercased() }
            guard chipExists || insightExists else {
                intelLog("Discarding \(newItems.count) news items for \(companyName) — entity no longer active")
                self.newsSearchedCompanies.remove(companyName.lowercased())
                return
            }
            self.newsItems.insert(contentsOf: newItems, at: 0)
            if self.newsItems.count > Self.maxNewsItems {
                self.newsItems = Array(self.newsItems.prefix(Self.maxNewsItems))
            }
            intelLog("Added \(newItems.count) news items for \(companyName)")
        }
    }
}
