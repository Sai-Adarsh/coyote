import Foundation

enum Env {
    private static let values: [String: String] = {
        // Look for .env next to the app bundle first, then in the project root
        let candidates = [
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(".env"),
            Bundle.main.bundleURL
                .deletingLastPathComponent() // Debug/
                .deletingLastPathComponent() // Products/
                .deletingLastPathComponent() // Build/
                .deletingLastPathComponent() // DerivedData/<hash>/
                .deletingLastPathComponent() // DerivedData/
                .appendingPathComponent(".env"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".env")
        ]

        for url in candidates {
            if let contents = try? String(contentsOf: url, encoding: .utf8) {
                return parse(contents)
            }
        }
        return [:]
    }()

    private static func parse(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            result[key] = value
        }
        return result
    }

    static var openAIKey: String {
        values["OPENAI_API_KEY"] ?? ""
    }

    static var claudeAPIKey: String {
        values["CLAUDE_API_KEY"] ?? ""
    }

    static var crustdataToken: String {
        values["CRUSTDATA_API_TOKEN"] ?? ""
    }
}
