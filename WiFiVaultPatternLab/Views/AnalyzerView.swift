import SwiftUI

struct AnalyzerView: View {
    @ObservedObject var model: PatternLabViewModel
    @State private var showsPassword = false

    var body: some View {
        NavigationStack {
            ZStack {
                PatternLabWallpaperBackdrop()
                Form {
                    inputSection
                    if !model.analysis.isEmpty {
                        scoreSection
                        findingsSection
                        recommendationsSection
                    }
                    scopeSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("本地模式分析")
        }
    }

    private var inputSection: some View {
        Section("输入密码") {
            Group {
                if showsPassword {
                    TextField("仅在本机内存中分析", text: $model.analysisInput)
                } else {
                    SecureField("仅在本机内存中分析", text: $model.analysisInput)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.body.monospaced())
            .onChange(of: model.analysisInput) { _ in
                model.updateAnalysis()
            }

            Toggle("显示输入", isOn: $showsPassword)
            if !model.analysisInput.isEmpty {
                Button("清空", role: .destructive) {
                    model.clearAnalysis()
                }
            }
        }
    }

    private var scoreSection: some View {
        Section("结构强度") {
            HStack {
                Spacer()
                ZStack {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 18)
                    Circle()
                        .trim(from: 0, to: Double(model.analysis.strengthScore) / 100)
                        .stroke(
                            AngularGradient(colors: [.red, .orange, .yellow, .green], center: .center),
                            style: StrokeStyle(lineWidth: 18, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(model.analysis.strengthScore)")
                            .font(.system(size: 46, weight: .black, design: .rounded))
                        Text(model.analysis.riskLevel.title).font(.headline).foregroundStyle(riskColor)
                    }
                }
                .frame(width: 180, height: 180)
                .accessibilityLabel("强度评分 \(model.analysis.strengthScore) 分")
                Spacer()
            }
            LabeledContent("朴素熵估算", value: String(format: "%.1f bits", model.analysis.estimatedEntropyBits))
            Text("评分用于识别结构弱点，不等于线上系统的真实破解时间，也不会查询泄露库。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var findingsSection: some View {
        Section("模式命中") {
            if model.analysis.findings.isEmpty {
                Label("未命中当前六类常见结构", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                ForEach(model.analysis.findings) { finding in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("命中：\(finding.matchedText)").font(.body.monospaced()).textSelection(.enabled)
                            Text(finding.kind.explanation).font(.footnote).foregroundStyle(.secondary)
                            if let source = finding.sourceName { Text("来源：\(source)").font(.caption) }
                        }.padding(.vertical, 6)
                    } label: {
                        Label(finding.kind.title, systemImage: "exclamationmark.shield.fill")
                            .font(.headline).foregroundStyle(riskColor)
                    }
                }
            }
        }
    }

    private var recommendationsSection: some View {
        Section("改进建议") {
            ForEach(Array(model.analysis.recommendations.enumerated()), id: \.offset) { _, item in
                Label(item, systemImage: "arrow.up.right.circle")
            }
        }
    }

    private var scopeSection: some View {
        Section("检测范围") {
            Text("公开词根、年份、有效日期、键盘序列、重复字符、连续数字。输入不会写入磁盘，不保存历史记录。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(model.indexStatusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var riskColor: Color {
        switch model.analysis.riskLevel {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        }
    }
}
