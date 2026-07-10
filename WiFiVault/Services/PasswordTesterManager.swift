import CryptoKit
import Foundation

@MainActor
final class PasswordTesterManager: ObservableObject {
    enum AuditState: Equatable {
        case idle
        case imported
        case auditing
        case completed
        case stopped
        case failed
    }

    enum RiskLevel: String, Codable, CaseIterable {
        case critical
        case high
        case medium
        case low

        var title: String {
            switch self {
            case .critical:
                return "极高风险"
            case .high:
                return "高风险"
            case .medium:
                return "中等风险"
            case .low:
                return "较低风险"
            }
        }
    }

    struct PasswordResult: Identifiable, Codable, Hashable {
        let id: UUID
        let originalIndex: Int
        let password: String
        let score: Int
        let estimatedEntropyBits: Double
        let riskLevel: RiskLevel
        let reasons: [String]

        init(
            id: UUID = UUID(),
            originalIndex: Int,
            password: String,
            score: Int,
            estimatedEntropyBits: Double,
            riskLevel: RiskLevel,
            reasons: [String]
        ) {
            self.id = id
            self.originalIndex = originalIndex
            self.password = password
            self.score = score
            self.estimatedEntropyBits = estimatedEntropyBits
            self.riskLevel = riskLevel
            self.reasons = reasons
        }
    }

    struct AuditLogEntry: Identifiable, Codable, Hashable {
        enum Event: String, Codable {
            case imported
            case auditStarted
            case auditCompleted
            case auditStopped
            case singleVerificationRequested
            case failure
        }

        let id: UUID
        let date: Date
        let event: Event
        let message: String

        init(
            id: UUID = UUID(),
            date: Date = Date(),
            event: Event,
            message: String
        ) {
            self.id = id
            self.date = date
            self.event = event
            self.message = message
        }
    }

    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @Published private(set) var state: AuditState = .idle
    @Published private(set) var loadedFileName: String?
    @Published private(set) var passwords: [String] = []
    @Published private(set) var results: [PasswordResult] = []
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentPassword = ""
    @Published private(set) var statusText = "请导入 TXT 密码列表"
    @Published private(set) var logs: [AuditLogEntry] = []
    @Published var notice: Notice?

    private var auditTask: Task<Void, Never>?
    private let maximumPasswordCount = 20_000
    private let maximumLogCount = 500

    private let commonPasswords: Set<String> = [
        "12345678",
        "123456789",
        "1234567890",
        "password",
        "password1",
        "password123",
        "qwerty123",
        "qwertyuiop",
        "11111111",
        "00000000",
        "88888888",
        "66666666",
        "abcd1234",
        "admin123",
        "iloveyou",
        "letmein",
        "welcome1"
    ]

    private var logFileURL: URL {
        let fileManager = FileManager.default
        let baseDirectory =
            fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
            ?? fileManager.temporaryDirectory

        let directory =
            baseDirectory
            .appendingPathComponent("WiFiVault", isDirectory: true)

        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        return directory.appendingPathComponent(
            "password-audit-log.json",
            isDirectory: false
        )
    }

    init() {
        loadLogs()
    }

    var isAuditing: Bool {
        state == .auditing
    }

    var sortedResults: [PasswordResult] {
        results.sorted {
            if $0.score == $1.score {
                return $0.originalIndex < $1.originalIndex
            }

            return $0.score < $1.score
        }
    }

    var criticalCount: Int {
        results.filter { $0.riskLevel == .critical }.count
    }

    var highCount: Int {
        results.filter { $0.riskLevel == .high }.count
    }

    var mediumCount: Int {
        results.filter { $0.riskLevel == .medium }.count
    }

    var lowCount: Int {
        results.filter { $0.riskLevel == .low }.count
    }

    func importPasswordList(from url: URL) throws {
        stopAudit()

        let gainedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if gainedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        let text = try decodeTextFile(data)

        var seen = Set<String>()
        var importedPasswords: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let candidate =
                rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !candidate.isEmpty else { continue }
            guard seen.insert(candidate).inserted else { continue }

            importedPasswords.append(candidate)

            if importedPasswords.count >= maximumPasswordCount {
                break
            }
        }

        guard !importedPasswords.isEmpty else {
            throw ImportError.emptyFile
        }

        passwords = importedPasswords
        loadedFileName = url.lastPathComponent
        results = []
        progress = 0
        currentPassword = ""
        state = .imported
        statusText = "已导入 \(importedPasswords.count) 个唯一候选密码"

        appendLog(
            event: .imported,
            message:
                "导入文件 \(url.lastPathComponent)，"
                + "共 \(importedPasswords.count) 个唯一候选项。"
        )

