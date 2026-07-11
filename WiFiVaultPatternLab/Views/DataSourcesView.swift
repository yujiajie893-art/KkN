import SwiftUI

struct DataSourcesView: View {
    @ObservedObject var model: PatternLabViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                PatternLabWallpaperBackdrop()
                List {
                    Section("资源包") {
                        LabeledContent("版本", value: model.packVersion)
                        LabeledContent("数据体积", value: formattedBytes(model.packByteCount))
                        LabeledContent("文件数量", value: model.datasetStates.count.formatted())
                        Text(model.resourceStatusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("内置数据") {
                        ForEach(model.datasetStates) { state in
                            datasetRow(state)
                        }
                    }

                    Section("隐私与来源") {
                        Text("所有检测和生成都在本机完成。App 不联网、不采集输入、不包含泄露密码库，也不具备 Wi‑Fi 自动验证接口。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("测试来源由项目方提供，公开发布前仍应保留其再分发许可证明。")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("数据来源")
        }
    }

    private func datasetRow(_ state: DatasetViewState) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(state.descriptor.displayName)
                    .font(.headline)
                Spacer()
                integrityLabel(state.integrity)
            }
            Text("\(state.descriptor.lineCount.formatted()) 条 · \(formattedBytes(state.descriptor.byteCount))")
                .font(.subheadline.monospacedDigit())
            Text(state.descriptor.sourceName)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Text(state.descriptor.license)
                    .font(.caption)
                Spacer()
                if let url = URL(string: state.descriptor.sourceURL),
                   !state.descriptor.sourceURL.isEmpty {
                    Link("来源", destination: url)
                        .font(.caption)
                }
            }
            Text("SHA-256  \(state.descriptor.sha256)")
                .textSelection(.enabled)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func integrityLabel(_ integrity: DatasetIntegrity) -> some View {
        switch integrity {
        case .pending:
            Label("校验中", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .valid:
            Label("完整", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case let .invalid(message):
            Label(message, systemImage: "xmark.octagon.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func formattedBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
