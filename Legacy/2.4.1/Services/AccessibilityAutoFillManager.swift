import AVFoundation
import Combine
import Foundation
import UIKit

@MainActor
final class AccessibilityAutoFillManager: ObservableObject {
    enum State: Equatable {
        case idle
        case presenting
        case verifying
        case succeeded
        case stopped
        case exhausted
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var candidates: [String] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var statusText =
        "导入密码列表后，可启动无障碍辅助填充"
    @Published private(set) var lastAnnouncement = ""

    @Published var speechEnabled = true
    @Published var speakPasswordAloud = false
    @Published var autoAdvanceEnabled = true
    @Published var speechRate: Float = 0.48
    @Published var speechPitch: Float = 1.0
    @Published var speechVolume: Float = 1.0

    private let synthesizer = AVSpeechSynthesizer()
    private var presentationTask: Task<Void, Never>?
    private var suspendedForBackground = false

    private let maximumCandidateCount = VerificationLimit.absoluteMaximum
    private let presentationIntervalNanoseconds: UInt64 = 3_000_000_000

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
        guard candidates.indices.contains(currentIndex) else {
            return nil
        }

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
        state == .presenting &&
        currentIndex + 1 < candidates.count
    }

    func start(
        with importedPasswords: [String],
        limit: VerificationLimit = .fifty,
        preserveIndex: Bool = false
    ) {
        stopPresentationTask()
        stopSpeech()

        let resolvedCount = min(
            limit.resolvedCount(availableCount: importedPasswords.count),
            maximumCandidateCount
        )
        let limitedCandidates = Array(importedPasswords.prefix(resolvedCount))
        let previousIndex = currentIndex

        guard !limitedCandidates.isEmpty else {
            candidates = []
            currentIndex = 0
            state = .idle
            statusText = "没有可用于辅助填充的候选密码"
            announce("没有可用于辅助填充的候选密码。")
            return
        }

        candidates = limitedCandidates
        currentIndex = preserveIndex
            ? min(max(previousIndex, 0), limitedCandidates.count - 1)
            : 0
        state = .presenting
        statusText =
            "已选择第 \(currentIndex + 1) 个密码，共 \(limitedCandidates.count) 个"

        let planDescription = limit == .all
            ? "已载入全部 \(limitedCandidates.count) 个候选密码。"
            : "已按计划载入 \(limitedCandidates.count) 个候选密码。"

        announceCurrentCandidate(
            prefix: "无障碍辅助填充已开始。" + planDescription
        )

        restartPresentationTaskIfNeeded()
    }

    func stop() {
        stopPresentationTask()
        stopSpeech()

        state = .stopped
        statusText = "无障碍辅助填充已停止"
        announce("无障碍辅助填充已停止。")
    }

    /// Stops timers and speech when the app is no longer active. The candidate
    /// selection is retained, but no verification or narration is kept alive in
    /// the background.
    func suspendForBackground() {
        suspendedForBackground = isRunning
        stopPresentationTask()
        stopSpeech()

        if state == .verifying {
            state = .presenting
        }

        if suspendedForBackground {
            statusText = "应用进入后台，候选导航已暂停"
        }
    }

    /// Candidate narration may resume after returning to the foreground, but a
    /// continuous Wi-Fi validation session must still be resumed explicitly.
    func resumeAfterBackground() {
        guard suspendedForBackground else { return }
        suspendedForBackground = false

        guard state == .presenting else { return }
        statusText = "已返回前台，可继续验证第 \(currentNumber) 个候选"
        restartPresentationTaskIfNeeded()
    }

    func reset() {
        stopPresentationTask()
        stopSpeech()

        candidates = []
        currentIndex = 0
        state = .idle
        statusText =
            "导入密码列表后，可启动无障碍辅助填充"
        lastAnnouncement = ""
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
        statusText =
            "已选择第 \(currentNumber) 个密码，共 \(totalCount) 个"

        announceCurrentCandidate()
    }

    func moveToPreviousCandidate() {
        guard canMoveBackward else { return }

        currentIndex -= 1
        statusText =
            "已选择第 \(currentNumber) 个密码，共 \(totalCount) 个"

        announceCurrentCandidate()
    }

    func selectCandidate(at index: Int, announceSelection: Bool = true) {
        guard !candidates.isEmpty else { return }

        stopPresentationTask()
        currentIndex = min(max(index, 0), candidates.count - 1)

        if state == .stopped || state == .exhausted {
            state = .presenting
        }

        statusText =
            "已选择第 \(currentNumber) 个密码，共 \(totalCount) 个"

        if announceSelection {
            announceCurrentCandidate()
        }

        restartPresentationTaskIfNeeded()
    }

