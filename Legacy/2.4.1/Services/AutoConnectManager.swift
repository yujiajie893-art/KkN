import Foundation
import Combine
import NetworkExtension

@MainActor
final class AutoConnectManager: ObservableObject {
    enum ConnectionState: Equatable {
        case idle
        case preparing
        case waitingForSystem
        case verifying
        case connected
        case failed
        case cancelled
    }

    enum RequestOrigin: String, Equatable {
        case savedRecord
        case singleStep
        case continuousTrigger
    }

    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusText = "请选择一条已保存的 Wi-Fi 记录"
    @Published private(set) var connectedSSID: String?
    @Published private(set) var currentOrigin: RequestOrigin = .savedRecord
    @Published var notice: Notice?

    private let configurationManager = NEHotspotConfigurationManager.shared
    private var verificationTask: Task<Void, Never>?
    private var operationToken = UUID()

    var isRunning: Bool {
        switch state {
        case .preparing, .waitingForSystem, .verifying:
            return true
        default:
            return false
        }
    }

    func connect(
        ssid: String,
        password: String,
        joinOnce: Bool = false,
        origin: RequestOrigin = .savedRecord
    ) {
        guard !isRunning else { return }

        let cleanSSID = ssid.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanSSID.isEmpty else {
            fail("网络名称不能为空。")
            return
        }

        currentOrigin = origin
        notice = nil
        connectedSSID = nil
        state = .preparing
        progress = 0.05
        statusText = "正在检查“\(cleanSSID)”的候选格式…"

        #if targetEnvironment(simulator)
        fail("iOS 模拟器不能实际加入 Wi-Fi，请连接真机测试。")
        return
        #endif

        if let validationMessage = WiFiCredentialPolicy.connectionValidationMessage(
            for: password
        ) {
            fail(validationMessage)
            return
        }

        verificationTask?.cancel()

        let token = UUID()
        operationToken = token

        state = .preparing
        progress = 0.12
        statusText = "正在准备“\(cleanSSID)”的连接配置…"

        let configuration: NEHotspotConfiguration

        if password.isEmpty {
            configuration = NEHotspotConfiguration(ssid: cleanSSID)
        } else {
            configuration = NEHotspotConfiguration(
                ssid: cleanSSID,
                passphrase: password,
                isWEP: false
            )
        }

        // Single-step verification uses joinOnce so a failed candidate is not
        // left behind as a persistent Wi-Fi configuration. Saved-record flows
        // may still request a persistent configuration.
        configuration.joinOnce = joinOnce

        state = .waitingForSystem
        progress = 0.35
        statusText = "请在系统弹窗中确认加入该网络…"

        configurationManager.apply(configuration) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }

                self.handleApplyResult(
                    error,
                    expectedSSID: cleanSSID,
                    token: token
                )
            }
        }
    }

    func stop() {
        guard isRunning else { return }

        // NEHotspotConfigurationManager.apply 本身没有取消 API。
        // 这里停止应用自己的等待和验证流程，并让旧回调失效。
        operationToken = UUID()
        verificationTask?.cancel()
        verificationTask = nil

        state = .cancelled
        progress = 0
        statusText = "已停止后续确认流程"
    }

    func reset() {
        guard !isRunning else { return }

        state = .idle
        progress = 0
        statusText = "请选择一条已保存的 Wi-Fi 记录"
        connectedSSID = nil
        currentOrigin = .savedRecord
        notice = nil
    }

    private func handleApplyResult(
        _ error: Error?,
        expectedSSID: String,
        token: UUID
    ) {
        guard operationToken == token, state != .cancelled else { return }

        if let error {
            let nsError = error as NSError

            if nsError.code == NEHotspotConfigurationError.alreadyAssociated.rawValue {
                beginVerification(expectedSSID: expectedSSID, token: token)
                return
            }

            fail(friendlyMessage(for: nsError))
            return
        }

        beginVerification(expectedSSID: expectedSSID, token: token)
    }

    private func beginVerification(expectedSSID: String, token: UUID) {
        state = .verifying
        progress = 0.55
        statusText = "系统已接受配置，正在确认当前 Wi-Fi…"

        verificationTask?.cancel()

        verificationTask = Task { [weak self] in
            guard let self else { return }

            let maximumChecks = 10

            for checkIndex in 1...maximumChecks {
                if Task.isCancelled { return }

                try? await Task.sleep(nanoseconds: 700_000_000)

                guard
                    !Task.isCancelled,
                    self.operationToken == token,
                    self.state != .cancelled
                else {
                    return
                }

                let currentSSID = await self.fetchCurrentSSID()

                self.progress =
                    0.55 +
                    (Double(checkIndex) / Double(maximumChecks)) * 0.4

                self.statusText =
                    "正在确认连接… \(checkIndex)/\(maximumChecks)"

                if currentSSID == expectedSSID {
                    self.succeed(ssid: expectedSSID)
                    return
                }
            }

            guard self.operationToken == token else { return }

            self.fail(
                "系统没有确认已连接到“\(expectedSSID)”。请确认路由器在附近、保存的密码正确，并允许系统加入网络。"
            )
        }
    }

    private func fetchCurrentSSID() async -> String? {
        await withCheckedContinuation { continuation in
            NEHotspotNetwork.fetchCurrent { network in
                continuation.resume(returning: network?.ssid)
            }
        }
    }

    private func succeed(ssid: String) {
        verificationTask?.cancel()
        verificationTask = nil

        connectedSSID = ssid
        state = .connected
        progress = 1
        statusText = "已连接到“\(ssid)”"

        notice = Notice(
            title: "连接成功",
            message: "设备已连接到“\(ssid)”。"
        )
    }

    private func fail(_ message: String) {
        verificationTask?.cancel()
        verificationTask = nil

        connectedSSID = nil
        state = .failed
        progress = 0
        statusText = "连接失败"

        notice = Notice(
            title: "无法连接",
            message: message
        )
    }

    private func friendlyMessage(for error: NSError) -> String {
        switch error.code {
        case NEHotspotConfigurationError.userDenied.rawValue:
            return "你取消了系统的加入网络请求。"

        case NEHotspotConfigurationError.invalidSSID.rawValue:
            return "网络名称无效。"

        case NEHotspotConfigurationError.invalidWPAPassphrase.rawValue:
            return "保存的 Wi-Fi 密码格式无效。"

        case NEHotspotConfigurationError.applicationIsNotInForeground.rawValue:
            return "应用必须保持在前台，才能请求加入 Wi-Fi。"

        case NEHotspotConfigurationError.pending.rawValue:
            return "系统已有一个 Wi-Fi 配置请求正在处理中，请稍后再试。"

        case NEHotspotConfigurationError.systemDenied.rawValue:
            return "系统拒绝了这次 Wi-Fi 配置请求。请检查应用权限和签名能力。"

        default:
            return "系统返回错误：\(error.localizedDescription)"
        }
    }
}
