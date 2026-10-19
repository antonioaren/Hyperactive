import Foundation
import AppKit

@Observable
final class AppState {
    var isActive = false
    var intervalMinutes: Int = 5
    var nudgeCount: Int = 0
    var lastNudgeTime: Date?
    var hasAccessibility = false
    var launchAtLogin = false
    var keepAwakeWithLidClosed = false
    var hasExternalDisplay = false
    var closedLidMessage: String?

    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.hyperactive.timer", qos: .utility)
    private let closedLidKeepAwake = ClosedLidKeepAwake()
    private var didPrepareForTermination = false
    private var isTerminating = false

    static let closedLidHeatWarning = "Runs hot with the lid closed. Don't put the Mac in a bag. If sleep stays disabled, run sudo pmset -a disablesleep 0"

    var menuBarIcon: String {
        isActive ? "cursorarrow.motionlines" : "cursorarrow"
    }

    var statusText: String {
        if isActive {
            var text = "Active — \(nudgeCount) nudge\(nudgeCount == 1 ? "" : "s")"
            if let last = lastNudgeTime {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                text += " (last: \(formatter.string(from: last)))"
            }
            return text
        }
        return "Inactive"
    }

    var closedLidStatusText: String {
        if hasExternalDisplay {
            return "External display connected — macOS can already stay awake with the lid closed."
        }
        return "No external display — closing the lid would normally sleep this Mac."
    }

    init() {
        hasAccessibility = AccessibilityHelper.isTrusted()
        launchAtLogin = LaunchAtLoginHelper.isEnabled
        hasExternalDisplay = closedLidKeepAwake.hasExternalDisplay
        closedLidKeepAwake.onDisplaysChanged = { [weak self] in
            guard let self else { return }
            self.hasExternalDisplay = self.closedLidKeepAwake.hasExternalDisplay
        }
        AppDelegate.terminationHandler = { [weak self] in
            self?.prepareForTermination()
        }

        DispatchQueue.main.async { [weak self] in
            self?.resumeClosedLidIfNeeded()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isActive else { return }
            self.restartTimer()
        }
    }

    /// Re-check accessibility status when the menu opens
    func refreshAccessibility() {
        hasAccessibility = AccessibilityHelper.isTrusted()
    }

    func toggle() {
        if isActive {
            stop()
        } else {
            start()
        }
    }

    func start() {
        guard AccessibilityHelper.isTrusted() else {
            hasAccessibility = false
            AccessibilityHelper.requestAccess()
            // Poll for permission grant (e.g. user toggled it off/on after rebuild)
            startAccessibilityPolling()
            return
        }
        hasAccessibility = true
        isActive = true
        startTimer()
    }

    private var accessibilityPollTimer: DispatchSourceTimer?

    private func startAccessibilityPolling() {
        accessibilityPollTimer?.cancel()
        let poll = DispatchSource.makeTimerSource(queue: .main)
        poll.schedule(deadline: .now() + 1, repeating: 2)
        poll.setEventHandler { [weak self] in
            guard let self else { return }
            if AccessibilityHelper.isTrusted() {
                self.accessibilityPollTimer?.cancel()
                self.accessibilityPollTimer = nil
                self.hasAccessibility = true
                self.isActive = true
                self.startTimer()
            }
        }
        poll.resume()
        accessibilityPollTimer = poll

        // Stop polling after 60 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.accessibilityPollTimer?.cancel()
            self?.accessibilityPollTimer = nil
        }
    }

    func stop() {
        isActive = false
        stopTimer()
    }

    func refreshDisplays() {
        closedLidKeepAwake.refreshDisplays()
        hasExternalDisplay = closedLidKeepAwake.hasExternalDisplay
    }

    func setKeepAwakeWithLidClosed(_ enabled: Bool) {
        guard !isTerminating else { return }
        closedLidMessage = nil
        if enabled == keepAwakeWithLidClosed { return }

        if enabled {
            if closedLidKeepAwake.arm() {
                keepAwakeWithLidClosed = true
            } else {
                keepAwakeWithLidClosed = false
                closedLidMessage = "Sleep settings were not changed. Administrator permission is required."
            }
            return
        }

        if closedLidKeepAwake.disarm() {
            keepAwakeWithLidClosed = false
        } else {
            keepAwakeWithLidClosed = true
            closedLidMessage = "Sleep settings were not changed. Administrator permission is required."
        }
    }

    /// Restores normal sleep on quit. Safe to call more than once.
    func prepareForTermination() {
        guard !didPrepareForTermination else { return }
        didPrepareForTermination = true
        isTerminating = true
        closedLidKeepAwake.disarmForTermination()
    }

    private func resumeClosedLidIfNeeded() {
        guard !isTerminating else { return }
        let result = closedLidKeepAwake.resumeFromPreviousLaunch()
        keepAwakeWithLidClosed = closedLidKeepAwake.isArmed
        if result == .needsAdministrator {
            closedLidMessage = "Sleep settings were not changed. Administrator permission is required."
        }
    }

    func updateInterval(_ minutes: Int) {
        intervalMinutes = minutes
        if isActive {
            restartTimer()
        }
    }

    private func startTimer() {
        stopTimer()
        let source = DispatchSource.makeTimerSource(queue: timerQueue)
        let seconds = Double(intervalMinutes) * 60.0
        source.schedule(deadline: .now() + seconds, repeating: seconds)
        source.setEventHandler { [weak self] in
            self?.performNudge()
        }
        source.resume()
        timer = source

        // Perform an initial nudge immediately
        timerQueue.async { [weak self] in
            self?.performNudge()
        }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func restartTimer() {
        startTimer()
    }

    private func performNudge() {
        let success = MouseNudger.nudge()
        DispatchQueue.main.async {
            if success {
                self.nudgeCount += 1
                self.lastNudgeTime = Date()
            }
        }
    }
}
