import AppKit
import CoreGraphics
import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac awake when the lid closes without an external display.
///
/// Idle assertions and cursor nudges do not block clamshell sleep. macOS sleeps
/// immediately on lid close unless an external display is attached, so this arms
/// `pmset -a disablesleep` ahead of time. That setting needs an administrator
/// password. The built-in panel itself turns off when the lid is shut; processes
/// keep running. A display-sleep assertion keeps the screen on while the lid is
/// still open.
final class ClosedLidKeepAwake {
    static let preferenceKey = "keepAwakeWithLidClosed"

    private(set) var isArmed = false
    private(set) var hasExternalDisplay = false

    var onDisplaysChanged: (() -> Void)?

    private var assertionID: IOPMAssertionID = 0
    private var holdsAssertion = false
    private var screenObserver: NSObjectProtocol?

    init() {
        hasExternalDisplay = Self.detectExternalDisplay()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshDisplays()
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        releaseDisplayAssertion()
    }

    func refreshDisplays() {
        let external = Self.detectExternalDisplay()
        guard external != hasExternalDisplay else { return }
        hasExternalDisplay = external
        onDisplaysChanged?()
    }

    enum ResumeResult {
        case armed
        case restored
        case idle
        case needsAdministrator
    }

    /// Re-arm a saved preference, or turn sleep back on if a previous session
    /// armed `disablesleep` and died before cleaning up.
    func resumeFromPreviousLaunch() -> ResumeResult {
        if UserDefaults.standard.bool(forKey: Self.preferenceKey) {
            if arm() { return .armed }
            UserDefaults.standard.set(false, forKey: Self.preferenceKey)
            return .needsAdministrator
        }
        if Self.markerExists() {
            return restoreSleep() ? .restored : .needsAdministrator
        }
        return .idle
    }

    @discardableResult
    func arm() -> Bool {
        guard Self.setDisableSleep(true) else { return false }
        acquireDisplayAssertion()
        Self.writeMarker()
        UserDefaults.standard.set(true, forKey: Self.preferenceKey)
        isArmed = true
        return true
    }

    /// User turned the feature off. The preference is cleared only if sleep is restored.
    @discardableResult
    func disarm() -> Bool {
        UserDefaults.standard.set(false, forKey: Self.preferenceKey)
        guard isArmed || Self.markerExists() else {
            isArmed = false
            return true
        }
        guard restoreSleep() else {
            UserDefaults.standard.set(true, forKey: Self.preferenceKey)
            return false
        }
        isArmed = false
        return true
    }

    /// App is quitting. Sleep is restored while Hyperactive is not running.
    /// The saved preference stays on so the next launch can re-arm.
    @discardableResult
    func disarmForTermination() -> Bool {
        guard isArmed || Self.markerExists() else { return true }
        guard restoreSleep() else { return false }
        isArmed = false
        return true
    }

    @discardableResult
    private func restoreSleep() -> Bool {
        guard Self.setDisableSleep(false) else { return false }
        releaseDisplayAssertion()
        Self.removeMarker()
        return true
    }

    private func acquireDisplayAssertion() {
        guard !holdsAssertion else { return }
        var newID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Hyperactive keeps the display on with the lid closed" as CFString,
            &newID
        )
        guard result == kIOReturnSuccess else { return }
        assertionID = newID
        holdsAssertion = true
    }

    private func releaseDisplayAssertion() {
        guard holdsAssertion else { return }
        IOPMAssertionRelease(assertionID)
        holdsAssertion = false
        assertionID = 0
    }

    static func detectExternalDisplay() -> Bool {
        NSScreen.screens.contains { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber else {
                return false
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            return !Self.isBuiltinDisplay(displayID)
        }
    }

    /// `CGDisplayIsBuiltin` is a `boolean_t`. The SDK imports that as either `Bool`
    /// or an integer, so treat any non-zero byte as the built-in panel.
    private static func isBuiltinDisplay(_ displayID: CGDirectDisplayID) -> Bool {
        var builtin = CGDisplayIsBuiltin(displayID)
        return withUnsafeBytes(of: &builtin) { bytes in
            bytes.contains { $0 != 0 }
        }
    }

    private static func setDisableSleep(_ disabled: Bool) -> Bool {
        let flag = disabled ? "1" : "0"
        let source = "do shell script \"/usr/bin/pmset -a disablesleep \(flag)\" with administrator privileges"
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        _ = script.executeAndReturnError(&error)
        if scriptFailed(error) {
            return false
        }
        if let actual = readDisableSleep() {
            return actual == disabled
        }
        return error == nil
    }

    private static func scriptFailed(_ error: NSDictionary?) -> Bool {
        guard let error else { return false }
        let number = error["NSAppleScriptErrorNumber"] as? NSNumber
        return number != nil && number?.intValue != 0
    }

    /// Reads the current system-wide `disablesleep` value. `nil` if `pmset` did not report it.
    private static func readDisableSleep() -> Bool? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2 else { continue }
            let key = parts[0].lowercased()
            if key == "disablesleep" || key == "sleepdisabled" {
                return parts[1] == "1"
            }
        }
        return nil
    }

    private static var markerURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("Hyperactive", isDirectory: true)
            .appendingPathComponent("disablesleep-armed", isDirectory: false)
    }

    private static func markerExists() -> Bool {
        FileManager.default.fileExists(atPath: markerURL.path)
    }

    private static func writeMarker() {
        let url = markerURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("1".utf8).write(to: url, options: .atomic)
        } catch {
            NSLog("Hyperactive failed to write sleep marker: \(error.localizedDescription)")
        }
    }

    private static func removeMarker() {
        try? FileManager.default.removeItem(at: markerURL)
    }
}
