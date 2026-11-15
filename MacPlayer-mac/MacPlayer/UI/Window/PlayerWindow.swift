import AppKit

/// Player window that offers every key press to the player before normal dispatch,
/// so playback shortcuts work no matter which control inside the window has focus.
final class PlayerWindow: NSWindow {
    /// Returns `true` when the key press was consumed.
    var keyDownHandler: ((NSEvent) -> Bool)?

    /// Command-key presses arrive here first, ahead of the main menu.
    /// AppKit may also consult a window that is not key, so shortcuts apply only while this one is.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isKeyWindow, event.type == .keyDown, keyDownHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    /// Plain key presses arrive here, ahead of the first responder.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyDownHandler?(event) == true { return }
        super.sendEvent(event)
    }
}
