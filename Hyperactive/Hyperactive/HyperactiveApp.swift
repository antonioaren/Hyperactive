import SwiftUI

@main
struct HyperactiveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image(systemName: appState.menuBarIcon)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var terminationHandler: (() -> Void)?

    func applicationWillTerminate(_ notification: Notification) {
        Self.terminationHandler?()
    }
}
