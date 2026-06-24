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

    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.hyperactive.timer", qos: .utility)

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

    init() {
        hasAccessibility = AccessibilityHelper.isTrusted()
        launchAtLogin = LaunchAtLoginHelper.isEnabled

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
