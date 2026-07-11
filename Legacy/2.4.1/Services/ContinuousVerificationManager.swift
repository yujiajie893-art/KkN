import AVFoundation
import Combine
import Foundation
import UIKit

@MainActor
final class ContinuousVerificationManager: ObservableObject {
    enum Speed: String, CaseIterable, Identifiable {
        case slow
        case medium
        case fast

        var id: String { rawValue }

        var title: String {
            switch self {
            case .slow: return "慢"
            case .medium: return "中"
            case .fast: return "快"
            }
        }

        var interval: TimeInterval {
            switch self {
            case .slow: return 12
            case .medium: return 8
            case .fast: return 5
            }
        }

        var description: String {
            switch self {
            case .slow: return "每 12 秒提示一次"
            case .medium: return "每 8 秒提示一次"
            case .fast: return "每 5 秒提示一次"
            }
        }
    }

    enum State: Equatable {
        case disabled
        case awaitingConfirmation
        case running
        case paused
        case awaitingUserVerification
        case succeeded
        case stopped
        case exhausted
    }

    struct Confirmation: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @Published var isEnabled = false
    @Published var speed: Speed = .medium
    @Published var speechEnabled = true
    @Published var announceCountdown = true
    @Published var switchControlAssistEnabled = false
    @Published var verificationLimit: VerificationLimit = .fifty {
        didSet {
            UserDefaults.standard.set(
                verificationLimit.rawValue,
                forKey: "vault.verification.limit"
            )
        }
    }
    @Published var verificationPace: VerificationPace = .balanced {
        didSet {
            UserDefaults.standard.set(
                verificationPace.rawValue,
                forKey: "vault.verification.pace"
            )
        }
    }
    @Published var verificationOrder: VerificationOrder = .riskFirst {
        didSet {
            UserDefaults.standard.set(
                verificationOrder.rawValue,
                forKey: "vault.verification.order"
            )
        }
    }

    @Published private(set) var state: State = .disabled
    @Published private(set) var currentIndex = 0
    @Published private(set) var totalCount = 0
    @Published private(set) var secondsRemaining = 0
    @Published private(set) var statusText = "连续辅助模式未启用"
    @Published private(set) var lastAnnouncement = ""

    // MARK: - 2.4.1 Switch Control continuous trigger

    /// Opt-in only. It is intentionally reset to false on every fresh manager instance.
    @Published private(set) var continuousTriggerEnabled = false
    @Published private(set) var isSwitchControlRunning = UIAccessibility.isSwitchControlRunning
    @Published private(set) var continuousTriggerPhase: VerificationLoopStateMachine.Phase = .disabled
    @Published private(set) var continuousTriggerStatusText = "连续触发默认关闭"
    @Published private(set) var continuousTriggerRequestSequence = 0
    @Published private(set) var continuousAttemptInFlight = false
    @Published private(set) var continuousAttemptsStarted = 0
    @Published private(set) var continuousAttemptsCompleted = 0
    @Published private(set) var continuousSessionStartIndex = 0

    @Published var confirmation: Confirmation?

    private let synthesizer = AVSpeechSynthesizer()
    private var cycleTask: Task<Void, Never>?
    private var nextTriggerTask: Task<Void, Never>?
    private var loop = VerificationLoopStateMachine()
    private var switchControlObserver: NSObjectProtocol?
    private var applicationActiveObserver: NSObjectProtocol?

