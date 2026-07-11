import Foundation
import SwiftUI

@MainActor
final class PatternLabViewModel: ObservableObject {
    @Published var configuration = GeneratorConfiguration()
    @Published private(set) var datasetStates: [DatasetViewState] = []
    @Published private(set) var selectedDatasetIDs = Set<String>()
    @Published private(set) var packVersion = "—"
    @Published private(set) var packByteCount: Int64 = 0
    @Published private(set) var resourceStatusText = "正在读取本地资源包…"
    @Published private(set) var indexStatusText = "词根索引尚未载入"

    @Published private(set) var generationState: GenerationState = .idle
    @Published private(set) var generationProgress = GenerationProgress()
    @Published private(set) var generationSummary: GenerationSummary?
    @Published private(set) var generationStatusText = "选择来源和规则后开始生成"

    @Published var analysisInput = ""
    @Published private(set) var analysis = PasswordAnalysis.empty

    @Published private(set) var importedTextResult: TextImportResult?
    @Published private(set) var importedTextStatus = "尚未导入外部 TXT"
    @Published var useImportedText = false

    private var snapshot: PublicResourcePackSnapshot?
    private var commonRootIndex: CommonRootIndex?
    private var resourceTask: Task<Void, Never>?
    private var generationWorker: Task<GenerationSummary, Error>?
    private var generationObserver: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?

    init() {
        loadResources()
    }

    deinit {
        resourceTask?.cancel()
        generationWorker?.cancel()
        generationObserver?.cancel()
        analysisTask?.cancel()
    }

    var rootDatasetStates: [DatasetViewState] {
        datasetStates.filter { $0.descriptor.role == .root }
    }

    var validDatasetIDs: Set<String> {
        Set(datasetStates.filter(\.integrity.isValid).map(\.descriptor.id))
    }

    var canGenerate: Bool {
        !generationState.isRunning
            && (!selectedDatasetIDs.intersection(validDatasetIDs).isEmpty || (useImportedText && importedTextResult != nil))
            && configuration.hasEnabledRule
    }

    func isDatasetSelected(_ id: String) -> Bool {
        selectedDatasetIDs.contains(id)
    }

    func setDataset(_ id: String, selected: Bool) {
        guard validDatasetIDs.contains(id) else { return }
        if selected {
            selectedDatasetIDs.insert(id)
        } else {
            selectedDatasetIDs.remove(id)
        }
    }

    func startGeneration() {
        guard let snapshot else {
            generationState = .failed("资源包尚未就绪")
            generationStatusText = "资源包尚未就绪"
            return
        }

        var selectedRoots = snapshot.datasets.filter {
            $0.descriptor.role == .root
                && selectedDatasetIDs.contains($0.descriptor.id)
                && validDatasetIDs.contains($0.descriptor.id)
        }
        if useImportedText, let importedTextResult {
            let descriptor = PublicDatasetDescriptor(
                id: "external_import", displayName: importedTextResult.originalFileName,
                category: .test, role: .root, file: importedTextResult.fileURL.lastPathComponent,
                defaultEnabled: true, analyzerEnabled: false, sourceName: "用户导入", sourceURL: "",
                license: "仅限用户自有或获授权数据", lineCount: importedTextResult.acceptedCount,
                byteCount: (try? FileManager.default.attributesOfItem(atPath: importedTextResult.fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0,
                sha256: "")
            selectedRoots.append(ResolvedPublicDataset(descriptor: descriptor, fileURL: importedTextResult.fileURL))
        }
        guard !selectedRoots.isEmpty else {
            generationState = .failed("未选择可用来源")
            generationStatusText = "请至少选择一个可用来源"
            return
        }
        guard configuration.hasEnabledRule else {
            generationState = .failed("未选择生成规则")
            generationStatusText = "请至少启用一条生成规则"
            return
        }

        generationWorker?.cancel()
        generationObserver?.cancel()
        if let previousURL = generationSummary?.fileURL {
            try? FileManager.default.removeItem(at: previousURL)
        }

        let keyboardDataset = snapshot.datasets.first {
            $0.descriptor.id == "keyboard_patterns"
                && validDatasetIDs.contains($0.descriptor.id)
        }
        let request = StreamingGenerationRequest(
            configuration: configuration,
            rootDatasets: selectedRoots,
            keyboardDataset: keyboardDataset,
            outputURL: makeExportURL()
        )

        generationSummary = nil
        generationProgress = GenerationProgress(
            generatedCount: 0,
            maximumCount: configuration.normalized().maximumResults,
            bytesWritten: 0,
            elapsedSeconds: 0
        )
        generationState = .running
        generationStatusText = "正在流式生成并写入 TXT…"

        let worker = Task.detached(priority: .userInitiated) { [weak self] in
            try await StreamingGenerationEngine.generate(request: request) { progress in
                Task { @MainActor [weak self] in
                    guard let self, self.generationState.isRunning else { return }
                    self.generationProgress = progress
                }
            }
        }
        generationWorker = worker

        generationObserver = Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await worker.value
                guard !Task.isCancelled else { return }
                self.generationSummary = summary
                self.generationProgress = GenerationProgress(
                    generatedCount: summary.generatedCount,
                    maximumCount: self.configuration.normalized().maximumResults,
                    bytesWritten: summary.bytesWritten,
                    elapsedSeconds: summary.duration
                )
                self.generationState = .completed
                self.generationStatusText = summary.wasTruncated
                    ? "已达到设定上限，TXT 可保存到“文件”App"
                    : "全部规则生成完成，TXT 可保存到“文件”App"
            } catch is CancellationError {
                guard !Task.isCancelled else { return }
                self.generationState = .cancelled
                self.generationStatusText = "生成已取消，未保留不完整文件"
            } catch {
                guard !Task.isCancelled else { return }
                self.generationState = .failed(error.localizedDescription)
                self.generationStatusText = error.localizedDescription
            }
        }
    }

