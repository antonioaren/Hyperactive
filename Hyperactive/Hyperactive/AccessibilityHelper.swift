import ApplicationServices
import AppKit

enum AccessibilityHelper {
    /// `AXIsProcessTrusted` is the permission check. Creating a `CGEvent` and
    /// calling `post` both succeed when Accessibility is off; macOS just
    /// discards the event. Treating that as success made Snooze look active
    /// after an update replaced the ad-hoc signature and dropped the old grant.
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
