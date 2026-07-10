import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: WiFiStore
    @EnvironmentObject private var autoConnect: AutoConnectManager
    @EnvironmentObject private var passwordTester: PasswordTesterManager
    @EnvironmentObject private var accessibilityFill: AccessibilityAutoFillManager

    @State private var searchText = ""
    @State private var showPasswords = false
    @State private var showingAddSheet = false
    @State private var showingAutoConnectSheet = false
    @State private var showingPasswordTesterSheet = false
    @State private var editingRecord: WiFiRecord?
    @State private var recordPendingDeletion: WiFiRecord?
    @State private var errorMessage: String?

    private var filteredRecords: [WiFiRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return store.records
        }

        return store.records.filter {
            $0.ssid.localizedCaseInsensitiveContains(query) ||
            $0.note.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                if store.records.isEmpty {
                    emptyState
                } else {
                    recordsList
                }
            }
            .navigationTitle("Wi-Fi 密码库")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索网络名称或备注"
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingPasswordTesterSheet = true
                    } label: {
                        Image(systemName: "shield.lefthalf.filled")
                    }
                    .accessibilityLabel("密码强度审计")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加 Wi-Fi")
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                WiFiFormView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showingAutoConnectSheet) {
                AutoConnectSheet()
                    .environmentObject(store)
                    .environmentObject(autoConnect)
            }
            .sheet(isPresented: $showingPasswordTesterSheet) {
                PasswordTesterSheet()
                    .environmentObject(passwordTester)
                    .environmentObject(autoConnect)
                    .environmentObject(accessibilityFill)
            }
            .sheet(item: $editingRecord) { record in
                WiFiFormView(
                    record: record,
                    initialPassword: store.password(for: record.id)
                )
                .environmentObject(store)
            }
            .confirmationDialog(
                "确定删除这个 Wi-Fi 记录吗？",
                isPresented: Binding(
                    get: { recordPendingDeletion != nil },
                    set: { if !$0 { recordPendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: recordPendingDeletion
            ) { record in
                Button("删除“\(record.ssid)”", role: .destructive) {
                    delete(record)
                }
                Button("取消", role: .cancel) {
                    recordPendingDeletion = nil
                }
            } message: { _ in
                Text("网络名称、备注和钥匙串中的密码都会从本机删除。")
            }
            .alert(
                "操作失败",
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

    private var recordsList: some View {
        List {
            Section {
                Toggle(isOn: $showPasswords.animation(.easeInOut(duration: 0.2))) {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("显示密码")
                                .font(.body.weight(.medium))
                            Text("只在当前设备、当前界面显示")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: showPasswords ? "eye.fill" : "eye.slash.fill")
                            .foregroundStyle(.blue)
                    }
                }
                .tint(.blue)

                Button {
                    showingAutoConnectSheet = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("自动连接")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)

                            Text("选择一条已保存记录并请求系统加入")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "wifi")
                            .foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
            }

            Section {
                if filteredRecords.isEmpty {
                    noSearchResults
                } else {
                    ForEach(filteredRecords) { record in
                        WiFiRowView(
                            record: record,
                            password: store.password(for: record.id),
                            showPassword: showPasswords,
                            onEdit: {
                                editingRecord = record
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                recordPendingDeletion = record
                            } label: {
                                Label("删除", systemImage: "trash")
                            }

                            Button {
                                editingRecord = record
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button {
                                editingRecord = record
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                recordPendingDeletion = record
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("已保存网络（\(filteredRecords.count)）")
            } footer: {
                Text("密码使用 iOS 钥匙串保存在本机；网络名称和备注使用 UserDefaults 持久化。")
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.12))
                    .frame(width: 92, height: 92)

                Image(systemName: "wifi")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.blue)
            }

            VStack(spacing: 7) {
                Text("还没有保存 Wi-Fi")
                    .font(.title3.bold())

                Text("手动添加网络名称和密码，忘记时可在本机查看。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            Button {
                showingAddSheet = true
            } label: {
                Label("添加第一个网络", systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var noSearchResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("没有找到匹配的网络")
                .font(.headline)

            Text("试试搜索其他网络名称或备注。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .listRowBackground(Color.clear)
    }

    private func delete(_ record: WiFiRecord) {
        do {
            try store.deleteRecord(record)
            recordPendingDeletion = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
