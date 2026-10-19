import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState

    private static let intervals = [1, 2, 5, 10, 15, 30]

    var body: some View {
        Button(appState.isActive ? "Stop" : "Start") {
            appState.toggle()
        }
        .keyboardShortcut("s")
        .onAppear {
            appState.refreshAccessibility()
            appState.refreshDisplays()
        }

        Divider()

        Text(appState.statusText)

        if !appState.hasAccessibility {
            Text("Accessibility: not granted")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Toggle OFF then ON after rebuild")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Open Accessibility Settings\u{2026}") {
                AccessibilityHelper.openAccessibilitySettings()
            }
        }

        Divider()

        Menu("Interval") {
            ForEach(Self.intervals, id: \.self) { minutes in
                Button {
                    appState.updateInterval(minutes)
                } label: {
                    HStack {
                        Text("\(minutes) min")
                        if appState.intervalMinutes == minutes {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Divider()

        Toggle("Launch at Login", isOn: Binding(
            get: { appState.launchAtLogin },
            set: { _ in
                LaunchAtLoginHelper.toggle()
                appState.launchAtLogin = LaunchAtLoginHelper.isEnabled
            }
        ))

        Divider()

        Toggle("Keep Awake with Lid Closed", isOn: Binding(
            get: { appState.keepAwakeWithLidClosed },
            set: { appState.setKeepAwakeWithLidClosed($0) }
        ))

        Text(appState.closedLidStatusText)
            .font(.caption)
            .foregroundStyle(.secondary)

        Text(AppState.closedLidHeatWarning)
            .font(.caption2)
            .foregroundStyle(.secondary)

        if let closedLidMessage = appState.closedLidMessage {
            Text(closedLidMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        Divider()

        Button("About Hyperactive") {
            NSApplication.shared.orderFrontStandardAboutPanel()
        }

        Button("Quit") {
            appState.prepareForTermination()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
