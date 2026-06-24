import SwiftUI

@main
struct HyperactiveApp: App {
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
