import Cocoa

/// PIPViewController subclass that ensures the PiP window has a black background
/// and forces video redraws during layout changes (resize, enter/exit).
/// Same pattern as IINA's VideoPIPViewController.
class VideoPIPViewController: PIPViewController {

    override func viewDidLayout() {
        super.viewDidLayout()

        // Ensure the PiP window background is black so resize doesn't flash white
        if let window = view.window {
            window.backgroundColor = .black
        }

        // Force the video layer to redraw at the new size
        forceRedraw()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        forceRedraw()
    }

    /// Trigger a redraw on the video view's backing layer.
    private func forceRedraw() {
        let videoView = view

        // MPVVideoNSView: find the MPVVideoLayer and force update
        if let mpvLayer = videoView.layer as? MPVVideoLayer {
            mpvLayer.update(force: true)
        }

        // MetalVideoNSView: trigger needsDisplay
        if videoView.layer is CAMetalLayer {
            videoView.needsDisplay = true
        }
    }
}
