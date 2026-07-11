import Foundation

struct WiFiRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var ssid: String
    var password: String
    var createdAt = Date()
    var lastUsedAt: Date?
}

enum VerificationLimit: Int, CaseIterable, Codable {
    case fifty = 50, oneHundred = 100, fiveHundred = 500, oneThousand = 1000
    static let absoluteMaximum = 20_000
    init(storedValue: Int) { self = Self(rawValue: storedValue) ?? .fifty }
}

enum VerificationPace: String, CaseIterable, Codable {
    case conservative, balanced, fast
    init(storedValue: String) { self = Self(rawValue: storedValue) ?? .balanced }
}

enum VerificationOrder: String, CaseIterable, Codable {
    case original, riskFirst, shortestFirst
    init(storedValue: String) { self = Self(rawValue: storedValue) ?? .riskFirst }
}

enum WiFiCredentialPolicy {
    static func connectionValidationMessage(ssid: String, password: String) -> String? {
        ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "SSID 不能为空" : nil
    }
}

enum CandidateListParser {
    static let maximumCandidateCount = 20_000
    static func parse(data: Data) throws -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var seen = Set<String>()
        return text.components(separatedBy: .newlines).compactMap {
            let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 256, seen.insert(value).inserted else { return nil }
            return value
        }.prefix(maximumCandidateCount).map { $0 }
    }
}
