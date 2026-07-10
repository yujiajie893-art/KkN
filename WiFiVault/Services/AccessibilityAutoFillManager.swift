import AVFoundation
import Foundation
import UIKit

/// 无障碍辅助填充管理器（专业增强版）
/// 支持自动循环验证、智能延迟、暂停/恢复、实时进度反馈
@MainActor
final class AccessibilityAutoFillManager: ObservableObject {
    // MARK: - 状态枚举
    enum State: Equatable {
        case idle
        case presenting          // 正在展示候选
        case verifying           // 正在验证
        case succeeded           // 连接成功
        case stopped             // 用户主动停止
        case exhausted           // 候选列表用完
        case paused              // 暂停中
    }

    // MARK: - 公开属性
    @Published private(set) var state: State = .idle
    @Published private(set) var candidates: [String] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var statusText = "导入密码列表后，可启动无障碍辅助填充"
    @Published private(set) var lastAnnouncement = ""
    @Published private(set) var attemptCount = 0          // 已尝试次数
    @Published private(set) var estimatedRemainingTime: TimeInterval = 0 // 预估剩余时间（秒）

    // 语音设置
    @Published var speechEnabled = true
    @Published var speakPasswordAloud = false
    @Published var autoAdvanceEnabled = true
    @Published var speechRate: Float = 0.48
    @Published var speechPitch: Float = 1.0
    @Published var speechVolume: Float = 1.0

    // 自动验证增强参数
    @Published var autoVerifyEnabled = false
    @Published var autoVerifyDelay: Double = 2.5   // 基础延迟
    @Published var maxAttempts: Int = 50            // 最大尝试次数（与候选数一致）
    private var currentDelay: Double = 2.5          // 实际延迟（动态调整）

    // 内部任务
    private var verifyTask: Task<Void, Never>?
    private var presentationTask: Task<Void, Never>?
    private let synthesizer = AVSpeechSynthesizer()

    // 常量
    private let maximumCandidateCount = 50
    private let presentationIntervalNanoseconds: UInt64 = 3_000_000_000
    private let maxDelay: Double = 10.0             // 最大延迟（指数退避上限）

    // 暂停控制
    private var isPaused = false
    private var pauseContinuation: CheckedContinuation<Void, Never>?

    // MARK: - 计算属性
    var isRunning: Bool {
        switch state {
        case .presenting, .verifying:
            return true
        default:
            return false
        }
    }

    var isVerifying: Bool {
        state == .verifying
    }

    var currentPassword: String? {
        guard candidates.indices.contains(currentIndex) else { return nil }
        return candidates[currentIndex]
    }

    var currentNumber: Int {
        guard !candidates.isEmpty else { return 0 }
        return currentIndex + 1
    }

    var totalCount: Int {
        candidates.count
    }

    var progress: Double {
        guard !candidates.isEmpty else { return 0 }
        return Double(currentNumber) / Double(candidates.count)
    }

    var canMoveBackward: Bool {
        state == .presenting && currentIndex > 0
    }

    var canMoveForward: Bool {
        state == .presenting && currentIndex + 1 < candidates.count
    }

    // MARK: - 公开方法
    func start(with importedPasswords: [String]) {
        stop() // 清理旧任务
        stopSpeech()

        let limited = Array(importedPasswords.prefix(maximumCandidateCount))
        guard !limited.isEmpty else {
            candidates = []
            currentIndex = 0
            state = .idle
            statusText = "没有可用于辅助填充的候选密码"
            announce("没有可用于辅助填充的候选密码。")
            return
        }

        candidates = limited
        currentIndex = 0
        attemptCount = 0
        currentDelay = autoVerifyDelay
        isPaused = false
        state = .presenting
        statusText = "已选择第 1 个密码，共 \(limited.count) 个"

        announceCurrentCandidate(prefix: "无障碍辅助填充已开始。本次最多载入 \(limited.count) 个候选密码。")
        restartPresentationTaskIfNeeded()

        if autoVerifyEnabled {
            startAutoVerify()
        }
    }

    func stop() {
        stopPresentationTask()
        stopSpeech()
        stopAutoVerify()
        isPaused = false
        pauseContinuation?.resume()
        pauseContinuation = nil
        state = .stopped
        statusText = "无障碍辅助填充已停止"
        announce("无障碍辅助填充已停止。")
    }

    func reset() {
        stop()
        candidates = []
        currentIndex = 0
        attemptCount = 0
        state = .idle
        statusText = "导入密码列表后，可启动无障碍辅助填充"
        lastAnnouncement = ""
        estimatedRemainingTime = 0
    }

    func pause() {
        guard state == .presenting || state == .verifying else { return }
        isPaused = true
        state = .paused
        statusText = "已暂停，点击“继续”恢复"
        announce("已暂停。")
    }

    func resume() {
        guard state == .paused else { return }
        isPaused = false
        pauseContinuation?.resume()
        pauseContinuation = nil
        state = .presenting
        statusText = "已恢复，继续尝试下一个候选"
        announce("已恢复。")
        if autoVerifyEnabled {
            startAutoVerify()
        }
    }

    func updateAutoAdvanceSetting() {
        if autoAdvanceEnabled {
            restartPresentationTaskIfNeeded()
        } else {
            stopPresentationTask()
        }
    }

    func moveToNextCandidate() {
        guard state == .presenting else { return }
        guard currentIndex + 1 < candidates.count else {
            stopPresentationTask()
            state = .exhausted
            statusText = "已经到达候选列表末尾"
            announce("已经到达候选列表末尾。")
            return
        }
        currentIndex += 1
        statusText = "已选择第 \(currentNumber) 个密码，共 \(totalCount) 个"
        announceCurrentCandidate()
        updateEstimatedTime()
    }

