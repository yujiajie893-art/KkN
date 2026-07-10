import SwiftUI

struct WiFiFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WiFiStore

    private let record: WiFiRecord?

    @State private var ssid: String
    @State private var password: String
    @State private var note: String
    @State private var revealPassword = false
    @State private var errorMessage: String?

    init(record: WiFiRecord? = nil, initialPassword: String = "") {
        self.record = record
        _ssid = State(initialValue: record?.ssid ?? "")
        _password = State(initialValue: initialPassword)
        _note = State(initialValue: record?.note ?? "")
    }

    private var isEditing: Bool {
        record != nil
    }

    private var canSave: Bool {
        !ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "wifi")
                            .foregroundStyle(.blue)
                            .frame(width: 24)

                        TextField("例如：Home_5G", text: $ssid)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("网络名称")
                } footer: {
                    Text("请输入你自己拥有或获准保存的 Wi-Fi 名称。")
                }

                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.orange)
                            .frame(width: 24)

                        Group {
                            if revealPassword {
                                TextField("输入密码，可留空", text: $password)
                            } else {
                                SecureField("输入密码，可留空", text: $password)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button {
                            revealPassword.toggle()
                        } label: {
                            Image(systemName: revealPassword ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(revealPassword ? "隐藏密码" : "显示密码")
                    }
                } header: {
                    Text("密码")
                } footer: {
                    Text("密码会写入 iOS 钥匙串，并设置为仅在本设备解锁后可访问。")
                }

                Section {
                    TextField(
                        "例如：客厅路由器、办公室二楼",
                        text: $note,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                } header: {
                    Text("备注（可选）")
                }

                Section {
                    Label {
                        Text("本应用不会联网、扫描网络、破解密码，也不会读取系统已经保存的 Wi-Fi 密码。")
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑 Wi-Fi" : "添加 Wi-Fi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .alert(
                "保存失败",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "发生未知错误。")
            }
        }
    }

    private func save() {
        do {
            if let record {
                try store.updateRecord(
                    record,
                    ssid: ssid,
                    password: password,
                    note: note
                )
            } else {
                try store.addRecord(
                    ssid: ssid,
                    password: password,
                    note: note
                )
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
