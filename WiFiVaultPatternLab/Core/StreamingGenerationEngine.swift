import Foundation

struct StreamingGenerationRequest: Sendable {
    let configuration: GeneratorConfiguration
    let rootDatasets: [ResolvedPublicDataset]
    let keyboardDataset: ResolvedPublicDataset?
    let outputURL: URL
}

enum StreamingGenerationError: LocalizedError {
    case noRootSource
    case noRuleSelected

    var errorDescription: String? {
        switch self {
        case .noRootSource: return "请至少选择一个可用词根来源。"
        case .noRuleSelected: return "请至少启用一条生成规则。"
        }
    }
}

enum StreamingGenerationEngine {
    static func generate(
        request: StreamingGenerationRequest,
        progressHandler: @escaping @Sendable (GenerationProgress) -> Void = { _ in }
    ) async throws -> GenerationSummary {
        let configuration = request.configuration.normalized()
        guard !request.rootDatasets.isEmpty else { throw StreamingGenerationError.noRootSource }
        guard configuration.hasEnabledRule else { throw StreamingGenerationError.noRuleSelected }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: request.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: request.outputURL.path) {
            try fileManager.removeItem(at: request.outputURL)
        }
        fileManager.createFile(atPath: request.outputURL.path, contents: nil)

        let startedAt = Date()
        var completed = false
        defer {
            if !completed {
                try? fileManager.removeItem(at: request.outputURL)
            }
        }

        let keyboardPatterns = try loadKeyboardPatterns(from: request.keyboardDataset)
        let writer = try BufferedLineWriter(url: request.outputURL)
        var preview: [String] = []
        preview.reserveCapacity(200)
        var generatedCount = 0
        var wasTruncated = false
        var seenRoots = Set<UInt64>()
        seenRoots.reserveCapacity(250_000)
        var lastProgressCount = 0
        var lastProgressAt = Date()

        func currentProgress() -> GenerationProgress {
            GenerationProgress(
                generatedCount: generatedCount,
                maximumCount: configuration.maximumResults,
                bytesWritten: writer.totalBytes,
                elapsedSeconds: Date().timeIntervalSince(startedAt)
            )
        }

        progressHandler(currentProgress())

        generation: for dataset in request.rootDatasets {
            let reader = try UTF8LineReader(url: dataset.fileURL)
            while let rawRoot = try reader.nextLine() {
                try Task.checkCancellation()
                let root = rawRoot.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !root.isEmpty, root.count <= 128 else { continue }

                let fingerprint = StableHash64.fnv1a(root.lowercased())
                guard seenRoots.insert(fingerprint).inserted else { continue }

                let exhausted = try PatternRuleExpander.forEachCandidate(
                    root: root,
                    configuration: configuration,
                    keyboardPatterns: keyboardPatterns
                ) { candidate in
                    try Task.checkCancellation()
                    guard generatedCount < configuration.maximumResults else {
                        wasTruncated = true
                        return false
                    }

                    try writer.append(candidate)
                    generatedCount += 1
                    if preview.count < 200 { preview.append(candidate) }

                    let now = Date()
                    if generatedCount - lastProgressCount >= 10_000
                        || now.timeIntervalSince(lastProgressAt) >= 0.25 {
                        lastProgressCount = generatedCount
                        lastProgressAt = now
                        progressHandler(currentProgress())
                    }
                    return true
                }

                if !exhausted || generatedCount >= configuration.maximumResults {
                    wasTruncated = true
                    break generation
                }
            }
        }

        try writer.finish()
        let duration = max(Date().timeIntervalSince(startedAt), 0.000_001)
        progressHandler(
            GenerationProgress(
                generatedCount: generatedCount,
                maximumCount: configuration.maximumResults,
                bytesWritten: writer.totalBytes,
                elapsedSeconds: duration
            )
        )
        completed = true

        return GenerationSummary(
            fileURL: request.outputURL,
            generatedCount: generatedCount,
            bytesWritten: writer.totalBytes,
            duration: duration,
            wasTruncated: wasTruncated,
            previewSamples: preview,
            sourceIDs: request.rootDatasets.map(\.descriptor.id)
        )
    }

    private static func loadKeyboardPatterns(
        from dataset: ResolvedPublicDataset?
    ) throws -> [String] {
        guard let dataset else { return [] }
        let reader = try UTF8LineReader(url: dataset.fileURL)
        var values: [String] = []
        values.reserveCapacity(min(dataset.descriptor.lineCount, 1_000))
        while let line = try reader.nextLine() {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !value.isEmpty { values.append(value) }
        }
        return values
    }
}

private final class BufferedLineWriter {
    private let handle: FileHandle
    private var buffer = Data()
    private let flushThreshold = 256 * 1_024
    private(set) var totalBytes: Int64 = 0
    private var isFinished = false

    init(url: URL) throws {
        handle = try FileHandle(forWritingTo: url)
        buffer.reserveCapacity(flushThreshold + 1_024)
    }

    deinit {
        if !isFinished {
            try? handle.close()
        }
    }

    func append(_ line: String) throws {
        let bytes = line.utf8
        buffer.append(contentsOf: bytes)
        buffer.append(0x0A)
        totalBytes += Int64(bytes.count + 1)
        if buffer.count >= flushThreshold {
            try flush()
        }
    }

    func finish() throws {
        guard !isFinished else { return }
        try flush()
        try handle.synchronize()
        try handle.close()
        isFinished = true
    }

    private func flush() throws {
        guard !buffer.isEmpty else { return }
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }
}