    func repeatCurrentAnnouncement() {
        guard currentPassword != nil else { return }
        announceCurrentCandidate()
    }

    @discardableResult
    func beginSingleVerification() -> Bool {
        guard currentPassword != nil, state == .presenting else {
            return false
        }

        stopPresentationTask()
        state = .verifying
        statusText =
            "正在验证第 \(currentNumber) 个密码"

        announce(
            "正在验证第 \(currentNumber) 个密码。"
            + "系统可能要求确认加入网络。"
        )
        return true
    }

    func handleVerificationFailure(autoAdvance: Bool = true) {
        guard state == .verifying else { return }

        state = .presenting
        statusText =
            "第 \(currentNumber) 个密码未连接成功"

        if autoAdvance {
            announce(
                "连接未成功。"
                + "三秒后会选择下一个密码。"
                + "你也可以再次激活验证当前密码按钮。"
            )
            scheduleAdvanceAfterFailure()
        } else {
            announce(
                "连接未成功。"
                + "候选位置将由连续辅助模式管理。"
            )
        }
    }

    func handleVerificationCancellation(restartPresentation: Bool = true) {
        guard state == .verifying else { return }

        state = .presenting
        statusText = "本次验证已取消"

        if restartPresentation {
            announce(
                "本次验证已取消。"
                + "三秒后会继续朗读候选密码。"
            )
            restartPresentationTaskIfNeeded()
        } else {
            announce(
                "本次验证已取消。"
                + "候选位置保持不变。"
            )
        }
    }

    func handleVerificationSuccess(ssid: String) {
        stopPresentationTask()
        stopSpeech()

        state = .succeeded
        statusText = "已连接到“\(ssid)”"

        announce("连接成功。已连接到 \(ssid)。")
    }

    func announceSettingsPreview() {
        announce(
            "语音提示预览。"
            + "当前语速、音调和音量设置已经生效。"
        )
    }

    private func restartPresentationTaskIfNeeded() {
        stopPresentationTask()

        guard autoAdvanceEnabled, state == .presenting else {
            return
        }

        presentationTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds:
                        self.presentationIntervalNanoseconds
                )

                guard
                    !Task.isCancelled,
                    self.autoAdvanceEnabled,
                    self.state == .presenting
                else {
                    return
                }

                self.moveToNextCandidate()

                if self.state == .exhausted {
                    return
                }
            }
        }
    }

    private func scheduleAdvanceAfterFailure() {
        stopPresentationTask()

        guard state == .presenting else { return }

        presentationTask = Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(
                nanoseconds:
                    self.presentationIntervalNanoseconds
            )

            guard
                !Task.isCancelled,
                self.state == .presenting
            else {
                return
            }

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

    private func announceCurrentCandidate(
        prefix: String? = nil
    ) {
        guard let currentPassword else { return }

        var components: [String] = []

        if let prefix {
            components.append(prefix)
        }

        components.append(
            "正在提示第 \(currentNumber) 个密码，"
            + "共 \(totalCount) 个。"
        )

        if speakPasswordAloud {
            components.append(
                "当前密码是："
                + "\(spokenPassword(currentPassword))。"
            )
        } else {
            components.append(
                "为保护隐私，密码内容没有朗读。"
            )
        }

        components.append(
            "要验证当前密码，"
            + "请激活屏幕上的验证当前密码按钮。"
        )

        announce(components.joined())
    }

    private func announce(_ text: String) {
        lastAnnouncement = text

        guard speechEnabled else { return }

        stopSpeech()

        // VoiceOver is itself a speech system. Posting an accessibility
        // announcement prevents AVSpeechSynthesizer from speaking over it.
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(
                notification: .announcement,
                argument: text
            )
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice =
            AVSpeechSynthesisVoice(language: "zh-CN")
            ?? AVSpeechSynthesisVoice(
                language: Locale.preferredLanguages.first
            )
        utterance.rate =
            min(max(speechRate, 0.35), 0.58)
        utterance.pitchMultiplier =
            min(max(speechPitch, 0.7), 1.5)
        utterance.volume =
            min(max(speechVolume, 0), 1)

        synthesizer.speak(utterance)
    }

    private func stopSpeech() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func spokenPassword(_ password: String) -> String {
        password
            .map { character in
                if character == " " {
                    return "空格"
                }

                return String(character)
            }
            .joined(separator: "，")
    }
}
