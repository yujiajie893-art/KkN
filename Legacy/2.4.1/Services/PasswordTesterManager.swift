import CryptoKit
import Combine
import Foundation

private let vaultCommonPasswords: Set<String> = [
    "12345678", "123456789", "1234567890", "00000000",
    "11111111", "88888888", "66666666", "password",
    "password1", "password123", "qwerty", "qwerty123",
    "qwertyuiop", "admin", "admin123", "abcd1234",
    "letmein", "welcome", "welcome1", "iloveyou",
    "sunshine", "princess", "dragon", "master"
]

@MainActor
final class PasswordTesterManager: ObservableObject {
    enum AuditState: Equatable, Sendable {
        case idle
        case imported
        case auditing
        case completed
        case stopped
        case failed
    }

    enum RiskLevel: String, Codable, CaseIterable, Sendable {
        case critical
        case high
        case medium
        case low

        var title: String {
            switch self {
            case .critical: return "极高风险"
            case .high: return "高风险"
            case .medium: return "中等风险"
            case .low: return "较低风险"
            }
        }
    }

    struct PasswordResult: Identifiable, Codable, Hashable, Sendable {
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

    struct AuditLogEntry: Identifiable, Codable, Hashable, Sendable {
        enum Event: String, Codable, Sendable {
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
    @Published private(set) var loadedFileSize = 0
    @Published private(set) var passwords: [String] = []
    @Published private(set) var results: [PasswordResult] = []
    @Published private(set) var sortedResults: [PasswordResult] = []
    @Published private(set) var criticalCount = 0
    @Published private(set) var highCount = 0
    @Published private(set) var mediumCount = 0
    @Published private(set) var lowCount = 0
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentPassword = ""
    @Published private(set) var statusText = "请导入 TXT 密码列表"
    @Published private(set) var logs: [AuditLogEntry] = []
    @Published var notice: Notice?

    private var auditTask: Task<Void, Never>?
    private let maximumPasswordCount = CandidateListParser.maximumCandidateCount
    private let maximumLogCount = 300
    private let analysisBatchSize = 500