    func cancelGeneration() {
        guard generationState.isRunning else { return }
        generationWorker?.cancel()
        generationState = .cancelled
        generationStatusText = "正在停止并清理不完整文件…"
    }

    func clearGeneration() {
        generationObserver?.cancel()
        generationWorker?.cancel()
        if let url = generationSummary?.fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        generationSummary = nil
        generationProgress = GenerationProgress()
        generationState = .idle
        generationStatusText = "选择来源和规则后开始生成"
    }

    func importTextFile(from url: URL) {
        do {
            if let old = importedTextResult?.fileURL { try? FileManager.default.removeItem(at: old) }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PatternLabImports", isDirectory: true)
            let result = try TextDatasetImporter.importFile(at: url, destinationDirectory: directory)
            importedTextResult = result
            useImportedText = true
            importedTextStatus = "已导入 \(result.acceptedCount.formatted()) 条 · \(result.detectedEncoding)" +
                (result.wasTruncated ? " · 已截断至 20,000 条" : "")
        } catch {
            importedTextResult = nil
            useImportedText = false
            importedTextStatus = error.localizedDescription
        }
    }

    func clearImportedText() {
        if let url = importedTextResult?.fileURL { try? FileManager.default.removeItem(at: url) }
        importedTextResult = nil
        useImportedText = false
        importedTextStatus = "尚未导入外部 TXT"
    }

    func updateAnalysis() {
        analysisTask?.cancel()
        let input = analysisInput
        guard !input.isEmpty else {
            analysis = .empty
            return
        }
        let index = commonRootIndex

        analysisTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) {
                RiskScoringEngine.analyze(input, commonRootIndex: index)
            }.value
            guard !Task.isCancelled,
                  let self,
                  self.analysisInput == input else { return }
            self.analysis = result
        }
    }

    func clearAnalysis() {
        analysisTask?.cancel()
        analysisInput = ""
        analysis = .empty
    }

    private func loadResources() {
        resourceTask?.cancel()
        resourceTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loadedSnapshot = try PublicResourcePackLoader.load()
                self.snapshot = loadedSnapshot
                self.packVersion = loadedSnapshot.manifest.packVersion
                self.packByteCount = loadedSnapshot.manifest.datasets
                    .reduce(0) { $0 + $1.byteCount }
                self.datasetStates = loadedSnapshot.manifest.datasets.map {
                    DatasetViewState(descriptor: $0, integrity: .pending)
                }
                self.resourceStatusText = "正在校验资源包完整性…"

                let validation = await Task.detached(priority: .utility) {
                    PublicResourcePackLoader.validate(snapshot: loadedSnapshot)
                }.value
                guard !Task.isCancelled else { return }

                self.datasetStates = self.datasetStates.map { state in
                    var copy = state
                    copy.integrity = validation[state.id] ?? .invalid("缺少校验结果")
                    return copy
                }
                let validIDs = Set(validation.compactMap { id, integrity in
                    integrity.isValid ? id : nil
                })
                self.selectedDatasetIDs = Set(
                    loadedSnapshot.manifest.datasets
                        .filter { $0.defaultEnabled && $0.role == .root && validIDs.contains($0.id) }
                        .map(\.id)
                )
                if self.selectedDatasetIDs.isEmpty,
                   let firstRoot = loadedSnapshot.manifest.datasets.first(where: {
                       $0.role == .root && validIDs.contains($0.id)
                   }) {
                    self.selectedDatasetIDs.insert(firstRoot.id)
                }

                let invalidCount = validation.values.filter { !$0.isValid }.count
                self.resourceStatusText = invalidCount == 0
                    ? "资源包已就绪，全部 \(validation.count) 个文件校验通过"
                    : "有 \(invalidCount) 个资源文件未通过校验"

                self.indexStatusText = "正在建立本地词根指纹索引…"
                let analyzerDatasets = loadedSnapshot.datasets.filter {
                    $0.descriptor.analyzerEnabled && validIDs.contains($0.descriptor.id)
                }
                let index = try await Task.detached(priority: .utility) {
                    try CommonRootIndex.build(from: analyzerDatasets)
                }.value
                guard !Task.isCancelled else { return }
                self.commonRootIndex = index
                self.indexStatusText = "公开词根索引已就绪"
                if !self.analysisInput.isEmpty { self.updateAnalysis() }
            } catch {
                self.resourceStatusText = error.localizedDescription
                self.indexStatusText = "词根索引未载入"
            }
        }
    }

    private func makeExportURL() -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "PatternLab-3.0-\(formatter.string(from: Date())).txt"
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("PatternLabExports", isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
    }
}
