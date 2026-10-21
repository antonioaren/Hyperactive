import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState
    var updateChecker: UpdateChecker

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

        Text(AppVersion.installedDescription)
            .font(.caption)
            .foregroundStyle(.secondary)

        updateSection

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

    @ViewBuilder
    private var updateSection: some View {
        switch updateChecker.state {
        case .checking:
            Text("Checking for updates\u{2026}")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .installing:
            Text("Downloading and installing update\u{2026}")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .idle, .upToDate, .updateAvailable, .failed:
            if let release = updateChecker.availableRelease {
                Button("Update to v\(release.version.description)") {
                    updateChecker.installUpdate(beforeRelaunch: appState.prepareForTermination)
                }
            } else {
                Button("Check for Updates\u{2026}") {
                    updateChecker.checkForUpdates(userInitiated: true)
                }
            }

            if updateChecker.state == .upToDate {
                Text("Hyperactive is up to date")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if case .failed(let message) = updateChecker.state {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Open Releases Page\u{2026}") {
                    updateChecker.openReleasesPage()
                }
            }
        }
    }
}
