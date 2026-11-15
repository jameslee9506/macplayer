import Foundation
import IOKit.pwr_mgt

/// Prevents system sleep during video playback using IOPMAssertion.
/// Pattern adopted from IINA's SleepPreventer.
@MainActor
final class SleepPreventer {
    private var assertionID: IOPMAssertionID = 0
    private var isActive = false

    /// Prevent system sleep (call when playback starts).
    func preventSleep() {
        guard !isActive else { return }

        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "MacPlayer video playback" as CFString,
            &assertionID
        )

        if result == kIOReturnSuccess {
            isActive = true
        }
    }

    /// Allow system sleep (call when playback pauses/stops).
    func allowSleep() {
        guard isActive else { return }

        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }

    deinit {
        if isActive {
            IOPMAssertionRelease(assertionID)
        }
    }
}
