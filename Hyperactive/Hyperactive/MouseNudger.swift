import CoreGraphics
import Foundation

enum MouseNudger {
    private static let offsets = [-4, -3, -2, 2, 3, 4]

    /// Nudge the mouse cursor by a few pixels and back. Direct port of keep_active.py lines 59-72.
    static func nudge() -> Bool {
        guard let event = CGEvent(source: nil) else { return false }
        let currentPos = event.location

        let dx = Double(offsets.randomElement()!)
        let dy = Double(offsets.randomElement()!)
        let newPos = CGPoint(x: currentPos.x + dx, y: currentPos.y + dy)

        guard let moveEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: newPos,
            mouseButton: .left
        ) else { return false }
        moveEvent.post(tap: .cghidEventTap)

        Thread.sleep(forTimeInterval: 0.15)

        guard let moveBack = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: currentPos,
            mouseButton: .left
        ) else { return false }
        moveBack.post(tap: .cghidEventTap)

        return true
    }
}
