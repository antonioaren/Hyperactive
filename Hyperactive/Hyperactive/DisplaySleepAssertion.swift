import Foundation
import IOKit.pwr_mgt

/// Keeps the display on while Snooze is in Screen only mode.
///
/// This is a separate assertion from the one closed-lid keep-awake holds.
/// Releasing it leaves that other assertion, and `pmset disablesleep`, alone.
/// The assertion ends when this process does, so a crash does not leave the
/// display forced on.
final class DisplaySleepAssertion {
    private(set) var isHeld = false
    private var assertionID: IOPMAssertionID = 0

    func acquire() {
        guard !isHeld else { return }
        var newID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Hyperactive keeps the display on outside active hours" as CFString,
            &newID
        )
        guard result == kIOReturnSuccess else {
            NSLog("Hyperactive failed to hold a display assertion: \(result)")
            return
        }
        assertionID = newID
        isHeld = true
    }

    func release() {
        guard isHeld else { return }
        IOPMAssertionRelease(assertionID)
        isHeld = false
        assertionID = 0
    }
}
