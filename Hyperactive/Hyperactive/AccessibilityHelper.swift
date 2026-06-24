import ApplicationServices
import AppKit
import CoreGraphics

enum AccessibilityHelper {
    static func isTrusted() -> Bool {
        // AXIsProcessTrusted() can return stale results after a rebuild
        // (code signature changes but the TCC entry stays).
        // As a fallback, try posting a real CGEvent — this is the ground truth.
        if AXIsProcessTrusted() {
            return true
        }
        return canPostEvent()
    }

    /// Try to create and post a no-op mouse event to verify actual permission.
    private static func canPostEvent() -> Bool {
        guard let event = CGEvent(source: nil) else { return false }
        let pos = event.location
        guard let testEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: pos,
            mouseButton: .left
        ) else { return false }
        testEvent.post(tap: .cghidEventTap)
        return true
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