        if importedPasswords.count == maximumPasswordCount {
            notice = Notice(
                title: "已达到导入上限",
                message:
                    "为避免占用过多内存，本次最多读取 "
                    + "\(maximumPasswordCount) 条唯一密码。"
            )
        }
    }

    func startOfflineAudit(ssid: String) {
        guard !passwords.isEmpty else {
            notice = Notice(
                title: "没有密码列表",
                message: "请先导入一个 TXT 文件，每行放置一个密码。"
            )
            return
        }

        auditTask?.cancel()

        let normalizedSSID =
            ssid.trimmingCharacters(in: .whitespacesAndNewlines)

        results = []
        progress = 0
        currentPassword = ""
        state = .auditing
        statusText = "正在进行离线强度分析…"

        appendLog(
            event: .auditStarted,
            message:
                "开始离线审计 \(passwords.count) 个候选项；"
                + "SSID：\(normalizedSSID.isEmpty ? "未填写" : normalizedSSID)。"
        )

        auditTask = Task { [weak self] in
            guard let self else { return }

            let candidates = self.passwords
            let total = max(candidates.count, 1)
            var collectedResults: [PasswordResult] = []
            collectedResults.reserveCapacity(candidates.count)

            for (index, password) in candidates.enumerated() {
                guard !Task.isCancelled else { return }

                let result = self.analyze(
                    password: password,
                    originalIndex: index,
                    ssid: normalizedSSID
                )

                collectedResults.append(result)

                // Updating the UI less frequently keeps large imports responsive.
                if index % 20 == 0 || index == candidates.count - 1 {
                    self.results = collectedResults
                    self.currentPassword = password
                    self.progress = Double(index + 1) / Double(total)
                    self.statusText =
                        "正在分析 \(index + 1)/\(candidates.count)"

                    await Task.yield()
                }
            }

            guard !Task.isCancelled else { return }

            self.results = collectedResults
            self.progress = 1
            self.currentPassword = ""
            self.state = .completed
            self.statusText =
                "分析完成：发现 "
                + "\(self.criticalCount + self.highCount) 个高风险候选项"

            self.appendLog(
                event: .auditCompleted,
                message:
                    "离线审计完成。极高风险 \(self.criticalCount) 个，"
                    + "高风险 \(self.highCount) 个，"
                    + "中等风险 \(self.mediumCount) 个，"
                    + "较低风险 \(self.lowCount) 个。"
            )
        }
    }

    func stopAudit() {
        guard state == .auditing else { return }

        auditTask?.cancel()
        auditTask = nil
        state = .stopped
        currentPassword = ""
        statusText = "已停止离线分析"

        appendLog(
            event: .auditStopped,
            message:
                "用户停止离线审计，进度 "
                + "\(Int(progress * 100))%。"
        )
    }

    func recordSingleVerificationRequest(
        ssid: String,
        password: String
    ) {
        let fingerprint = passwordFingerprint(password)

        appendLog(
            event: .singleVerificationRequested,
            message:
                "用户手动请求单次验证；SSID：\(ssid)；"
                + "候选指纹：\(fingerprint)。"
        )
    }

    func clearImportedData() {
        stopAudit()

        loadedFileName = nil
        passwords = []
        results = []
        progress = 0
        currentPassword = ""
        state = .idle
        statusText = "请导入 TXT 密码列表"
    }

    func clearLogs() {
        logs = []
        saveLogs()
    }

    private func analyze(
        password: String,
        originalIndex: Int,
        ssid: String
    ) -> PasswordResult {
        let lowercased = password.lowercased()
        let normalizedSSID = ssid.lowercased()

        let hasLowercase =
            password.range(of: "[a-z]", options: .regularExpression) != nil
        let hasUppercase =
            password.range(of: "[A-Z]", options: .regularExpression) != nil
        let hasDigits =
            password.range(of: "[0-9]", options: .regularExpression) != nil
        let hasSymbols =
            password.range(
                of: "[^A-Za-z0-9]",
                options: .regularExpression
            ) != nil

        var characterPool = 0

        if hasLowercase { characterPool += 26 }
        if hasUppercase { characterPool += 26 }
        if hasDigits { characterPool += 10 }
        if hasSymbols { characterPool += 33 }

        let entropy =
            characterPool > 0
            ? Double(password.count) * log2(Double(characterPool))
            : 0

        var score = 0
        var reasons: [String] = []

        switch password.count {
        case 0...7:
            reasons.append("长度不足 8 位")
        case 8...9:
            score += 18
            reasons.append("长度仅达到最低常见要求")
        case 10...11:
            score += 28
        case 12...15:
            score += 42
        default:
            score += 55
        }

        let classCount =
            [hasLowercase, hasUppercase, hasDigits, hasSymbols]
            .filter { $0 }
            .count

        score += classCount * 9

        if classCount <= 1 {
            reasons.append("字符类型单一")
        }

        if commonPasswords.contains(lowercased) {
            score -= 55
            reasons.append("属于常见弱密码")
        }

        if !normalizedSSID.isEmpty {
            if lowercased == normalizedSSID {
                score -= 55
                reasons.append("密码与 SSID 完全相同")
            } else if
                normalizedSSID.count >= 4,
                lowercased.contains(normalizedSSID)
            {
                score -= 25
                reasons.append("密码包含完整 SSID")
            }
        }

        if isRepeated(password) {
            score -= 35
            reasons.append("主要由重复字符组成")
        }

        if containsSequence(lowercased) {
            score -= 24
            reasons.append("包含连续数字或键盘顺序")
        }

        if containsLikelyYear(lowercased) {
            score -= 12
            reasons.append("包含容易猜测的年份")
        }

        if hasPersonalPattern(lowercased) {
            score -= 18
            reasons.append("包含常见姓名、生日或家庭用词模式")
        }

        if entropy >= 70 {
            score += 12
        } else if entropy < 40 {
            reasons.append("估算搜索空间较小")
        }

        score = min(max(score, 0), 100)

        let riskLevel: RiskLevel

        switch score {
        case 0..<35:
            riskLevel = .critical
        case 35..<55:
            riskLevel = .high
        case 55..<75:
            riskLevel = .medium
        default:
            riskLevel = .low
        }

        if reasons.isEmpty {
            reasons.append("未发现明显的常见弱密码模式")
        }

        return PasswordResult(
            originalIndex: originalIndex,
            password: password,
            score: score,
            estimatedEntropyBits: entropy,
            riskLevel: riskLevel,
            reasons: reasons
        )
    }

    private func isRepeated(_ password: String) -> Bool {
        guard password.count >= 4 else { return false }

        if Set(password).count == 1 {
            return true
        }

        let characters = Array(password)

        for unitLength in 1...min(4, characters.count / 2) {
            guard characters.count.isMultiple(of: unitLength) else {
                continue
            }

            let unit = Array(characters.prefix(unitLength))
            var matches = true

            for index in characters.indices {
                if characters[index] != unit[index % unitLength] {
                    matches = false
                    break
                }
            }

            if matches {
                return true
            }
        }

        return false
    }

    private func containsSequence(_ password: String) -> Bool {
        let sequences = [
            "012345",
            "123456",
            "234567",
            "345678",
            "456789",
            "987654",
            "876543",
            "765432",
            "654321",
            "qwerty",
            "asdfgh",
            "zxcvbn",
            "abcdef"
        ]

        return sequences.contains { password.contains($0) }
    }

    private func containsLikelyYear(_ password: String) -> Bool {
        password.range(
            of: "(19|20)[0-9]{2}",
            options: .regularExpression
        ) != nil
    }

    private func hasPersonalPattern(_ password: String) -> Bool {
        let patterns = [
            "home",
            "family",
            "wifi",
            "admin",
            "router",
            "love",
            "mama",
            "papa",
            "birthday"
        ]

        return patterns.contains { password.contains($0) }
    }

    private func decodeTextFile(_ data: Data) throws -> String {
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .isoLatin1
        ]

        for encoding in encodings {
            if let string = String(data: data, encoding: encoding) {
                return string
            }
        }

        throw ImportError.unsupportedEncoding
    }

    private func passwordFingerprint(_ password: String) -> String {
        let digest = SHA256.hash(data: Data(password.utf8))

        return digest
            .prefix(6)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func appendLog(
        event: AuditLogEntry.Event,
        message: String
    ) {
        logs.insert(
            AuditLogEntry(event: event, message: message),
            at: 0
        )

        if logs.count > maximumLogCount {
            logs = Array(logs.prefix(maximumLogCount))
        }

        saveLogs()
    }

    private func loadLogs() {
        guard
            let data = try? Data(contentsOf: logFileURL),
            let decoded =
                try? JSONDecoder().decode(
                    [AuditLogEntry].self,
                    from: data
                )
        else {
            logs = []
            return
        }

        logs = decoded
    }

    private func saveLogs() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let data = try encoder.encode(logs)
            try data.write(
                to: logFileURL,
                options: [.atomic, .completeFileProtection]
            )
        } catch {
            notice = Notice(
                title: "日志保存失败",
                message: error.localizedDescription
            )
        }
    }
}

extension PasswordTesterManager {
    enum ImportError: LocalizedError {
        case emptyFile
        case unsupportedEncoding

        var errorDescription: String? {
            switch self {
            case .emptyFile:
                return "文件中没有可用的非空密码行。"

            case .unsupportedEncoding:
                return "无法识别该文本文件的字符编码。"
            }
        }
    }
}
