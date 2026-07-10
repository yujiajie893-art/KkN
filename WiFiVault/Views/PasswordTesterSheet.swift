import SwiftUI
import UniformTypeIdentifiers

struct PasswordTesterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var tester: PasswordTesterManager
    @EnvironmentObject private var autoConnect: AutoConnectManager
    @EnvironmentObject private var accessibilityFill:
        AccessibilityAutoFillManager

    @State private var ssid = ""
    @State private var isShowingImporter = false
    @State private var revealCurrentPassword = false
    @State private var selectedResultID: UUID?
    @State private var showAccessibilitySettings = false
    @State private var errorMessage: String?

    private var selectedResult:
        PasswordTesterManager.PasswordResult?
    {
        guard let selectedResultID else { return nil }

        return tester.results.first {
            $0.id == selectedResultID
        }
    }

    var body: some View {
        NavigationStack {
            List {
                targetSection
                importSection
                auditSection

                if !tester.results.isEmpty {
                    summarySection
                    resultSection
                }

                accessibilityGuidedSection
                verificationSection
                logSection
                safetySection
            }
            .navigationTitle("密码强度审计")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        tester.stopAudit()
                        accessibilityFill.stop()
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $isShowingImporter,
                allowedContentTypes: [.plainText],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .onChange(
                of: accessibilityFill.autoAdvanceEnabled
            ) { _ in
                accessibilityFill.updateAutoAdvanceSetting()
            }
            .onChange(of: autoConnect.state) { newState in
                switch newState {
                case .connected:
                    if let connectedSSID =
                        autoConnect.connectedSSID
                    {
                        accessibilityFill
                            .handleVerificationSuccess(
                                ssid: connectedSSID
                            )
                    }

                case .failed:
                    accessibilityFill
                        .handleVerificationFailure()

                case .cancelled:
                    accessibilityFill
                        .handleVerificationCancellation()

                default:
                    break
                }
            }
            .alert(
                "操作失败",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: {
                        if !$0 {
                            errorMessage = nil
                        }
                    }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "发生未知错误。")
            }
            .alert(item: $tester.notice) { notice in
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    dismissButton: .default(Text("好"))
                )
            }
            .alert(item: $autoConnect.notice) { notice in
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }

    private var targetSection: some View {
        Section {
            TextField(
                "输入自家 Wi-Fi 名称（SSID）",
                text: $ssid
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityLabel("Wi-Fi 网络名称")
            .accessibilityHint(
                "输入需要验证的自家网络名称。"
            )
        } header: {
            Text("审计目标")
        } footer: {
            Text(
                "SSID 仅用于离线检查和用户明确触发的"
                + "单次连接验证，不会扫描附近网络。"
            )
        }
    }

    private var importSection: some View {
        Section {
            Button {
                isShowingImporter = true
            } label: {
                Label(
                    tester.loadedFileName == nil
                    ? "导入 TXT 密码列表"
                    : "重新导入 TXT",
                    systemImage: "doc.badge.plus"
                )
            }
            .disabled(tester.isAuditing)
            .accessibilityHint(
                "打开系统文件选择器。"
                + "文本文件每行应包含一个候选密码。"
            )

            if let fileName = tester.loadedFileName {
                LabeledContent("文件") {
                    Text(fileName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                LabeledContent("唯一候选项") {
                    Text("\(tester.passwords.count)")
                        .monospacedDigit()
                }

                Button("清除导入数据", role: .destructive) {
                    selectedResultID = nil
                    accessibilityFill.reset()
                    tester.clearImportedData()
                }
                .disabled(tester.isAuditing)
            }
        } header: {
            Text("本地文件")
        } footer: {
            Text(
                "TXT 每行一个候选密码。"
                + "文件只在本机读取，不会上传。"
            )
        }
    }

    private var auditSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(
                        tester.statusText,
                        systemImage: statusIcon
                    )
                    .font(.subheadline.weight(.medium))

                    Spacer()

                    Text("\(Int(tester.progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: tester.progress)
                    .tint(progressTint)
                    .accessibilityLabel("离线分析进度")
                    .accessibilityValue(
                        "\(Int(tester.progress * 100))%"
                    )

                if tester.isAuditing {
                    Divider()

                    Toggle(
                        "显示当前分析密码",
                        isOn: $revealCurrentPassword
                    )
                    .font(.subheadline)

                    LabeledContent("当前分析") {
                        Text(currentPasswordDisplay)
                            .font(
                                .system(
                                    .caption,
                                    design: .monospaced
                                )
                            )
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 12) {
                    if tester.isAuditing {
                        Button(role: .destructive) {
                            tester.stopAudit()
                        } label: {
                            Label(
                                "停止分析",
                                systemImage: "stop.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        selectedResultID = nil
                        tester.startOfflineAudit(ssid: ssid)
                    } label: {
                        Label(
                            tester.isAuditing
                            ? "分析中…"
                            : "开始离线审计",
                            systemImage: "shield.checkered"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        tester.passwords.isEmpty
                        || tester.isAuditing
                    )
                }
            }
            .padding(.vertical, 5)
        } header: {
            Text("离线分析")
        } footer: {
            Text(
                "该过程只计算长度、字符组合、常见模式"
                + "和估算搜索空间，不会尝试连接 Wi-Fi。"
            )
        }
    }

    private var summarySection: some View {
        Section("风险概览") {
            HStack {
                RiskCountView(
                    title: "极高",
                    count: tester.criticalCount,
                    symbol: "exclamationmark.octagon.fill",
                    color: .red
                )

                RiskCountView(
                    title: "高",
                    count: tester.highCount,
                    symbol:
                        "exclamationmark.triangle.fill",
                    color: .orange
                )

                RiskCountView(
                    title: "中",
                    count: tester.mediumCount,
                    symbol: "minus.circle.fill",
                    color: .yellow
                )

                RiskCountView(
                    title: "较低",
                    count: tester.lowCount,
                    symbol: "checkmark.shield.fill",
                    color: .green
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }

    private var resultSection: some View {
        Section {
            ForEach(
                Array(tester.sortedResults.prefix(200))
            ) { result in
                Button {
                    selectedResultID = result.id
                } label: {
                    VStack(
                        alignment: .leading,
                        spacing: 7
                    ) {
                        HStack {
                            Text(result.password)
                                .font(
                                    .system(
                                        .body,
                                        design: .monospaced
                                    )
                                )
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer()

                            Text(result.riskLevel.title)
                                .font(
                                    .caption.weight(
                                        .semibold
                                    )
                                )
                                .foregroundStyle(
                                    riskColor(
                                        result.riskLevel
                                    )
                                )
                        }

                        ProgressView(
                            value: Double(result.score),
                            total: 100
                        )
                        .tint(
                            riskColor(result.riskLevel)
                        )

                        HStack {
                            Text(
                                "评分 \(result.score)/100"
                            )
                            Text(
                                "估算熵 "
                                + "\(Int(result.estimatedEntropyBits)) bit"
                            )
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Text(
                            result.reasons.joined(
                                separator: " · "
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "密码候选，"
                    + "\(result.riskLevel.title)，"
                    + "评分 \(result.score) 分"
                )
                .accessibilityHint(
                    "双击后可在下方进行一次连接验证。"
                )
            }
        } header: {
            Text("风险排序（最多显示前 200 项）")
        } footer: {
            Text(
                "评分越低，代表越容易被猜中"
                + "或包含明显弱模式。"
            )
        }
    }

    private var accessibilityGuidedSection: some View {
        Section {
            Toggle(
                "启用语音提示",
                isOn: $accessibilityFill.speechEnabled
            )
            .accessibilityHint(
                "开启后，系统会朗读候选位置和连接状态。"
            )

            Toggle(
                "每 3 秒自动选择下一个候选",
                isOn:
                    $accessibilityFill.autoAdvanceEnabled
            )
            .accessibilityHint(
                "仅自动移动候选位置，"
                + "不会自动提交密码连接。"
            )

            DisclosureGroup(
                "语音提示设置",
                isExpanded: $showAccessibilitySettings
            ) {
                Toggle(
                    "朗读密码内容",
                    isOn:
                        $accessibilityFill.speakPasswordAloud
                )
                .accessibilityHint(
                    "开启后密码会通过扬声器逐字符朗读，"
                    + "周围的人可能听到。"
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("语速")
                        Spacer()
                        Text(
                            accessibilityFill.speechRate,
                            format:
                                .number.precision(
                                    .fractionLength(2)
                                )
                        )
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    }

                    Slider(
                        value:
                            $accessibilityFill.speechRate,
                        in: 0.35...0.58
                    )
                    .accessibilityLabel("语音速度")
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("音调")
                        Spacer()
                        Text(
                            accessibilityFill.speechPitch,
                            format:
                                .number.precision(
                                    .fractionLength(1)
                                )
                        )
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    }

                    Slider(
                        value:
                            $accessibilityFill.speechPitch,
                        in: 0.7...1.5
                    )
                    .accessibilityLabel("语音音调")
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("音量")
                        Spacer()
                        Text(
                            accessibilityFill.speechVolume,
                            format:
                                .percent.precision(
                                    .fractionLength(0)
                                )
                        )
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    }

                    Slider(
                        value:
                            $accessibilityFill.speechVolume,
                        in: 0...1
                    )
                    .accessibilityLabel("语音提示音量")
                }

                Button {
                    accessibilityFill
                        .announceSettingsPreview()
                } label: {
                    Label(
                        "播放语音预览",
                        systemImage:
                            "speaker.wave.2.fill"
                    )
                }
            }

            if accessibilityFill.isRunning
                || accessibilityFill.state == .succeeded
                || accessibilityFill.state == .exhausted
                || accessibilityFill.state == .stopped
            {
                guidedStatusPanel
            } else {
Button {
    accessibilityFill.start(with: tester.passwords)
    // 🔥 自动验证增强：开启后全自动循环尝试每个密码
    accessibilityFill.autoVerifyEnabled = true
    accessibilityFill.autoVerifyDelay = 2.5  // 每2.5秒试一个
} label: {
    Label(
        "🚀 全自动填充（循环验证）",
        systemImage: "bolt.circle.fill"
    )
    .frame(maxWidth: .infinity)
}
.buttonStyle(.borderedProminent)
.controlSize(.large)
.disabled(tester.passwords.isEmpty)
.accessibilityHint(
    "自动尝试每个候选密码直到连接成功"
)
            }
        } header: {
            Text("无障碍辅助填充")
        } footer: {
            Text(
                "候选项会自动按顺序朗读和切换。"
                + "盲人用户可让 VoiceOver 焦点停留在"
                + "“验证当前密码”按钮并重复双击，"
                + "也可使用系统语音控制说出按钮名称。"
                + "每一次联网验证仍由用户明确触发。"
            )
        }
    }

    private var guidedStatusPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label(
                    accessibilityFill.statusText,
                    systemImage:
                        accessibilityStatusIcon
                )
                .font(.subheadline.weight(.medium))

                Spacer()

                Text(
                    "\(accessibilityFill.currentNumber)"
                    + "/\(accessibilityFill.totalCount)"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            ProgressView(
                value: accessibilityFill.progress
            )
            .accessibilityLabel("候选密码位置")
            .accessibilityValue(
                "第 \(accessibilityFill.currentNumber) 个，"
                + "共 \(accessibilityFill.totalCount) 个"
            )

            if let password =
                accessibilityFill.currentPassword
            {
                LabeledContent("当前密码") {
                    Text(
                        accessibilityFill
                            .speakPasswordAloud
                        ? password
                        : maskedPassword(password)
                    )
                    .font(
                        .system(
                            .caption,
                            design: .monospaced
                        )
                    )
                    .lineLimit(1)
                }
                .accessibilityElement(
                    children: .combine
                )
                .accessibilityLabel("当前候选密码")
                .accessibilityValue(
                    accessibilityFill
                        .speakPasswordAloud
                    ? password
                    : "密码内容已隐藏"
                )
            }

            Button {
                verifyAccessibleCurrentPassword()
            } label: {
                Label(
                    accessibilityFill.isVerifying
                    ? "正在验证…"
                    : "验证当前密码",
                    systemImage: "wifi"
                )
                .font(.body.weight(.semibold))
                .frame(
                    maxWidth: .infinity,
                    minHeight: 54
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                accessibilityFill.currentPassword == nil
                || accessibilityFill.isVerifying
                || autoConnect.isRunning
                || ssid.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            )
            .accessibilityHint(
                "验证当前语音提示的密码一次。"
                + "该按钮不会自动验证后续密码。"
            )
            .accessibilityAction(
                named: Text("重复朗读当前候选")
            ) {
                accessibilityFill
                    .repeatCurrentAnnouncement()
            }
            .accessibilityAction(
                named: Text("选择下一个候选")
            ) {
                accessibilityFill
                    .moveToNextCandidate()
            }

            HStack(spacing: 10) {
                Button {
                    accessibilityFill
                        .moveToPreviousCandidate()
                } label: {
                    Label(
                        "上一个",
                        systemImage: "chevron.left"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(
                    !accessibilityFill.canMoveBackward
                )

                Button {
                    accessibilityFill
                        .repeatCurrentAnnouncement()
                } label: {
                    Label(
                        "重播",
                        systemImage:
                            "speaker.wave.2"
                    )
                }
                .buttonStyle(.bordered)

                Button {
                    accessibilityFill
                        .moveToNextCandidate()
                } label: {
                    Label(
                        "下一个",
                        systemImage: "chevron.right"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(
                    !accessibilityFill.canMoveForward
                )
            }

            HStack(spacing: 10) {
                if autoConnect.isRunning {
                    Button(
                        "停止本次验证",
                        role: .destructive
                    ) {
                        autoConnect.stop()
                    }
                    .frame(maxWidth: .infinity)
                }

                Button(
                    "停止辅助填充",
                    role: .destructive
                ) {
                    accessibilityFill.stop()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
    }

    private var verificationSection: some View {
        Section {
            if let selectedResult {
                LabeledContent("所选密码") {
                    Text(selectedResult.password)
                        .font(
                            .system(
                                .caption,
                                design: .monospaced
                            )
                        )
                        .lineLimit(1)
                }

                Button {
                    verify(
                        password:
                            selectedResult.password
                    )
                } label: {
                    Label(
                        autoConnect.isRunning
                        ? "系统正在处理…"
                        : "仅验证所选密码一次",
                        systemImage: "wifi"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    ssid.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                    || autoConnect.isRunning
                )
            } else {
                ContentUnavailableView(
                    "尚未选择候选项",
                    systemImage: "hand.tap",
                    description: Text(
                        "视力障碍用户可直接使用上方"
                        + "无障碍辅助填充，"
                        + "无需在风险列表中寻找密码。"
                    )
                )
            }
        } header: {
            Text("普通单次验证")
        } footer: {
            Text(
                "这里保留给不使用辅助模式的用户。"
            )
        }
    }

    private var logSection: some View {
        Section {
            if tester.logs.isEmpty {
                Text("暂无本地日志")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tester.logs.prefix(30)) {
                    entry in
                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {
                        Text(entry.message)
                            .font(.caption)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )

                        Text(
                            entry.date.formatted(
                                date: .abbreviated,
                                time: .standard
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                Button(
                    "清除本地日志",
                    role: .destructive
                ) {
                    tester.clearLogs()
                }
            }
        } header: {
            Text("本地日志")
        } footer: {
            Text(
                "日志保存在 Application Support，"
                + "不会记录密码明文，"
                + "只记录候选指纹和操作摘要。"
            )
        }
    }

    private var safetySection: some View {
        Section {
            Label {
                Text(
                    "辅助模式可以自动朗读和选择候选，"
                    + "但不会自动批量提交网络密码。"
                    + "所有数据和日志只保存在本机。"
                )
                .font(.footnote)
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private var currentPasswordDisplay: String {
        guard !tester.currentPassword.isEmpty else {
            return "—"
        }

        if revealCurrentPassword {
            return tester.currentPassword
        }

        return maskedPassword(tester.currentPassword)
    }

    private var statusIcon: String {
        switch tester.state {
        case .idle:
            return "doc.text"

        case .imported:
            return "checkmark.circle"

        case .auditing:
            return "magnifyingglass"

        case .completed:
            return "checkmark.shield.fill"

        case .stopped:
            return "stop.circle.fill"

        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var progressTint: Color {
        switch tester.state {
        case .completed:
            return .green

        case .stopped:
            return .orange

        case .failed:
            return .red

        default:
            return .blue
        }
    }

    private var accessibilityStatusIcon: String {
        switch accessibilityFill.state {
        case .idle:
            return "accessibility"

        case .presenting:
            return "speaker.wave.2.fill"

        case .verifying:
            return "wifi"

        case .succeeded:
            return "checkmark.circle.fill"

        case .stopped:
            return "stop.circle.fill"

        case .exhausted:
            return "list.bullet.rectangle"
        }
    }

    private func riskColor(
        _ risk: PasswordTesterManager.RiskLevel
    ) -> Color {
        switch risk {
        case .critical:
            return .red

        case .high:
            return .orange

        case .medium:
            return .yellow

        case .low:
            return .green
        }
    }

    private func maskedPassword(
        _ password: String
    ) -> String {
        String(
            repeating: "•",
            count:
                min(max(password.count, 8), 18)
        )
    }

    private func verifyAccessibleCurrentPassword() {
        guard let password =
            accessibilityFill.currentPassword
        else {
            return
        }

        accessibilityFill.beginSingleVerification()
        verify(password: password)
    }

    private func verify(password: String) {
        let cleanSSID =
            ssid.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        tester.recordSingleVerificationRequest(
            ssid: cleanSSID,
            password: password
        )

        autoConnect.connect(
            ssid: cleanSSID,
            password: password
        )
    }

    private func handleImport(
        _ result: Result<[URL], Error>
    ) {
        do {
            guard let url =
                try result.get().first
            else {
                return
            }

            selectedResultID = nil
            accessibilityFill.reset()
            try tester.importPasswordList(from: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RiskCountView: View {
    let title: String
    let count: Int
    let symbol: String
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .foregroundStyle(color)

            Text("\(count)")
                .font(.headline.monospacedDigit())

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(
            children: .combine
        )
        .accessibilityLabel(
            "\(title)风险，\(count) 个"
        )
    }
}