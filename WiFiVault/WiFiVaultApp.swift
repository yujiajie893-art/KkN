import SwiftUI

@main
struct WiFiVaultApp: App {
    @StateObject private var store = WiFiStore()
    @StateObject private var autoConnect = AutoConnectManager()
    @StateObject private var passwordTester = PasswordTesterManager()
    @StateObject private var accessibilityFill =
        AccessibilityAutoFillManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(autoConnect)
                .environmentObject(passwordTester)
                .environmentObject(accessibilityFill)
        }
    }
}
