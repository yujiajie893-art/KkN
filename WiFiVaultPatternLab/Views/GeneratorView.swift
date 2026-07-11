import SwiftUI

struct GeneratorView: View {
    @ObservedObject var model: PatternLabViewModel
    @State private var exportItem: ExportDocumentItem?
    @State private var showsImporter = false
    @State private var showsExportConfirmation = false

    private let resultLimits = [10_000, 100_000, 500_000, 1_000_000]

    var body: some View {
        NavigationStack {
            ZStack {
                PatternLabWallpaperBackdrop()
                Form {
                    sourceSection
                    importSection
                    ruleSection
                    limitSection
                    actionSection
                    resultSection
                    boundarySection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("PatternLab 3.0")
            .sheet(item: $exportItem) { item in
                FileExportPicker(fileURL: item.url) { exported in
                    if exported { showsExportConfirmation = true }
                }
            }
            .sheet(isPresented: $showsImporter) {
                FileImportPicker { url in
                    showsImporter = false
                    model.importTextFile(from: url)
                }
            }
            .alert("导出完成", isPresented: $showsExportConfirmation) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("TXT 已保存。请打开系统“文件”App，在你刚才选择的位置找到导出的文件。")
            }
        }
    }

    private var sourceSection: some View {
        Section("词根来源") {
            ForEach(model.rootDatasetStates) { state in
                Toggle(
                    isOn: Binding(
                        get: { model.isDatasetSelected(state.id) },
                        set: { model.setDataset(state.id, selected: $0) }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(state.descriptor.displayName)
                            if state.descriptor.id == "test_dataset" {
                                Text("性能测试")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.orange.opacity(0.18), in: Capsule())
                            }
                        }
                        Text("\(state.descriptor.lineCount.formatted()) 条 · \(state.descriptor.license)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!state.integrity.isValid || model.generationState.isRunning)
            }

            Text(model.resourceStatusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }


    private var importSection: some View {
        Section("外部 TXT") {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showsImporter = true
            } label: {
                Label("导入 TXT 文件", systemImage: "doc.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Text(model.importedTextStatus).font(.footnote).foregroundStyle(.secondary)
            if let result = model.importedTextResult {
                Toggle("作为生成来源", isOn: $model.useImportedText)
                LabeledContent("有效内容", value: result.acceptedCount.formatted())
                LabeledContent("自动去重", value: result.duplicateCount.formatted())
                LabeledContent("忽略空行", value: result.ignoredBlankCount.formatted())
                LabeledContent("跳过超长行", value: result.skippedLongLineCount.formatted())
                if result.wasTruncated {
                    Label("超过 20,000 条，已按上限截断", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Button("移除导入文件", role: .destructive) { model.clearImportedText() }
            }
        }
    }

    private var ruleSection: some View {
        Section("生成规则") {
            Toggle("保留原始词根", isOn: $model.configuration.includeBaseRoot)

            Toggle("词根 + 年份", isOn: $model.configuration.includeYears)
            if model.configuration.includeYears {
                Stepper(
                    "起始年份：\(model.configuration.startYear)",
                    value: $model.configuration.startYear,
                    in: 1900...2100
                )
                Stepper(
                    "结束年份：\(model.configuration.endYear)",
                    value: $model.configuration.endYear,
                    in: 1900...2100
                )
            }

            Toggle("词根 + 数字后缀", isOn: $model.configuration.includeNumericSuffix)
            if model.configuration.includeNumericSuffix {
                Stepper(
                    "数字起点：\(model.configuration.numericStart)",
                    value: $model.configuration.numericStart,
                    in: 0...9_999
                )
                Stepper(
                    "数字终点：\(model.configuration.numericEnd)",
                    value: $model.configuration.numericEnd,
                    in: 0...9_999
                )
            }

            Toggle("词根 + 日期（有效月日）", isOn: $model.configuration.includeDates)
            Toggle("词根 + 键盘模式", isOn: $model.configuration.includeKeyboardCombinations)
            Toggle("大小写变体", isOn: $model.configuration.includeCaseVariants)
            Toggle("特殊字符变体", isOn: $model.configuration.includeSpecialCharacterVariants)
        }
        .disabled(model.generationState.isRunning)
    }

    private var limitSection: some View {
        Section("单次上限") {
            Picker("最大结果数", selection: $model.configuration.maximumResults) {
                ForEach(resultLimits, id: \.self) { limit in
                    Text(limit.formatted()).tag(limit)
                }
            }
            .pickerStyle(.menu)
            .disabled(model.generationState.isRunning)

            Text("引擎直接写入临时 TXT，仅保留前 200 条预览；不会在内存保存完整结果数组。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var actionSection: some View {
        Section {
            if model.generationState.isRunning {
                Button(role: .destructive) {
                    model.cancelGeneration()
                } label: {
                    Label("停止生成", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
            } else {
                Button {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    model.startGeneration()
                } label: {
                    Label("开始流式生成", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canGenerate)
            }

            Text(model.generationStatusText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if model.generationState.isRunning {
                ProgressView(value: model.generationProgress.fractionCompleted)
                LabeledContent("已生成", value: model.generationProgress.generatedCount.formatted())
                LabeledContent(
                    "当前速度",
                    value: "\(Int(model.generationProgress.ratePerSecond.rounded()).formatted()) 条/秒"
                )
                LabeledContent(
                    "已写入",
                    value: formattedBytes(model.generationProgress.bytesWritten)
                )
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let summary = model.generationSummary {
            Section("生成结果") {
                LabeledContent("结果数量", value: summary.generatedCount.formatted())
                LabeledContent("TXT 体积", value: formattedBytes(summary.bytesWritten))
                LabeledContent("耗时", value: String(format: "%.2f 秒", summary.duration))
                LabeledContent(
                    "平均速度",
                    value: "\(Int(summary.ratePerSecond.rounded()).formatted()) 条/秒"
                )
                if summary.wasTruncated {
                    Label("已按设定上限停止", systemImage: "checkmark.circle")
                        .foregroundStyle(.orange)
                }

                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    exportItem = ExportDocumentItem(url: summary.fileURL)
                } label: {
                    Label("一键导出到“文件”App", systemImage: "folder.badge.plus")
                        .font(.title3.bold())
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button("清空结果", role: .destructive) {
                    model.clearGeneration()
                }
            }

            Section("预览（前 \(summary.previewSamples.count) 条）") {
                ForEach(Array(summary.previewSamples.enumerated()), id: \.offset) { index, sample in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                        Text(sample)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var boundarySection: some View {
        Section("离线边界") {
            Text("只生成结构样本并写入本地文件；不读取 SSID，不调用网络连接接口，不把候选传给任何验证模块。请仅用于自有或已获授权数据的离线健康度测试。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func formattedBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