    func moveToPreviousCandidate() {
        guard canMoveBackward else { return }
        currentIndex -= 1
        statusText = "已选择第 \(currentNumber) 个密码，共 \(totalCount) 个"
        announceCurrentCandidate()
        updateEstimatedTime()
    }

    func repeatCurrentAnnouncement() {
        guard currentPassword != nil else { return }
        announceCurrentCandidate()
    }

    func beginSingleVerification() {
        guard let password = currentPassword, state == .presenting else { return }
        // 跳过明显无效的密码（非空且长度<8，但允许空密码用于开放网络）
        if !password.isEmpty && password.count < 8 {
            let msg = "密码长度不足 8 位，跳过。"
            statusText = msg
            announce(msg)
            moveToNextCandidate()
            if autoVerifyEnabled && state == .presenting {
                startAutoVerify()
            }
            return
        }

        stopPresentationTask()
        state = .verifying
        attemptCount += 1
        statusText = "正在验证第 \(currentNumber) 个密码"
        announce("正在验证第 \(currentNumber) 个密码。系统可能要求确认加入网络。")
        updateEstimatedTime()
    }

    func handleVerificationFailure() {
        guard state == .verifying else { return }
        state = .presenting
        statusText = "第 \(currentNumber) 个密码未连接成功"

        // 指数退避：失败后增加延迟
        currentDelay = min(currentDelay * 1.5, maxDelay)
        let delayMsg = String(format: "下次尝试等待 %.1f 秒", currentDelay)
        announce("连接未成功。\(delayMsg)。自动继续下一个候选。")

        moveToNextCandidate()
        if autoVerifyEnabled && state == .presenting {
            // 使用更新后的延迟重新启动自动验证
            startAutoVerify()
        }
    }

    func handleVerificationCancellation() {
        guard state == .verifying else { return }
        state = .presenting
        statusText = "本次验证已取消"
        announce("本次验证已取消。三秒后会继续朗读候选密码。")
        restartPresentationTaskIfNeeded()
    }

    func handleVerificationSuccess(ssid: String) {
        stop()
        state = .succeeded
        statusText = "已连接到“\(ssid)”"
        announce("连接成功。已连接到 \(ssid)。")
    }

    func announceSettingsPreview() {
        announce("语音提示预览。当前语速、音调和音量设置已经生效。")
    }

    // MARK: - 私有方法
    private func startAutoVerify() {
        stopAutoVerify()
        guard autoVerifyEnabled, state == .presenting else { return }

        verifyTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                // 暂停检查
                if self.isPaused {
                    await withCheckedContinuation { continuation in
                        self.pauseContinuation = continuation
                    }
                }
                guard !Task.isCancelled, self.autoVerifyEnabled, self.state == .presenting else { return }

                // 使用当前动态延迟
                let delayNs = UInt64(self.currentDelay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delayNs)

                guard !Task.isCancelled, self.autoVerifyEnabled, self.state == .presenting else { return }

                // 检查是否达到最大尝试次数
                if self.attemptCount >= self.maxAttempts {
                    await MainActor.run {
                        self.stop()
                        self.state = .exhausted
                        self.statusText = "已达到最大尝试次数，停止自动验证。"
                        self.announce("已达到最大尝试次数，停止自动验证。")
                    }
                    return
                }

                await MainActor.run {
                    UIAccessibility.post(notification: .announcement, argument: "自动验证当前密码")
                    self.beginSingleVerification()
                }
            }
        }
    }

    private func stopAutoVerify() {
        verifyTask?.cancel()
        verifyTask = nil
        isPaused = false
        pauseContinuation?.resume()
        pauseContinuation = nil
    }

    private func restartPresentationTaskIfNeeded() {
        stopPresentationTask()
        guard autoAdvanceEnabled, state == .presenting else { return }

        presentationTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.presentationIntervalNanoseconds)
                guard !Task.isCancelled, self.autoAdvanceEnabled, self.state == .presenting else { return }
                self.moveToNextCandidate()
                if self.state == .exhausted { return }
            }
        }
    }

    private func scheduleAdvanceAfterFailure() {
        stopPresentationTask()
        guard state == .presenting else { return }

        presentationTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.presentationIntervalNanoseconds)
            guard !Task.isCancelled, self.state == .presenting else { return }
            self.moveToNextCandidate()
            if self.state == .presenting {
                self.restartPresentationTaskIfNeeded()
            }
        }
    }

    private func stopPresentationTask() {
        presentationTask?.cancel()
        presentationTask = nil
    }

    private func announceCurrentCandidate(prefix: String? = nil) {
        guard let currentPassword else { return }
        var components: [String] = []
        if let prefix { components.append(prefix) }
        components.append("正在提示第 \(currentNumber) 个密码，共 \(totalCount) 个。")
        if speakPasswordAloud {
            components.append("当前密码是：\(spokenPassword(currentPassword))。")
        } else {
            components.append("为保护隐私，密码内容没有朗读。")
        }
        components.append("要验证当前密码，请激活屏幕上的验证当前密码按钮。")
        announce(components.joined())
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
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN") ?? AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first)
        utterance.rate = min(max(speechRate, 0.35), 0.58)
        utterance.pitchMultiplier = min(max(speechPitch, 0.7), 1.5)
        utterance.volume = min(max(speechVolume, 0), 1)
        synthesizer.speak(utterance)
    }

    private func stopSpeech() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func spokenPassword(_ password: String) -> String {
        password.map { $0 == " " ? "空格" : String($0) }.joined(separator: "，")
    }

    private func updateEstimatedTime() {
        let remaining = max(0, totalCount - currentNumber)
        estimatedRemainingTime = Double(remaining) * currentDelay
        // 可在此更新UI或语音
    }
}