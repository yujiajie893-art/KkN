import Foundation

@MainActor
final class WiFiStore: ObservableObject {
    @Published private(set) var records: [WiFiRecord] = []

    private let userDefaults: UserDefaults
    private let keychain: KeychainService
    private let recordsKey = "wifi-vault.records.v1"

    init(
        userDefaults: UserDefaults = .standard,
        keychain: KeychainService = .shared
    ) {
        self.userDefaults = userDefaults
        self.keychain = keychain
        loadRecords()
    }

    func password(for recordID: UUID) -> String {
        do {
            return try keychain.readPassword(for: recordID) ?? ""
        } catch {
            return ""
        }
    }

    func addRecord(ssid: String, password: String, note: String) throws {
        let now = Date()
        let record = WiFiRecord(
            ssid: ssid.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: now,
            updatedAt: now
        )

        try keychain.savePassword(password, for: record.id)
        records.append(record)
        sortRecords()
        saveRecords()
    }

    func updateRecord(
        _ record: WiFiRecord,
        ssid: String,
        password: String,
        note: String
    ) throws {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else {
            return
        }

        try keychain.savePassword(password, for: record.id)

        records[index].ssid = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        records[index].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        records[index].updatedAt = Date()

        sortRecords()
        saveRecords()
    }

    func deleteRecord(_ record: WiFiRecord) throws {
        try keychain.deletePassword(for: record.id)
        records.removeAll { $0.id == record.id }
        saveRecords()
    }

    func markUsed(_ record: WiFiRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else {
            return
        }

        records[index].updatedAt = Date()
        sortRecords()
        saveRecords()
    }

    private func loadRecords() {
        guard let data = userDefaults.data(forKey: recordsKey) else {
            records = []
            return
        }

        do {
            records = try JSONDecoder().decode([WiFiRecord].self, from: data)
            sortRecords()
        } catch {
            records = []
        }
    }

    private func saveRecords() {
        do {
            let data = try JSONEncoder().encode(records)
            userDefaults.set(data, forKey: recordsKey)
        } catch {
            assertionFailure("保存 Wi-Fi 元数据失败：\(error.localizedDescription)")
        }
    }

    private func sortRecords() {
        records.sort {
            if $0.updatedAt == $1.updatedAt {
                return $0.ssid.localizedCaseInsensitiveCompare($1.ssid) == .orderedAscending
            }
            return $0.updatedAt > $1.updatedAt
        }
    }
}