    private var logFileURL: URL {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory

        let directory = baseDirectory
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

    var maximumImportDescription: String {
        "最多 20,000 条 · TXT 最大 16 MB"
    }

    var estimatedCandidateMemoryText: String {
        guard !passwords.isEmpty else { return "0 KB" }
        let utf8Bytes = passwords.reduce(into: 0) { partial, password in
            partial += password.utf8.count
        }
        let approximateBytes = utf8Bytes + passwords.count * 40
        return ByteCountFormatter.string(
            fromByteCount: Int64(approximateBytes),
            countStyle: .memory
        )
    }

    func verificationCandidates(
        limit: VerificationLimit,
        order: VerificationOrder
    ) -> [String] {
        let source: [PasswordResult]
        switch order {
        case .riskFirst:
            source = sortedResults.isEmpty
                ? Self.sortResults(results)
                : sortedResults
        case .importOrder:
            source = results
        }

        let count = limit.resolvedCount(availableCount: source.count)
        return source.prefix(count).map(\.password)
    }

    func importPasswordList(from url: URL) throws {
        if isAuditing {
            stopAudit()
        }

        let gainedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if gainedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try coordinatedData(from: url)

        let parsed = try CandidateListParser.parse(data: data)
        let importedPasswords = parsed.candidates

        passwords = importedPasswords
        loadedFileName = url.lastPathComponent
        loadedFileSize = data.count
        results = []
        resetResultCaches()
        progress = 0
        currentPassword = ""
        state = .imported
        statusText = "已导入 \(importedPasswords.count) 个唯一候选 · \(parsed.encodingName)"

        appendLog(
            event: .imported,
            message:
                "导入 \(url.lastPathComponent)，共 \(importedPasswords.count) 个唯一候选，"
                + "编码 \(parsed.encodingName)。"
        )

        if parsed.truncated || parsed.skippedLongLines > 0 {
            var messages: [String] = []
            if parsed.truncated {
                messages.append("已达到 \(maximumPasswordCount) 条上限")
            }
            if parsed.skippedLongLines > 0 {
                messages.append("跳过 \(parsed.skippedLongLines) 条超过 256 字符的内容")
            }

            notice = Notice(
                title: "导入完成",
                message: messages.joined(separator: "；") + "。"
            )
        }
    }

    func loadDemoList() {
        if isAuditing {
            stopAudit()
        }

        passwords = [
            "",
            "1234",
            "12345678",
            "qwerty123",
            "homewifi2024",
            "admin1234",
            "Summer2026",
            "River!Stone9",
            "Orbit-Cedar-47",
            "N7!mQ2#vL8@p",
            "correct-horse-battery-staple"
        ]
        loadedFileName = "内置格式示例"
        loadedFileSize = 0
        results = []
        resetResultCaches()
        progress = 0
        currentPassword = ""
        state = .imported
        statusText = "已载入 \(passwords.count) 条格式示例"

        appendLog(
            event: .imported,
            message: "载入内置格式示例，共 \(passwords.count) 条。"
        )
    }

    func analyzeSingle(password: String, ssid: String) -> PasswordResult {
        Self.analyze(
            password: password,
            originalIndex: 0,
            ssid: ssid
        )
    }

    func startOfflineAudit(ssid: String) {
        guard !passwords.isEmpty else {
            notice = Notice(
                title: "没有密码列表",
                message: "请先导入 TXT，或载入内置格式示例。"
            )
            return
        }

        auditTask?.cancel()

        let normalizedSSID = ssid.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let candidates = passwords
        let total = max(candidates.count, 1)

        results = []
        resetResultCaches()
        progress = 0
        currentPassword = ""
        state = .auditing
        statusText = "正在进行离线强度分析…"

        appendLog(
            event: .auditStarted,
            message: "开始离线分析 \(candidates.count) 个候选；SSID：\(normalizedSSID.isEmpty ? "未填写" : normalizedSSID)。"
        )

        auditTask = Task { [weak self] in
            guard let self else { return }

            var collected: [PasswordResult] = []
            collected.reserveCapacity(candidates.count)
            var critical = 0
            var high = 0
            var medium = 0
            var low = 0

            for start in stride(
                from: 0,
                to: candidates.count,
                by: self.analysisBatchSize
            ) {
                guard !Task.isCancelled else { return }

                let end = min(start + self.analysisBatchSize, candidates.count)
                let batch = Array(candidates[start..<end])
                let batchStart = start

                let analyzed = await Task.detached(priority: .userInitiated) {
                    batch.enumerated().map { offset, password in
                        Self.analyze(
                            password: password,
                            originalIndex: batchStart + offset,
                            ssid: normalizedSSID
                        )
                    }
                }.value

                guard !Task.isCancelled else { return }

                collected.append(contentsOf: analyzed)
                for result in analyzed {
                    switch result.riskLevel {
                    case .critical: critical += 1
                    case .high: high += 1
                    case .medium: medium += 1
                    case .low: low += 1
                    }
                }

                self.results = collected
                self.criticalCount = critical
                self.highCount = high
                self.mediumCount = medium
                self.lowCount = low

                if end == candidates.count || end <= 1_000 || end % 2_000 == 0 {
                    self.sortedResults = Self.sortResults(collected)
                }

                self.currentPassword = batch.last ?? ""
                self.progress = Double(end) / Double(total)
                self.statusText = "正在分析 \(end)/\(candidates.count)"

                await Task.yield()
            }

            guard !Task.isCancelled else { return }

            self.results = collected
            self.sortedResults = Self.sortResults(collected)
            self.progress = 1
            self.currentPassword = ""
            self.state = .completed
            self.statusText = "分析完成：\(self.criticalCount + self.highCount) 个高风险候选"

            self.appendLog(
                event: .auditCompleted,
                message: "分析完成。极高风险 \(self.criticalCount)，高风险 \(self.highCount)，中等风险 \(self.mediumCount)，较低风险 \(self.lowCount)。"
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
            message: "用户停止离线分析，进度 \(Int(progress * 100))%。"
        )
    }

    func recordSingleVerificationRequest(
        ssid: String,
        password: String
    ) {
        appendLog(
            event: .singleVerificationRequested,
            message: "用户请求单次验证；SSID：\(ssid)；候选指纹：\(passwordFingerprint(password))。"
        )
    }

    func clearImportedData() {
        if isAuditing {
            stopAudit()
        }

        loadedFileName = nil
        loadedFileSize = 0
        passwords = []
        results = []
        resetResultCaches()
        progress = 0
        currentPassword = ""
        state = .idle
        statusText = "请导入 TXT 密码列表"
    }

    func clearLogs() {
        logs = []
        saveLogs()
    }

    private func resetResultCaches() {
        sortedResults = []
        criticalCount = 0
        highCount = 0
        mediumCount = 0
        lowCount = 0
    }

    nonisolated private static func sortResults(
        _ values: [PasswordResult]
    ) -> [PasswordResult] {
        values.sorted {
            if $0.score == $1.score {
                return $0.originalIndex < $1.originalIndex
            }
            return $0.score < $1.score
        }
    }

    nonisolated private static func analyze(
        password: String,
        originalIndex: Int,
        ssid: String
    ) -> PasswordResult {
        let lowercased = password.lowercased()
        let normalizedSSID = ssid
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let scalars = password.unicodeScalars
        let hasLowercase = scalars.contains {
            CharacterSet.lowercaseLetters.contains($0)
        }
        let hasUppercase = scalars.contains {
            CharacterSet.uppercaseLetters.contains($0)
        }
        let hasDigits = scalars.contains {
            CharacterSet.decimalDigits.contains($0)
        }
        let hasSymbols = scalars.contains {
            !CharacterSet.alphanumerics.contains($0)
        }
        let isDigitsOnly = !password.isEmpty && scalars.allSatisfy {
            CharacterSet.decimalDigits.contains($0)
        }

        var characterPool = 0
        if hasLowercase { characterPool += 26 }
        if hasUppercase { characterPool += 26 }
        if hasDigits { characterPool += 10 }
        if hasSymbols { characterPool += 33 }

        let entropy = characterPool > 0
            ? Double(password.count) * log2(Double(characterPool))
            : 0

        var score = 0
        var reasons: [String] = []

        switch password.count {
        case 0...7:
            reasons.append("长度不足 8 位")
        case 8...9:
            score += 18
            reasons.append("长度仅达到常见最低要求")
        case 10...11:
            score += 30
        case 12...15:
            score += 45
        default:
            score += 58
        }

        let classCount = [hasLowercase, hasUppercase, hasDigits, hasSymbols]
            .filter { $0 }
            .count
        score += classCount * 8

        if classCount <= 1 {
            reasons.append("字符类型单一")
            score -= 10
        }

        if vaultCommonPasswords.contains(lowercased) {
            score -= 58
            reasons.append("属于常见弱密码")
        }

        if isDigitsOnly {
            score -= password.count <= 10 ? 25 : 12
            reasons.append("纯数字组合更容易被枚举")
        }

        if !normalizedSSID.isEmpty {
            if lowercased == normalizedSSID {
                score -= 55
                reasons.append("密码与 SSID 完全相同")
            } else if normalizedSSID.count >= 4,
                      lowercased.contains(normalizedSSID) {
                score -= 26
                reasons.append("密码包含完整 SSID")
            }
        }

        if isRepeated(password) {
            score -= 34
            reasons.append("主要由重复字符或重复片段组成")
        }

        if containsSequence(lowercased) {
            score -= 24
            reasons.append("包含连续数字或键盘顺序")
        }

        if containsLikelyDate(lowercased) {
            score -= 16
            reasons.append("包含容易猜测的日期或年份")
        }

        if looksLikePhoneNumber(lowercased) {
            score -= 22
            reasons.append("外观类似手机号")
        }

        if hasPersonalPattern(lowercased) {
            score -= 16
            reasons.append("包含常见家庭、设备或姓名模式")
        }

        if entropy >= 75 {
            score += 12
        } else if entropy < 40 {
            reasons.append("估算搜索空间较小")
        }

        score = min(max(score, 0), 100)

        let riskLevel: RiskLevel
        switch score {
        case 0..<35: riskLevel = .critical
        case 35..<55: riskLevel = .high
        case 55..<75: riskLevel = .medium
        default: riskLevel = .low
        }

        if reasons.isEmpty {
            reasons.append("未发现明显的常见弱模式")
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

    nonisolated private static func isRepeated(_ password: String) -> Bool {
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

            if matches { return true }
        }

        return false
    }

    nonisolated private static func containsSequence(_ password: String) -> Bool {
        let sequences = [
            "012345", "123456", "234567", "345678", "456789",
            "987654", "876543", "765432", "654321", "543210",
            "qwerty", "asdfgh", "zxcvbn", "abcdef", "1qaz2wsx"
        ]
        return sequences.contains { password.contains($0) }
    }

    nonisolated private static func containsLikelyDate(_ password: String) -> Bool {
        password.range(
            of: "(19|20)[0-9]{2}([01][0-9])?([0-3][0-9])?",
            options: .regularExpression
        ) != nil
    }

    nonisolated private static func looksLikePhoneNumber(_ password: String) -> Bool {
        password.range(
            of: "^1[3-9][0-9]{9}$",
            options: .regularExpression
        ) != nil
    }

    nonisolated private static func hasPersonalPattern(_ password: String) -> Bool {
        let patterns = [
            "home", "family", "wifi", "admin", "router", "guest",
            "love", "baby", "mama", "papa", "birthday", "wang",
            "zhang", "chen", "yang", "welcome", "default"
        ]
        return patterns.contains { password.contains($0) }
    }

    private func coordinatedData(from url: URL) throws -> Data {
        var coordinationError: NSError?
        var readResult: Result<Data, Error>?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            readResult = Result {
                try Data(contentsOf: coordinatedURL, options: [.mappedIfSafe])
            }
        }

        if let coordinationError {
            throw coordinationError
        }

        guard let readResult else {
            throw ImportError.unreadableFile
        }

        return try readResult.get()
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
            let decoded = try? JSONDecoder().decode(
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
