import SwiftUI

struct AutoConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WiFiStore
    @EnvironmentObject private var autoConnect: AutoConnectManager

    @State private var selectedRecordID: UUID?
    @State private var lastHandledConnectedSSID: String?

    private var selectedRecord: WiFiRecord? {
        guard let selectedRecordID else { return nil }
        return store.records.first { $0.id == selectedRecordID }
    }

    var body: some View {
        NavigationStack {
            List {
                networkSelectionSection
                connectionStatusSection
                recoverySection
                capabilitySection
            }
            .navigationTitle("自动连接")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        if autoConnect.isRunning {
                            autoConnect.stop()
                        }

                        dismiss()
                    }
                }
            }
            .onAppear {
                if selectedRecordID == nil {
                    selectedRecordID = store.records.first?.id
                }
            }
            .onChange(of: autoConnect.connectedSSID) { connectedSSID in
                guard
                    let connectedSSID,
                    connectedSSID != lastHandledConnectedSSID,
                    let selectedRecord
                else {
                    return
                }

                lastHandledConnectedSSID = connectedSSID
                store.markUsed(selectedRecord)
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

    private var networkSelectionSection: some View {
        Section {
            ForEach(store.records) { record in
                Button {
                    guard !autoConnect.isRunning else { return }

                    selectedRecordID = record.id
                    autoConnect.reset()
                } label: {
                    NetworkRecordRow(
                        record: record,
                        isSelected: selectedRecordID == record.id
                    )
                }
                .buttonStyle(.plain)
                .disabled(autoConnect.isRunning)
            }
        } header: {
            Text("选择自家网络")
        } footer: {
            Text(
                "每次只使用你明确选择的这一组网络名称和密码；"
                + "不会扫描附近网络，也不会批量猜测密码。"
            )
        }
    }

    private var connectionStatusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(
                        autoConnect.statusText,
                        systemImage: statusIcon
                    )
                    .font(.subheadline.weight(.medium))

                    Spacer()

                    Text("\(Int(autoConnect.progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: autoConnect.progress)
                    .tint(progressTint)
            }
            .padding(.vertical, 6)
        } header: {
            Text("连接状态")
        } footer: {
            Text(
                "点击停止会停止应用自己的等待和验证流程；"
                + "已经交给 iOS 的系统确认弹窗无法由应用强制撤回。"
            )
        }
    }

    private var recoverySection: some View {
        Section("忘记密码时") {
            RecoveryTipRow(
                icon: "key.fill",
                title: "查看 iPhone 已保存密码",
                detail: "打开“密码”App → Wi-Fi，使用 Face ID 或设备密码查看。"
            )

            RecoveryTipRow(
                icon: "person.2.fill",
                title: "让旧设备共享密码",
                detail: "让已连接该网络的 iPhone 靠近新设备，并在系统弹窗中点“共享密码”。"
            )

            RecoveryTipRow(
                icon: "qrcode.viewfinder",
                title: "检查路由器标签或二维码",
                detail: "不少家用路由器会把默认 Wi-Fi 名称、密码或二维码印在机身底部。"
            )

            RecoveryTipRow(
                icon: "arrow.counterclockwise.circle.fill",
                title: "最后手段：重置路由器",
                detail: "确认宽带账号和配置方式后，再按说明书恢复出厂设置并重新设置密码。"
            )
        }
    }

    private var capabilitySection: some View {
        Section {
            Label {
                Text(
                    "请在 Xcode 的 Signing & Capabilities 中添加 "
                    + "Hotspot Configuration，并使用真机测试。"
                )
                .font(.footnote)
            } icon: {
                Image(systemName: "iphone.gen3")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            if autoConnect.isRunning {
                Button(role: .destructive) {
                    autoConnect.stop()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Button {
                guard let selectedRecord else { return }

                autoConnect.connect(
                    ssid: selectedRecord.ssid,
                    password: store.password(for: selectedRecord.id)
                )
            } label: {
                Label(
                    autoConnect.isRunning ? "连接中…" : "自动连接",
                    systemImage:
                        autoConnect.isRunning
                        ? "wifi.exclamationmark"
                        : "wifi"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedRecord == nil || autoConnect.isRunning)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var statusIcon: String {
        switch autoConnect.state {
        case .idle:
            return "wifi"

        case .preparing:
            return "gearshape.2"

        case .waitingForSystem:
            return "hand.tap"

        case .verifying:
            return "checkmark.circle"

        case .connected:
            return "wifi.circle.fill"

        case .failed:
            return "exclamationmark.triangle.fill"

        case .cancelled:
            return "stop.circle.fill"
        }
    }

    private var progressTint: Color {
        switch autoConnect.state {
        case .connected:
            return .green

        case .failed:
            return .red

        case .cancelled:
            return .orange

        default:
            return .blue
        }
    }
}

private struct NetworkRecordRow: View {
    let record: WiFiRecord
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 11,
                    style: .continuous
                )
                .fill(.blue.opacity(0.12))
                .frame(width: 42, height: 42)

                Image(systemName: "wifi")
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(record.ssid)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(record.note.isEmpty ? "已保存凭据" : record.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(
                systemName: isSelected
                ? "checkmark.circle.fill"
                : "circle"
            )
            .foregroundStyle(isSelected ? Color.blue : Color.secondary)
        }
        .contentShape(Rectangle())
    }
}

private struct RecoveryTipRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 3)
    }
}