    init() {
        verificationLimit = VerificationLimit(
            rawValue: UserDefaults.standard.string(
                forKey: "vault.verification.limit"
            ) ?? ""
        ) ?? .fifty
        verificationPace = VerificationPace(
            rawValue: UserDefaults.standard.string(
                forKey: "vault.verification.pace"
            ) ?? ""
        ) ?? .balanced
        verificationOrder = VerificationOrder(
            rawValue: UserDefaults.standard.string(
                forKey: "vault.verification.order"
            ) ?? ""
        ) ?? .riskFirst

        loop.setAvailability(isSwitchControlRunning)
        loop.setEnabled(false)
        continuousTriggerStatusText = isSwitchControlRunning
            ? "已检测到切换控制；连续触发默认关闭"
            : "切换控制未开启；连续触发已锁定"
        syncContinuousTriggerState()

        switchControlObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.switchControlStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshSwitchControlStatus()
            }
        }

        applicationActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshSwitchControlStatus()
            }
        }
    }

    var isActive: Bool {
        switch state {
        case .running, .paused, .awaitingUserVerification:
            return true
        default:
            return false
        }
    }

    var isPaused: Bool { state == .paused }

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(min(currentIndex + 1, totalCount)) / Double(totalCount)
    }

    var isContinuousTriggerHeld: Bool { loop.isHeld }

    var isContinuousTriggerAvailable: Bool {
        isSwitchControlRunning && switchControlAssistEnabled && isEnabled
    }

    var canStartContinuousTrigger: Bool {
        continuousTriggerEnabled
            && isContinuousTriggerAvailable
            && !continuousAttemptInFlight
            && totalCount > 0
    }

    var isContinuousTriggerPaused: Bool {
        loop.phase == .paused
    }

    var continuousPlannedAttemptCount: Int {
        guard totalCount > 0 else { return 0 }
        return max(totalCount - min(continuousSessionStartIndex, totalCount), 0)
    }

    var continuousProgress: Double {
        let planned = continuousPlannedAttemptCount
        guard planned > 0 else { return 0 }
        return Double(min(continuousAttemptsCompleted, planned)) / Double(planned)
    }

    var continuousRemainingCount: Int {
        max(continuousPlannedAttemptCount - continuousAttemptsCompleted, 0)
    }

    var plannedLimitDescription: String {
        verificationLimit == .all
            ? "全部（最多 20,000 条）"
            : "前 \(verificationLimit.maximumCount) 条"
    }

    // MARK: - Timed single-step assistance (2.2)

    func requestStart(candidateCount: Int, currentIndex: Int) {
        guard isEnabled else {
            statusText = "请先开启连续辅助模式"
            announce("请先开启连续辅助模式。")
            return
        }

        guard candidateCount > 0 else {
            statusText = "没有可用的候选密码"
            announce("没有可用的候选密码。")
            return
        }

        stopCycle()
        stopSpeech()

        totalCount = verificationLimit.resolvedCount(
            availableCount: candidateCount
        )
        self.currentIndex = min(max(currentIndex, 0), totalCount - 1)
        state = .awaitingConfirmation
        statusText = "等待用户确认"

        let focusAssistMessage = switchControlAssistEnabled
            ? "倒计时结束后，焦点会自动移动到验证按钮。"
            : ""

        confirmation = Confirmation(
            title: "启动节奏辅助模式？",
            message:
                "此模式会按设定节奏自动朗读并移动到下一个候选，"
                + "但不会自动提交 Wi-Fi 密码。"
                + focusAssistMessage
                + "本次计划范围：\(plannedLimitDescription)。"
                + "每一次连接验证仍需通过 Voice Control、"
                + "Switch Control、外接开关或验证按钮明确触发。"
        )
    }

    func confirmStart() {
        guard state == .awaitingConfirmation else { return }

        state = .running
        statusText = "节奏辅助运行中，第 \(currentIndex + 1) 个候选"

        announce(
            "节奏辅助模式已启动。"
            + "当前是第 \(currentIndex + 1) 个候选，"
            + "共 \(totalCount) 个。"
            + "准备验证时，请说验证当前候选，"
            + "或使用切换控制激活验证按钮。"
        )

        startCycle()
    }

    func cancelStart() {
        guard state == .awaitingConfirmation else { return }
        state = .stopped
        statusText = "已取消启动"
        confirmation = nil
    }

    func pause() {
        guard state == .running else { return }
        stopCycle()
        state = .paused
        statusText = "已暂停在第 \(currentIndex + 1) 个候选"
        announce("节奏辅助模式已暂停。")
    }

    func resume() {
        guard state == .paused else { return }
        state = .running
        statusText = "已继续，第 \(currentIndex + 1) 个候选"
        announce("节奏辅助模式已继续。当前是第 \(currentIndex + 1) 个候选。")
        startCycle()
    }

    func togglePauseResume() {
        if state == .paused {
            resume()
        } else if state == .running {
            pause()
        }
    }

    func stop() {
        stopCycle()
        stopContinuousTrigger(announceStop: false)
        continuousAttemptInFlight = false
        loop.resetProgress()
        syncContinuousTriggerState()
        stopSpeech()

        state = .stopped
        secondsRemaining = 0
        statusText = "连续辅助模式已停止"
        announce("连续辅助模式已停止。")
    }

    func disable() {
        stopCycle()
        stopContinuousTrigger(announceStop: false)
        continuousAttemptInFlight = false
        loop.resetProgress()
        syncContinuousTriggerState()
        stopSpeech()

        isEnabled = false
        setContinuousTriggerEnabled(false)
        state = .disabled
        currentIndex = 0
        totalCount = 0
        continuousAttemptsStarted = 0
        continuousAttemptsCompleted = 0
        continuousSessionStartIndex = 0
        secondsRemaining = 0
        statusText = "连续辅助模式未启用"
        confirmation = nil
    }

    func markAwaitingVerification() {
        guard state == .running else { return }

        stopCycle()
        state = .awaitingUserVerification
        statusText = "等待用户验证第 \(currentIndex + 1) 个候选"

        announce(
            "第 \(currentIndex + 1) 个候选已准备好。"
            + "请通过验证按钮、语音控制或切换控制明确触发一次验证。"
        )
    }

    func handleVerificationFailed() {
        guard state == .awaitingUserVerification else { return }

        if currentIndex + 1 >= totalCount {
            state = .exhausted
            statusText = "候选列表已经结束"
            announce("连接未成功，候选列表已经结束。")
            return
        }

        currentIndex += 1
        state = .running
        statusText = "连接未成功，已移动到第 \(currentIndex + 1) 个候选"
        announce("连接未成功。已移动到第 \(currentIndex + 1) 个候选。")
        startCycle()
    }

    func handleVerificationCancelled() {
        guard state == .awaitingUserVerification else { return }
        state = .paused
        statusText = "本次验证已取消，辅助模式保持暂停"
        announce("本次验证已取消。连续辅助模式保持暂停。")
    }

    func handleVerificationSucceeded(ssid: String) {
        stopCycle()
        stopSpeech()
        state = .succeeded
        secondsRemaining = 0
        statusText = "已连接到“\(ssid)”"
        announce("连接成功。已连接到 \(ssid)。")
    }

    func updateCurrentIndex(_ index: Int) {
        if totalCount > 0 {
            currentIndex = min(max(index, 0), totalCount - 1)
        } else {
            currentIndex = max(index, 0)
        }

        if state == .running {
            statusText = "节奏辅助运行中，第 \(currentIndex + 1) 个候选"
        }
    }

    func previewSpeech() {
        announce("连续辅助模式语音预览。当前速度为\(speed.title)。")
    }

    // MARK: - Continuous trigger loop (2.4.1)

    @discardableResult
    func setContinuousTriggerEnabled(_ enabled: Bool) -> Bool {
        refreshSwitchControlStatus(announceChange: false)

        guard !enabled || (
            isSwitchControlRunning
            && isEnabled
            && switchControlAssistEnabled
        ) else {
            continuousTriggerEnabled = false
            loop.setEnabled(false)
            syncContinuousTriggerState(
                overrideStatus: "请先开启切换控制与单步辅助验证"
            )
            announce("请先开启切换控制与单步辅助验证。")
            return false
        }

        continuousTriggerEnabled = enabled
        loop.setEnabled(enabled)

        if enabled {
            continuousTriggerStatusText = "连续触发已开启，等待按住验证控件"
            announce(
                "连续触发模式已开启。短按仍只验证当前候选，"
                + "长按会开始循环，松开即暂停。"
            )
        } else {
            stopContinuousTrigger(announceStop: false)
            continuousTriggerStatusText = "连续触发默认关闭"
        }

        syncContinuousTriggerState()
        return true
    }

    @discardableResult
    func beginContinuousTrigger(
        candidateCount: Int,
        currentIndex: Int
    ) -> Bool {
        refreshSwitchControlStatus(announceChange: false)

        guard isEnabled, switchControlAssistEnabled else {
            continuousTriggerStatusText = "请先开启单步辅助验证"
            announce("请先开启单步辅助验证。")
            return false
        }

        guard continuousTriggerEnabled else {
            continuousTriggerStatusText = "请先开启连续触发模式"
            announce("请先开启连续触发模式。")
            return false
        }

        guard isSwitchControlRunning else {
            continuousTriggerStatusText = "切换控制未运行"
            announce("连续触发仅对切换控制用户开放。")
            return false
        }

        guard !continuousAttemptInFlight else { return false }

        let resolvedCount = verificationLimit.resolvedCount(
            availableCount: candidateCount
        )
        let resolvedIndex = min(
            max(currentIndex, 0),
            max(resolvedCount - 1, 0)
        )
        let isResumingExistingSession =
            loop.phase == .paused
            && loop.totalCount == resolvedCount
            && loop.currentIndex == resolvedIndex

        guard loop.prepare(
            totalCount: resolvedCount,
            currentIndex: resolvedIndex
        ) else {
            continuousTriggerStatusText = "没有可验证的候选"
            announce("没有可验证的候选。")
            return false
        }

        if !isResumingExistingSession {
            continuousAttemptsStarted = 0
            continuousAttemptsCompleted = 0
            continuousSessionStartIndex = resolvedIndex
        }

        stopCycle()
        if state == .running || state == .awaitingUserVerification {
            state = .paused
            statusText = "节奏辅助已暂停；连续触发正在运行"
        }
        nextTriggerTask?.cancel()
        nextTriggerTask = nil

        totalCount = resolvedCount
        self.currentIndex = resolvedIndex

        guard loop.beginHold() else { return false }

        continuousTriggerStatusText = isResumingExistingSession
            ? "已继续：准备验证第 \(self.currentIndex + 1) 个候选"
            : "连续验证已开始：第 \(self.currentIndex + 1)/\(totalCount) 条"
        syncContinuousTriggerState()
        announce(
            isResumingExistingSession
                ? "连续验证已继续。"
                : "连续验证已开始。可以随时使用暂停按钮中断。"
        )
        issueContinuousTriggerRequest()
        return true
    }

    func endContinuousTrigger() {
        pauseContinuousTrigger()
    }

    func pauseContinuousTrigger() {
        guard loop.isHeld || continuousAttemptInFlight else { return }

        nextTriggerTask?.cancel()
        nextTriggerTask = nil
        loop.release()
        continuousTriggerStatusText = continuousAttemptInFlight
            ? "暂停已请求；当前验证结束后停止推进"
            : "已暂停在第 \(currentIndex + 1)/\(totalCount) 个候选"
        syncContinuousTriggerState()
        announce("连续验证已暂停。")
    }

    @discardableResult
    func resumeContinuousTrigger(
        candidateCount: Int,
        currentIndex: Int
    ) -> Bool {
        guard loop.phase == .paused else { return false }
        return beginContinuousTrigger(
            candidateCount: candidateCount,
            currentIndex: currentIndex
        )
    }

    @discardableResult
    func markContinuousAttemptStarted(expectedIndex: Int) -> Bool {
        guard expectedIndex == loop.currentIndex else { return false }
        guard loop.markAttemptStarted() else { return false }

        continuousAttemptInFlight = true
        continuousAttemptsStarted += 1
        continuousTriggerStatusText =
            "正在验证第 \(expectedIndex + 1)/\(totalCount) 个候选"
        syncContinuousTriggerState()
        return true
    }

    /// Returns the candidate index that the view should select before the next request.
    func handleContinuousVerificationFailed() -> Int? {
        guard continuousAttemptInFlight else { return nil }
        continuousAttemptInFlight = false
        continuousAttemptsCompleted += 1

        switch loop.recordFailure() {
        case .advance(let nextIndex):
            currentIndex = nextIndex
            continuousTriggerStatusText =
                "未连接，准备第 \(nextIndex + 1)/\(totalCount) 个候选"
            syncContinuousTriggerState()
            scheduleNextContinuousTrigger()
            return nextIndex

        case .paused:
            continuousTriggerStatusText = "验证失败；循环已暂停"
            syncContinuousTriggerState()
            return nil

        case .exhausted:
            continuousTriggerStatusText = "候选列表已全部验证"
            syncContinuousTriggerState()
            announce("候选列表已经结束。")
            return nil

        case .ignored:
            syncContinuousTriggerState()
            return nil
        }
    }

    func handleContinuousVerificationCancelled() {
        guard continuousAttemptInFlight else { return }
        continuousAttemptInFlight = false
        nextTriggerTask?.cancel()
        nextTriggerTask = nil
        loop.recordCancellation()
        continuousTriggerStatusText = "本次验证已取消；循环暂停"
        syncContinuousTriggerState()
        announce("本次验证已取消。连续触发已暂停。")
    }

    func handleContinuousVerificationSucceeded(ssid: String) {
        guard continuousAttemptInFlight || loop.isHeld else { return }
        if continuousAttemptInFlight {
            continuousAttemptsCompleted += 1
        }
        continuousAttemptInFlight = false
        nextTriggerTask?.cancel()
        nextTriggerTask = nil
        loop.recordSuccess()
        continuousTriggerStatusText = "已连接到“\(ssid)”"
        syncContinuousTriggerState()
        announce("连接成功。连续触发已停止。")
    }

    func suspendContinuousTrigger(reason: String) {
        guard loop.isHeld || continuousAttemptInFlight else { return }
        nextTriggerTask?.cancel()
        nextTriggerTask = nil
        loop.release()
        continuousTriggerStatusText = "已暂停：\(reason)"
        syncContinuousTriggerState()
    }

    /// WiFiVault intentionally does not run validation or speech in the background.
    /// Any late NetworkExtension completion is ignored by AutoConnectManager's token.
    func suspendForBackground() {
        stopCycle()
        nextTriggerTask?.cancel()
        nextTriggerTask = nil
        stopSpeech()

        if continuousAttemptInFlight {
            continuousAttemptInFlight = false
            loop.recordCancellation()
        } else if loop.isHeld {
            loop.release()
        }

        if state == .running || state == .awaitingUserVerification {
            state = .paused
            secondsRemaining = 0
            statusText = "应用进入后台，辅助流程已暂停"
        }

        if continuousTriggerEnabled {
            continuousTriggerStatusText = "已因应用进入后台暂停；返回后请手动继续"
        }
        syncContinuousTriggerState()
    }

    func refreshSwitchControlStatus(announceChange: Bool = true) {
        let newValue = UIAccessibility.isSwitchControlRunning
        guard newValue != isSwitchControlRunning else { return }

        isSwitchControlRunning = newValue
        loop.setAvailability(newValue)

        if !newValue {
            nextTriggerTask?.cancel()
            nextTriggerTask = nil
            continuousTriggerEnabled = false
            loop.setEnabled(false)
            continuousTriggerStatusText = "切换控制已关闭，连续触发已锁定"
            if announceChange {
                announce("检测到切换控制已关闭。连续触发已经停止。")
            }
        } else {
            continuousTriggerStatusText = "已检测到切换控制；连续触发默认关闭"
            if announceChange {
                announce("已检测到切换控制。连续触发仍保持关闭。")
            }
        }

        syncContinuousTriggerState()
    }

    private func stopContinuousTrigger(announceStop: Bool) {
        nextTriggerTask?.cancel()
        nextTriggerTask = nil

        if continuousAttemptInFlight {
            // The system Wi-Fi request cannot be cancelled reliably. Keep its origin
            // until the result arrives, but invalidate the held session so no next
            // candidate can be requested.
            loop.release()
        } else {
            loop.resetProgress()
        }

        continuousTriggerStatusText = continuousTriggerEnabled
            ? "连续触发已停止"
            : "连续触发默认关闭"
        syncContinuousTriggerState()

        if announceStop {
            announce("连续触发已停止。")
        }
    }

    private func issueContinuousTriggerRequest() {
        guard loop.isHeld, loop.phase == .holding else { return }
        continuousTriggerRequestSequence &+= 1
    }

    private func scheduleNextContinuousTrigger() {
        nextTriggerTask?.cancel()
        let expectedGeneration = loop.generation
        let delay = verificationPace.delayNanoseconds

        nextTriggerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled else { return }
            guard self.loop.generation == expectedGeneration else { return }
            guard self.loop.isHeld, self.loop.phase == .holding else { return }
            self.issueContinuousTriggerRequest()
        }
    }

    private func syncContinuousTriggerState(overrideStatus: String? = nil) {
        continuousTriggerPhase = loop.phase
        if let overrideStatus {
            continuousTriggerStatusText = overrideStatus
        }
    }

    // MARK: - Shared speech and timed cycle

    private func startCycle() {
        stopCycle()
        guard state == .running else { return }

        let interval = max(Int(speed.interval), 1)
        secondsRemaining = interval

        cycleTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled, self.state == .running {
                if self.announceCountdown {
                    self.announce(
                        "第 \(self.currentIndex + 1) 个候选。"
                        + "\(self.secondsRemaining) 秒后提示验证。"
                    )
                }

                while self.secondsRemaining > 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled, self.state == .running else { return }
                    self.secondsRemaining -= 1
                }

                guard self.state == .running else { return }
                self.markAwaitingVerification()
                return
            }
        }
    }

    private func stopCycle() {
        cycleTask?.cancel()
        cycleTask = nil
    }

    private func announce(_ text: String) {
        lastAnnouncement = text
        guard speechEnabled else { return }

        stopSpeech()

        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: text)
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice =
            AVSpeechSynthesisVoice(language: "zh-CN")
            ?? AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first)
        utterance.rate = 0.46
        utterance.pitchMultiplier = 1
        utterance.volume = 1
        synthesizer.speak(utterance)
    }

    private func stopSpeech() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
    }
}
