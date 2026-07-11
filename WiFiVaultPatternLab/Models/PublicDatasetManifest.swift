import Foundation

enum PublicDatasetCategory: String, Codable, CaseIterable, Sendable {
    case english
    case pinyin
    case city
    case name
    case keyboard
    case test
}

enum PublicDatasetRole: String, Codable, Sendable {
    case root
    case auxiliary
}

struct PublicDatasetDescriptor: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let category: PublicDatasetCategory
    let role: PublicDatasetRole
    let file: String
    let defaultEnabled: Bool
    let analyzerEnabled: Bool
    let sourceName: String
    let sourceURL: String
    let license: String
    let lineCount: Int
    let byteCount: Int64
    let sha256: String
}

struct PublicPackManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let packId: String
    let packVersion: String
    let generatedAt: String
    let datasets: [PublicDatasetDescriptor]
}

struct ResolvedPublicDataset: Equatable, Sendable {
    let descriptor: PublicDatasetDescriptor
    let fileURL: URL
}

struct PublicResourcePackSnapshot: Equatable, Sendable {
    let bundleURL: URL
    let manifest: PublicPackManifest
    let datasets: [ResolvedPublicDataset]
}

enum DatasetIntegrity: Equatable, Sendable {
    case pending
    case valid
    case invalid(String)

    var isValid: Bool {
        self == .valid
    }
}

struct DatasetViewState: Identifiable, Equatable, Sendable {
    let descriptor: PublicDatasetDescriptor
    var integrity: DatasetIntegrity

    var id: String { descriptor.id }
}
