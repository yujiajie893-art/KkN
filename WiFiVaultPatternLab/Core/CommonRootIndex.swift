import Foundation

struct CommonRootIndex: Sendable {
    private struct Bucket: Sendable {
        let category: PublicDatasetCategory
        let displayName: String
        let hashes: Set<UInt64>
        let minimumLength: Int
        let maximumLength: Int
    }

    private let buckets: [Bucket]
    private let keyboardPatterns: [String]

    static func build(from datasets: [ResolvedPublicDataset]) throws -> CommonRootIndex {
        var buckets: [Bucket] = []
        var keyboardPatterns: [String] = []

        for dataset in datasets where dataset.descriptor.analyzerEnabled {
            let reader = try UTF8LineReader(url: dataset.fileURL)
            var hashes = Set<UInt64>()
            hashes.reserveCapacity(dataset.descriptor.lineCount)
            var minimumLength = Int.max
            var maximumLength = 0

            while let line = try reader.nextLine() {
                let value = line
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                guard value.count >= 4, value.count <= 32 else { continue }

                hashes.insert(StableHash64.fnv1a(value))
                minimumLength = min(minimumLength, value.count)
                maximumLength = max(maximumLength, value.count)
                if dataset.descriptor.category == .keyboard {
                    keyboardPatterns.append(value)
                }
            }

            guard !hashes.isEmpty else { continue }
            buckets.append(
                Bucket(
                    category: dataset.descriptor.category,
                    displayName: dataset.descriptor.displayName,
                    hashes: hashes,
                    minimumLength: minimumLength,
                    maximumLength: maximumLength
                )
            )
        }

        keyboardPatterns.sort { left, right in
            left.count == right.count ? left < right : left.count > right.count
        }
        return CommonRootIndex(buckets: buckets, keyboardPatterns: keyboardPatterns)
    }

    func commonRootFindings(in password: String) -> [PatternFinding] {
        let characters = Array(password.lowercased().prefix(256))
        guard characters.count >= 4 else { return [] }

        var findings: [PatternFinding] = []
        for bucket in buckets where bucket.category != .keyboard {
            guard let match = longestMatch(in: characters, bucket: bucket) else { continue }
            findings.append(
                PatternFinding(
                    kind: .commonRoot,
                    matchedText: match,
                    sourceName: bucket.displayName
                )
            )
        }
        return findings
    }

    func keyboardMatch(in password: String) -> String? {
        let lowercased = password.lowercased()
        return keyboardPatterns.first { lowercased.contains($0) }
    }

    private func longestMatch(in characters: [Character], bucket: Bucket) -> String? {
        let upperBound = min(bucket.maximumLength, characters.count)
        guard upperBound >= bucket.minimumLength else { return nil }

        for length in stride(from: upperBound, through: bucket.minimumLength, by: -1) {
            for start in 0...(characters.count - length) {
                let candidate = String(characters[start..<(start + length)])
                if bucket.hashes.contains(StableHash64.fnv1a(candidate)) {
                    return candidate
                }
            }
        }
        return nil
    }
}
