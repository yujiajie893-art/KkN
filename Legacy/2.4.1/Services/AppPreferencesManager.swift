import Combine
import Foundation
import SwiftUI

@MainActor
final class AppPreferencesManager: ObservableObject {
    enum AccentStyle: String, CaseIterable, Identifiable {
        case violet
        case ocean
        case emerald

        var id: String { rawValue }

        var title: String {
            switch self {
            case .violet: return "紫罗兰"
            case .ocean: return "深海蓝"
            case .emerald: return "翡翠绿"
            }
        }
    }

    enum InterfaceDensity: String, CaseIterable, Identifiable {
        case compact
        case comfortable
        case largeTargets

        var id: String { rawValue }

        var title: String {
            switch self {
            case .compact: return "紧凑"
            case .comfortable: return "舒适"
            case .largeTargets: return "大触控"
            }
        }

        var verticalSpacing: CGFloat {
            switch self {
            case .compact: return 14
            case .comfortable: return 18
            case .largeTargets: return 22
            }
        }

        var controlHeight: CGFloat {
            switch self {
            case .compact: return 48
            case .comfortable: return 54
            case .largeTargets: return 62
            }
        }
    }

    private enum Key {
        static let accentStyle = "vault.preferences.accentStyle"
        static let interfaceDensity = "vault.preferences.interfaceDensity"
        static let hapticsEnabled = "vault.preferences.hapticsEnabled"
        static let visualEffectsEnabled = "vault.preferences.visualEffectsEnabled"
        static let largeStatusText = "vault.preferences.largeStatusText"
    }

    @Published var accentStyle: AccentStyle {
        didSet { persist() }
    }

    @Published var interfaceDensity: InterfaceDensity {
        didSet { persist() }
    }

    @Published var hapticsEnabled: Bool {
        didSet { persist() }
    }

    @Published var visualEffectsEnabled: Bool {
        didSet { persist() }
    }

    @Published var largeStatusText: Bool {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        accentStyle = AccentStyle(
            rawValue: defaults.string(forKey: Key.accentStyle) ?? ""
        ) ?? .violet
        interfaceDensity = InterfaceDensity(
            rawValue: defaults.string(forKey: Key.interfaceDensity) ?? ""
        ) ?? .comfortable
        hapticsEnabled = defaults.object(forKey: Key.hapticsEnabled) as? Bool ?? true
        visualEffectsEnabled = defaults.object(forKey: Key.visualEffectsEnabled) as? Bool ?? true
        largeStatusText = defaults.object(forKey: Key.largeStatusText) as? Bool ?? false
        persist()
    }

    var renderToken: String {
        [
            accentStyle.rawValue,
            interfaceDensity.rawValue,
            hapticsEnabled.description,
            visualEffectsEnabled.description,
            largeStatusText.description
        ].joined(separator: "-")
    }

    func restoreDefaults() {
        accentStyle = .violet
        interfaceDensity = .comfortable
        hapticsEnabled = true
        visualEffectsEnabled = true
        largeStatusText = false
    }

    private func persist() {
        defaults.set(accentStyle.rawValue, forKey: Key.accentStyle)
        defaults.set(interfaceDensity.rawValue, forKey: Key.interfaceDensity)
        defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled)
        defaults.set(visualEffectsEnabled, forKey: Key.visualEffectsEnabled)
        defaults.set(largeStatusText, forKey: Key.largeStatusText)
    }
}
