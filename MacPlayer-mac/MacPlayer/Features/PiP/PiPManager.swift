import Foundation
import AppKit

/// Manages Picture-in-Picture mode using Apple's private PIPViewController.
/// Works with any NSView (mpv OpenGL, Metal, etc.) — not limited to AVFoundation.
@MainActor
@Observable
final class PiPManager: NSObject {
    private(set) var isActive: Bool = false
    private(set) var isPossible: Bool = false

    /// The video rendering view to present in PiP.
    private weak var videoView: NSView?

    /// Callback to query current playback state (for PiP play/pause button sync).
    var playbackStateProvider: (() -> Bool)?

    /// Callback invoked when the user taps play/pause in the PiP window.
    var onTogglePlayPause: (() -> Void)?

    private var pipController: PIPViewController?
    private var pipVideo: NSViewController?

    /// Aspect ratio locked at PiP entry — used by MPVVideoNSView to block non-proportional resizes.
    private(set) var lockedAspectRatio: NSSize?

    /// Original superview — saved before entering PiP so we can restore the view.
    private weak var originalSuperview: NSView?
    /// Original window for replacement animation.
    private weak var originalWindow: NSWindow?


    /// Register a video view for PiP. Called from the NSView's viewDidMoveToWindow().
    func setup(videoView: NSView) {
        self.videoView = videoView
        isPossible = true
    }

    /// Toggle PiP mode on/off.
    func togglePiP() {
        if isActive {
            exitPiP()
        } else {
            enterPiP()
        }
    }

    /// Clean up PiP resources.
    func teardown() {
        exitPiP()
        videoView = nil
        isPossible = false
    }

    // MARK: - Enter / Exit

    private func enterPiP() {
        guard let videoView, !isActive else { return }

        originalSuperview = videoView.superview
        originalWindow = videoView.window

        let pip = VideoPIPViewController()
        pip.delegate = self
        pipController = pip

        let vc = NSViewController()
        vc.view = videoView
        pipVideo = vc

        let size = videoView.bounds.size
        if size.width > 0, size.height > 0 {
            pip.aspectRatio = size
            lockedAspectRatio = size
        }

        pip.playing = playbackStateProvider?() ?? false
        pip.presentAsPicture(inPicture: vc)
        isActive = true
    }

    private func exitPiP() {
        guard isActive, let pip = pipController, let vc = pipVideo else { return }
        prepareForClosure(pip)
        pip.dismiss(vc)
        doneExiting()
    }

    // MARK: - Restore

    /// Restore the video view to its original superview with Auto Layout (IINA pattern).
    private func restoreVideoView() {
        guard let videoView, let superview = originalSuperview else { return }
        superview.addSubview(videoView)
        videoView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: superview.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: superview.bottomAnchor),
            videoView.leadingAnchor.constraint(equalTo: superview.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: superview.trailingAnchor),
        ])
    }

    private func prepareForClosure(_ pip: PIPViewController) {
        if let window = originalWindow {
            pip.replacementWindow = window
            pip.replacementRect = window.contentView?.frame ?? .zero
        }
    }

    private func doneExiting() {
        restoreVideoView()
        pipController = nil
        pipVideo = nil
        originalSuperview = nil
        originalWindow = nil
        lockedAspectRatio = nil
        isActive = false
    }

    /// Update the PiP play/pause button state (call when engine state changes).
    func updatePlayingState(_ isPlaying: Bool) {
        pipController?.playing = isPlaying
    }

}

// MARK: - PIPViewControllerDelegate

extension PiPManager: PIPViewControllerDelegate {
    nonisolated func pipShouldClose(_ pip: PIPViewController) -> Bool {
        Task { @MainActor in self.prepareForClosure(pip) }
        return true
    }

    nonisolated func pipWillClose(_ pip: PIPViewController) {
        Task { @MainActor in self.prepareForClosure(pip) }
    }

    nonisolated func pipDidClose(_ pip: PIPViewController) {
        Task { @MainActor in self.doneExiting() }
    }

    nonisolated func pipActionPlay(_ pip: PIPViewController) {
        Task { @MainActor in
            self.onTogglePlayPause?()
            self.pipController?.playing = true
        }
    }

    nonisolated func pipActionPause(_ pip: PIPViewController) {
        Task { @MainActor in
            self.onTogglePlayPause?()
            self.pipController?.playing = false
        }
    }

    nonisolated func pipActionStop(_ pip: PIPViewController) {
        Task { @MainActor in self.onTogglePlayPause?() }
    }
}
