import AppKit
import SwiftUI

/// Transparent AppKit view that owns pointer interaction on the bare video area:
/// click to toggle the controls, double-click for full screen, drag to move the window.
///
/// It is mounted as the bottom layer of the SwiftUI overlay (see `PlayerInteractionLayer`),
/// so SwiftUI's hit testing sends a press here only when no control sits on top of it.
/// Presses on a control's background stay with that control and never reach this view.
final class PlayerInteractionView: NSView {
    /// Pointer travel before a press becomes a window drag instead of a click.
    private static let dragThreshold: CGFloat = 3

    private var mouseDownEvent: NSEvent?
    private var didStartWindowDrag = false

    private var playerController: PlayerWindowController? {
        window?.windowController as? PlayerWindowController
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didStartWindowDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownEvent, !didStartWindowDrag, let window,
              !window.styleMask.contains(.fullScreen) else { return }

        let start = mouseDownEvent.locationInWindow
        let current = event.locationInWindow
        guard hypot(current.x - start.x, current.y - start.y) > Self.dragThreshold else { return }

        // The window server takes over from here; the matching mouseUp may never arrive.
        didStartWindowDrag = true
        window.performDrag(with: mouseDownEvent)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        guard mouseDownEvent != nil, !didStartWindowDrag else { return }
        playerController?.surfaceClicked(with: event)
    }
}

/// Places `PlayerInteractionView` beneath the SwiftUI overlay controls.
struct PlayerInteractionLayer: NSViewRepresentable {
    func makeNSView(context: Context) -> PlayerInteractionView {
        PlayerInteractionView()
    }

    func updateNSView(_ nsView: PlayerInteractionView, context: Context) {}
}
