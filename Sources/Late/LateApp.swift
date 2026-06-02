import SwiftUI

@main
struct LateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?
    private var statusBarController: StatusBarController?
    private var hotKeyManager: HotKeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let appState = AppState()
        let statusBarController = StatusBarController(appState: appState)

        self.appState = appState
        self.statusBarController = statusBarController
        self.hotKeyManager = HotKeyManager {
            statusBarController.togglePanel()
        }

        DispatchQueue.main.async {
            statusBarController.showPanel()
        }
    }
}
