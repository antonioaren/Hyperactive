import SwiftUI

@main
struct HyperactiveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @State private var updateChecker = UpdateChecker()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState, updateChecker: updateChecker)
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
