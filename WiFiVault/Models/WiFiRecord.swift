import Foundation

struct WiFiRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var ssid: String
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        ssid: String,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.ssid = ssid
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
