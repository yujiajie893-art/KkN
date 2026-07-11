import Foundation
import CoreFoundation

struct TextImportResult: Equatable, Sendable {
    let fileURL: URL
    let originalFileName: String
    let detectedEncoding: String
    let acceptedCount: Int
    let duplicateCount: Int
    let ignoredBlankCount: Int
    let skippedLongLineCount: Int
    let wasTruncated: Bool
}

enum TextDatasetImporterError: LocalizedError {
    case unreadable, unsupportedEncoding, empty
    var errorDescription: String? {
        switch self {
        case .unreadable: return "无法读取所选 TXT 文件"
        case .unsupportedEncoding: return "无法识别编码，请使用 UTF-8、UTF-16 或 GB2312"
        case .empty: return "文件中没有可导入的有效内容"
        }
    }
}

enum TextDatasetImporter {
    static let maximumLineLength = 256
    static let maximumCandidateCount = 20_000

    static func importFile(at sourceURL: URL, destinationDirectory: URL) throws -> TextImportResult {
        #if canImport(UIKit)
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }
        #endif
        guard let data = try? Data(contentsOf: sourceURL, options: .mappedIfSafe) else {
            throw TextDatasetImporterError.unreadable
        }
        let decoded = try decode(data)
        var seen = Set<String>(), accepted: [String] = []
        var duplicates = 0, blanks = 0, longLines = 0, truncated = false
        decoded.text.enumerateLines { rawLine, stop in
            var line = rawLine
            if line.first == "\u{FEFF}" { line.removeFirst() }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { blanks += 1; return }
            guard trimmed.count <= maximumLineLength else { longLines += 1; return }
            guard seen.insert(trimmed).inserted else { duplicates += 1; return }
            guard accepted.count < maximumCandidateCount else { truncated = true; stop = true; return }
            accepted.append(trimmed)
        }
        guard !accepted.isEmpty else { throw TextDatasetImporterError.empty }
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let outputURL = destinationDirectory.appendingPathComponent("Imported-\(UUID().uuidString).txt")
        try Data((accepted.joined(separator: "\n") + "\n").utf8).write(to: outputURL, options: .atomic)
        return TextImportResult(fileURL: outputURL, originalFileName: sourceURL.lastPathComponent,
            detectedEncoding: decoded.name, acceptedCount: accepted.count, duplicateCount: duplicates,
            ignoredBlankCount: blanks, skippedLongLineCount: longLines, wasTruncated: truncated)
    }

    static func decode(_ data: Data) throws -> (text: String, name: String) {
        if data.starts(with: [0xEF, 0xBB, 0xBF]), let s = String(data: data.dropFirst(3), encoding: .utf8) { return (s, "UTF-8 BOM") }
        if data.starts(with: [0xFF, 0xFE]), let s = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) { return (s, "UTF-16 LE") }
        if data.starts(with: [0xFE, 0xFF]), let s = String(data: data.dropFirst(2), encoding: .utf16BigEndian) { return (s, "UTF-16 BE") }
        if let s = String(data: data, encoding: .utf8) { return (s, "UTF-8") }
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        if let s = String(data: data, encoding: gb) { return (s, "GB2312/GB18030") }
        throw TextDatasetImporterError.unsupportedEncoding
    }
}
