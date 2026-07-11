import Foundation

@main
struct PatternLabCoreTests {
    static func main() async throws {
        testConfigurationNormalization()
        testDateTokenCount()
        try testRuleExpansion()
        testStructureDetection()
        testRiskScoring()
        try testManifestDecoding()
        try testLineReader()
        try await testMillionScaleStreamingPath()
        print("PatternLab 3.0 core tests: 8/8 passed")
    }

    private static func testConfigurationNormalization() {
        var configuration = GeneratorConfiguration()
        configuration.startYear = 2030
        configuration.endYear = 1980
        configuration.numericStart = 9_999
        configuration.numericEnd = 1
        configuration.maximumResults = 9_000_000

        let normalized = configuration.normalized()
        precondition(normalized.startYear == 1980)
        precondition(normalized.endYear == 2030)
        precondition(normalized.numericStart == 1)
        precondition(normalized.numericEnd == 9_999)
        precondition(normalized.maximumResults == 1_000_000)
    }

    private static func testDateTokenCount() {
        precondition(PatternRuleExpander.compactDateTokens.count == 366)
        precondition(PatternRuleExpander.compactDateTokens.contains("0229"))
        precondition(!PatternRuleExpander.compactDateTokens.contains("0230"))
    }

    private static func testRuleExpansion() throws {
        var configuration = GeneratorConfiguration()
        configuration.includeBaseRoot = true
        configuration.includeYears = true
        configuration.startYear = 2026
        configuration.endYear = 2026
        configuration.includeNumericSuffix = false
        configuration.includeDates = false
        configuration.includeKeyboardCombinations = false
        configuration.includeCaseVariants = false
        configuration.includeSpecialCharacterVariants = false

        var values: [String] = []
        let completed = try PatternRuleExpander.forEachCandidate(
            root: "atlas",
            configuration: configuration,
            keyboardPatterns: []
        ) { candidate in
            values.append(candidate)
            return true
        }
        precondition(completed)
        precondition(values == ["atlas", "atlas2026"])
    }

    private static func testStructureDetection() {
        let findings = PasswordStructureAnalyzer.findings(in: "qwerty-1234-2026-aaa")
        let kinds = Set(findings.map(\.kind))
        precondition(kinds.contains(.year))
        precondition(kinds.contains(.keyboardSequence))
        precondition(kinds.contains(.repeatedCharacters))
        precondition(kinds.contains(.consecutiveDigits))

        let dateFindings = PasswordStructureAnalyzer.findings(in: "sample-2024/02/29")
        precondition(dateFindings.contains { $0.kind == .dateFormat })
        let invalidLeapDate = PasswordStructureAnalyzer.findings(in: "sample-2026/02/29")
        precondition(!invalidLeapDate.contains { $0.kind == .dateFormat })
        let invalidDate = PasswordStructureAnalyzer.findings(in: "sample-0230")
        precondition(!invalidDate.contains { $0.kind == .dateFormat })
    }

    private static func testRiskScoring() {
        let weak = RiskScoringEngine.analyze("12345678")
        let strong = RiskScoringEngine.analyze("fR7!kP2#vQ9@Lm")
        precondition((0...100).contains(weak.strengthScore))
        precondition((0...100).contains(strong.strengthScore))
        precondition(strong.strengthScore > weak.strengthScore)
        precondition(strong.estimatedEntropyBits > weak.estimatedEntropyBits)
    }

    private static func testManifestDecoding() throws {
        let json = #"{"schemaVersion":1,"packId":"PatternLabPublicPack","packVersion":"3.0.0","generatedAt":"2026-07-11T00:00:00Z","datasets":[]}"#
        let manifest = try JSONDecoder().decode(PublicPackManifest.self, from: Data(json.utf8))
        precondition(manifest.schemaVersion == 1)
        precondition(manifest.packVersion == "3.0.0")
    }

    private static func testLineReader() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("lines.txt")
        try Data("one\r\ntwo\nthree".utf8).write(to: url)

        let reader = try UTF8LineReader(url: url, chunkSize: 4_096)
        let first = try reader.nextLine()
        let second = try reader.nextLine()
        let third = try reader.nextLine()
        let end = try reader.nextLine()
        precondition(first == "one")
        precondition(second == "two")
        precondition(third == "three")
        precondition(end == nil)
    }

    private static func testMillionScaleStreamingPath() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let rootsURL = directory.appendingPathComponent("roots.txt")
        let roots = (0..<101).map { "root\($0)" }.joined(separator: "\n") + "\n"
        try Data(roots.utf8).write(to: rootsURL)

        let descriptor = PublicDatasetDescriptor(
            id: "test_roots",
            displayName: "Test Roots",
            category: .test,
            role: .root,
            file: "roots.txt",
            defaultEnabled: true,
            analyzerEnabled: false,
            sourceName: "test",
            sourceURL: "",
            license: "test",
            lineCount: 101,
            byteCount: Int64(Data(roots.utf8).count),
            sha256: ""
        )

        var configuration = GeneratorConfiguration()
        configuration.includeBaseRoot = false
        configuration.includeYears = false
        configuration.includeNumericSuffix = true
        configuration.numericStart = 1
        configuration.numericEnd = 9_999
        configuration.includeDates = false
        configuration.includeKeyboardCombinations = false
        configuration.includeCaseVariants = false
        configuration.includeSpecialCharacterVariants = false
        configuration.maximumResults = 1_000_000

        let outputURL = directory.appendingPathComponent("million.txt")
        let summary = try await StreamingGenerationEngine.generate(
            request: StreamingGenerationRequest(
                configuration: configuration,
                rootDatasets: [ResolvedPublicDataset(descriptor: descriptor, fileURL: rootsURL)],
                keyboardDataset: nil,
                outputURL: outputURL
            )
        )

        precondition(summary.generatedCount == 1_000_000)
        precondition(summary.wasTruncated)
        precondition(summary.previewSamples.count == 200)
        precondition(summary.bytesWritten > 1_000_000)
        precondition(FileManager.default.fileExists(atPath: outputURL.path))
        precondition(summary.ratePerSecond > 10_000)
        print(String(format: "Streaming benchmark: %.0f lines/s, %.2f MB", summary.ratePerSecond, Double(summary.bytesWritten) / 1_000_000))
    }
}
