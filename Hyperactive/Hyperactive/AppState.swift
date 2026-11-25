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
    private(set) var settings = SnoozeSettings.disabled

    private var timer: DispatchSourceTimer?
    private var boundaryTimer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.hyperactive.timer", qos: .utility)
    private let closedLidKeepAwake = ClosedLidKeepAwake()
    private let displayAssertion = DisplaySleepAssertion()
    private var didPrepareForTermination = false
    private var isTerminating = false
    private var appliedActivity: Activity = .idle
    private var override: ManualOverride?
    private var lastDecision = SnoozeDecision(activity: .idle, override: nil, nextChange: nil)
    private var workspaceObservers: [NSObjectProtocol] = []
    private var notificationObservers: [NSObjectProtocol] = []

    static let closedLidHeatWarning = "Runs hot with the lid closed. Don't put the Mac in a bag. If sleep stays disabled, run sudo pmset -a disablesleep 0"

    var menuBarIcon: String {
        SnoozeSchedule.symbol(
            nudging: isActive,
            snoozeEnabled: settings.enabled,
            showingDisplay: appliedActivity == .display,
            paused: isPaused,
            blocked: accessibilityBlocked
        )
    }

    var statusText: String {
        if !settings.enabled {
            if isActive {
                var text = "Active — \(nudgeCount) nudge\(nudgeCount == 1 ? "" : "s")"
                if let last = lastNudgeTime {
                    text += " (last: \(Self.shortTime(last)))"
                }
                return text
            }
            return "Inactive"
        }
        return SnoozeSchedule.statusLine(
            now: Date(),
            calendar: .current,
            decision: lastDecision,
            nudgeCount: nudgeCount,
            lastNudge: lastNudgeTime,
            accessibilityBlocked: accessibilityBlocked,
            locale: .current
        )
    }

    var snoozeOutsideCaption: String? {
        guard settings.enabled, !isActive, !isPaused, !accessibilityBlocked else { return nil }
        switch settings.outsideMode {
        case .off:
            return "Outside active hours, Hyperactive does nothing."
        case .screenOnly:
            return "Outside active hours, the display stays on and the pointer stays still."
        }
    }

    var showsClosedLidDuringSnooze: Bool {
        settings.enabled && keepAwakeWithLidClosed && !isActive
    }

    var closedLidStatusText: String {
        if hasExternalDisplay {
            return "External display connected — macOS can already stay awake with the lid closed."
        }
        return "No external display — closing the lid would normally sleep this Mac."
    }

    private var isPaused: Bool {
        if case .forceIdle = override { return true }
        return false
    }

    private var accessibilityBlocked: Bool {
        settings.enabled && !hasAccessibility && lastDecision.activity == .nudge && !isActive
    }

    init() {
        settings = SnoozeSettings.load()
        intervalMinutes = NudgeInterval.load(from: .standard)
        NudgeInterval.save(intervalMinutes, to: .standard)
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

        workspaceObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleWake()
            }
        )
        observeClockChanges()
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.recheckAccessibility()
            }
        )
        startAccessibilityWatch()

        DispatchQueue.main.async { [weak self] in
            self?.resumeClosedLidIfNeeded()
        }

        if settings.enabled {
            reconcile(restartNudgeTimer: false, userInitiated: false)
        }
    }

    deinit {
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        timer?.cancel()
        boundaryTimer?.cancel()
        accessibilityWatch?.cancel()
        accessibilityPollTimer?.cancel()
        displayAssertion.release()
    }

    /// Re-check accessibility status when the menu opens.
    func refreshAccessibility() {
        hasAccessibility = AccessibilityHelper.isTrusted()
    }

    func refreshForMenu() {
        refreshAccessibility()
        refreshDisplays()
        guard settings.enabled, !isTerminating else { return }
        reconcile(restartNudgeTimer: false, userInitiated: false)
    }

    func toggle() {
        guard !isTerminating else { return }
        if !settings.enabled {
            if isActive {
                stop()
            } else {
                start()
            }
            return
        }
        if isActive {
            if case .forceNudge = override {
                override = nil
            } else {
                override = .forceIdle
            }
        } else if case .forceIdle = override {
            override = nil
        } else {
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            if let year = parts.year, let month = parts.month, let day = parts.day {
                override = .forceNudge(year: year, month: month, day: day)
            }
        }
        reconcile(restartNudgeTimer: false, userInitiated: true)
    }

    func start() {
        let effect = SnoozeSchedule.effect(for: .nudge, accessibilityTrusted: AccessibilityHelper.isTrusted())
        hasAccessibility = !effect.needsAccessibility
        guard effect.runNudges else {
            promptForAccessibilityOnce()
            return
        }
        isActive = true
        appliedActivity = .nudge
        displayAssertion.acquire()
        cancelBoundaryTimer()
        startTimer()
    }

    private var accessibilityPollTimer: DispatchSourceTimer?
    private var accessibilityWatch: DispatchSourceTimer?
    private var didRequestAccessibilityPrompt = false

    private func promptForAccessibilityOnce() {
        guard !didRequestAccessibilityPrompt else { return }
        didRequestAccessibilityPrompt = true
        AccessibilityHelper.requestAccess()
        startAccessibilityPolling()
    }

    /// Notices a grant or a revoke without restarting. Does not show the system prompt.
    private func startAccessibilityWatch() {
        let watch = DispatchSource.makeTimerSource(queue: .main)
        watch.schedule(deadline: .now() + 2, repeating: 2)
        watch.setEventHandler { [weak self] in
            self?.recheckAccessibility()
        }
        watch.resume()
        accessibilityWatch = watch
    }

    private func recheckAccessibility() {
        guard !isTerminating else { return }
        let trusted = AccessibilityHelper.isTrusted()
        guard trusted != hasAccessibility else { return }
        hasAccessibility = trusted
        if settings.enabled {
            reconcile(restartNudgeTimer: false, userInitiated: false)
        } else if !trusted && isActive {
            stop()
        }
    }

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
                if self.settings.enabled {
                    self.reconcile(restartNudgeTimer: true, userInitiated: true)
                } else {
                    self.isActive = true
                    self.appliedActivity = .nudge
                    self.displayAssertion.acquire()
                    self.startTimer()
                }
            }
        }
        poll.resume()
        accessibilityPollTimer = poll

        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.accessibilityPollTimer?.cancel()
            self?.accessibilityPollTimer = nil
        }
    }

    func stop() {
        isActive = false
        appliedActivity = .idle
        stopTimer()
        displayAssertion.release()
        if !settings.enabled {
            cancelBoundaryTimer()
        }
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
        stopTimer()
        cancelBoundaryTimer()
        accessibilityPollTimer?.cancel()
        accessibilityPollTimer = nil
        accessibilityWatch?.cancel()
        accessibilityWatch = nil
        displayAssertion.release()
        closedLidKeepAwake.disarmForTermination()
    }

    func setSnoozeEnabled(_ enabled: Bool) {
        guard !isTerminating else { return }
        if enabled == settings.enabled { return }
        if !enabled {
            disableSnooze()
            return
        }
        if settings.hasEffectiveWindow {
            settings.enabled = true
            override = nil
            persistSnooze()
            reconcile(restartNudgeTimer: false, userInitiated: false)
            return
        }
        SnoozeEditorPresenter.shared.show(
            draft: settings.seededForFirstEnable(),
            enableOnDone: true
        ) { [weak self] edited in
            self?.commitSnoozeEdit(edited, enableOnDone: true)
        }
    }

    func setOutsideMode(_ mode: OutsideMode) {
        guard !isTerminating else { return }
        guard settings.outsideMode != mode else { return }
        settings.outsideMode = mode
        persistSnooze()
        if settings.enabled {
            reconcile(restartNudgeTimer: false, userInitiated: false)
        }
    }

    func setWeekdaysOnly(_ enabled: Bool) {
        guard !isTerminating else { return }
        guard settings.weekdaysOnly != enabled else { return }
        settings.weekdaysOnly = enabled
        persistSnooze()
        if settings.enabled {
            reconcile(restartNudgeTimer: false, userInitiated: false)
        }
    }

    func editSnoozeSchedule() {
        guard !isTerminating else { return }
        SnoozeEditorPresenter.shared.show(draft: settings, enableOnDone: false) { [weak self] edited in
            self?.commitSnoozeEdit(edited, enableOnDone: false)
        }
    }

    func updateInterval(_ minutes: Int) {
        intervalMinutes = NudgeInterval.resolved(minutes)
        NudgeInterval.save(intervalMinutes, to: .standard)
        if isActive {
            restartTimer()
        }
    }

    private func commitSnoozeEdit(_ edited: SnoozeSettings, enableOnDone: Bool) {
        guard !isTerminating else { return }
        var updated = edited.normalized()
        if enableOnDone {
            guard updated.hasEffectiveWindow else { return }
            updated.enabled = true
            override = nil
        } else {
            updated.enabled = settings.enabled
        }
        settings = updated
        persistSnooze()
        if settings.enabled {
            reconcile(restartNudgeTimer: false, userInitiated: false)
        }
    }

    private func disableSnooze() {
        let wasNudging = isActive
        settings.enabled = false
        override = nil
        persistSnooze()
        cancelBoundaryTimer()
        if wasNudging {
            appliedActivity = .nudge
            displayAssertion.acquire()
        } else {
            displayAssertion.release()
            stopTimer()
            isActive = false
            appliedActivity = .idle
        }
    }

    private func persistSnooze() {
        settings.save(to: .standard)
    }

    private func resumeClosedLidIfNeeded() {
        guard !isTerminating else { return }
        let result = closedLidKeepAwake.resumeFromPreviousLaunch()
        keepAwakeWithLidClosed = closedLidKeepAwake.isArmed
        if result == .needsAdministrator {
            closedLidMessage = "Sleep settings were not changed. Administrator permission is required."
        }
    }

    private func handleWake() {
        guard !isTerminating else { return }
        if settings.enabled {
            reconcile(restartNudgeTimer: true, userInitiated: false)
        } else if isActive {
            restartTimer()
        }
    }

    private func observeClockChanges() {
        let names = [
            Notification.Name("NSSystemClockDidChangeNotification"),
            Notification.Name("NSSystemTimeZoneDidChangeNotification"),
        ]
        for name in names {
            notificationObservers.append(
                NotificationCenter.default.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    guard let self, self.settings.enabled, !self.isTerminating else { return }
                    self.reconcile(restartNudgeTimer: false, userInitiated: false)
                }
            )
        }
    }

    private func reconcile(restartNudgeTimer: Bool, userInitiated: Bool, now: Date = Date()) {
        guard !isTerminating, settings.enabled else { return }
        let decision = SnoozeSchedule.decide(
            now: now,
            calendar: .current,
            settings: settings,
            override: override
        )
        override = decision.override
        lastDecision = decision
        apply(decision.activity, restartNudgeTimer: restartNudgeTimer, userInitiated: userInitiated)
        scheduleBoundary(nextChange: decision.nextChange, now: now)
    }

    private func apply(_ activity: Activity, restartNudgeTimer: Bool, userInitiated: Bool) {
        let trusted = AccessibilityHelper.isTrusted()
        hasAccessibility = trusted
        let effect = SnoozeSchedule.effect(for: activity, accessibilityTrusted: trusted)
        if effect.needsAccessibility && userInitiated {
            promptForAccessibilityOnce()
        }

        if effect.runNudges {
            displayAssertion.acquire()
            startNudging(restartTimer: restartNudgeTimer)
            appliedActivity = .nudge
            return
        }

        stopTimer()
        isActive = false
        if effect.holdDisplayAssertion {
            displayAssertion.acquire()
            appliedActivity = .display
        } else {
            displayAssertion.release()
            appliedActivity = .idle
        }
    }

    private func startNudging(restartTimer: Bool) {
        let running = isActive && timer != nil
        isActive = true
        if SnoozeSchedule.shouldRestartNudgeTimer(isRunning: running, restartRequested: restartTimer) {
            startTimer()
        }
    }

    private func scheduleBoundary(nextChange: Date?, now: Date) {
        boundaryTimer?.cancel()
        boundaryTimer = nil
        guard settings.enabled else { return }
        let fire: Date
        if let scheduled = SnoozeSchedule.timerFireDate(now: now, nextChange: nextChange) {
            fire = scheduled
        } else if let nextChange, nextChange <= now {
            fire = now.addingTimeInterval(1)
        } else {
            return
        }
        let delay = max(fire.timeIntervalSince(now), 0.05)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        let milliseconds = max(Int(delay * 1_000), 50)
        timer.schedule(wallDeadline: .now() + .milliseconds(milliseconds), leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            self?.reconcile(restartNudgeTimer: false, userInitiated: false)
        }
        timer.resume()
        boundaryTimer = timer
    }

    private func cancelBoundaryTimer() {
        boundaryTimer?.cancel()
        boundaryTimer = nil
    }

    private func startTimer() {
        stopTimer()
        let source = DispatchSource.makeTimerSource(queue: timerQueue)
        let seconds = NudgeInterval.seconds(for: intervalMinutes)
        source.schedule(deadline: .now() + seconds, repeating: seconds)
        source.setEventHandler { [weak self] in
            self?.performNudge()
        }
        source.resume()
        timer = source

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
        guard AccessibilityHelper.isTrusted() else {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isTerminating else { return }
                self.hasAccessibility = false
                if self.settings.enabled {
                    self.reconcile(restartNudgeTimer: false, userInitiated: false)
                } else {
                    self.stop()
                }
            }
            return
        }
        let success = MouseNudger.nudge()
        DispatchQueue.main.async {
            if success {
                self.nudgeCount += 1
                self.lastNudgeTime = Date()
            }
        }
    }

    private static func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
