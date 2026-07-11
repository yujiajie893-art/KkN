import CryptoKit
import Foundation

enum PublicResourcePackError: LocalizedError {
    case bundleMissing
    case manifestMissing
    case unsupportedSchema(Int)
    case invalidPackIdentifier
    case duplicateDatasetIdentifier(String)
    case unsafeDatasetPath(String)
    case datasetMissing(String)

    var errorDescription: String? {
        switch self {
        case .bundleMissing: return "找不到 PatternLabPublicPack.bundle。"
        case .manifestMissing: return "资源包缺少 manifest.json。"
        case let .unsupportedSchema(version): return "不支持资源清单版本 \(version)。"
        case .invalidPackIdentifier: return "资源包标识不正确。"
        case let .duplicateDatasetIdentifier(id): return "资源清单包含重复 ID：\(id)。"
        case let .unsafeDatasetPath(path): return "资源路径不安全：\(path)。"
        case let .datasetMissing(id): return "资源文件不存在：\(id)。"
        }
    }
}

enum PublicResourcePackLoader {
    static func load(from appBundle: Bundle = .main) throws -> PublicResourcePackSnapshot {
        guard let bundleURL = appBundle.url(
            forResource: "PatternLabPublicPack",
            withExtension: "bundle"
        ) else {
            throw PublicResourcePackError.bundleMissing
        }
        return try load(bundleURL: bundleURL)
    }

    static func load(bundleURL: URL) throws -> PublicResourcePackSnapshot {
        let manifestURL = bundleURL.appendingPathComponent("manifest.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw PublicResourcePackError.manifestMissing
        }

        let manifestData = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
        let manifest = try JSONDecoder().decode(PublicPackManifest.self, from: manifestData)
        guard manifest.schemaVersion == 1 else {
            throw PublicResourcePackError.unsupportedSchema(manifest.schemaVersion)
        }
        guard manifest.packId == "PatternLabPublicPack" else {
            throw PublicResourcePackError.invalidPackIdentifier
        }

        let standardizedBundle = bundleURL.standardizedFileURL
        var seenIDs = Set<String>()
        var resolved: [ResolvedPublicDataset] = []
        resolved.reserveCapacity(manifest.datasets.count)

        for descriptor in manifest.datasets {
            guard seenIDs.insert(descriptor.id).inserted else {
                throw PublicResourcePackError.duplicateDatasetIdentifier(descriptor.id)
            }
            let fileURL = bundleURL
                .appendingPathComponent(descriptor.file, isDirectory: false)
                .standardizedFileURL
            guard fileURL.path.hasPrefix(standardizedBundle.path + "/") else {
                throw PublicResourcePackError.unsafeDatasetPath(descriptor.file)
            }
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw PublicResourcePackError.datasetMissing(descriptor.id)
            }
            resolved.append(ResolvedPublicDataset(descriptor: descriptor, fileURL: fileURL))
        }

        return PublicResourcePackSnapshot(
            bundleURL: bundleURL,
            manifest: manifest,
            datasets: resolved
        )
    }

    static func validate(
        snapshot: PublicResourcePackSnapshot
    ) -> [String: DatasetIntegrity] {
        Dictionary(uniqueKeysWithValues: snapshot.datasets.map { dataset in
            do {
                let data = try Data(contentsOf: dataset.fileURL, options: [.mappedIfSafe])
                guard Int64(data.count) == dataset.descriptor.byteCount else {
                    return (dataset.descriptor.id, .invalid("文件大小与清单不一致"))
                }

                var lineCount = data.reduce(into: 0) { count, byte in
                    if byte == 0x0A { count += 1 }
                }
                if !data.isEmpty, data.last != 0x0A { lineCount += 1 }
                guard lineCount == dataset.descriptor.lineCount else {
                    return (dataset.descriptor.id, .invalid("行数与清单不一致"))
                }

                let digest = SHA256.hash(data: data)
                    .map { String(format: "%02x", $0) }
                    .joined()
                guard digest == dataset.descriptor.sha256.lowercased() else {
                    return (dataset.descriptor.id, .invalid("SHA-256 校验失败"))
                }
                return (dataset.descriptor.id, .valid)
            } catch {
                return (dataset.descriptor.id, .invalid(error.localizedDescription))
            }
        })
    }
}
