import Foundation
import AppKit

/// Observable window state for tracking fullscreen, aspect ratio, and window geometry.
/// Supports saving and restoring window position across app launches.
@MainActor
@Observable
final class WindowState {
    var isFullscreen: Bool = false
    var videoAspectRatio: CGFloat = 16.0 / 9.0
    var windowFrame: CGRect = .zero
    /// Saved window frame before entering fullscreen, for restoring on exit
    var priorWindowedFrame: NSRect?

    private let frameKey = "MacPlayer.WindowFrame"

    func updateAspectRatio(width: Int, height: Int) {
        guard height > 0 else { return }
        videoAspectRatio = CGFloat(width) / CGFloat(height)
    }

    /// Calculate ideal window size for the given video dimensions and screen.
    func idealWindowSize(for screen: NSScreen?) -> CGSize {
        guard let screen else {
            return CGSize(width: 1280, height: 720)
        }

        let screenFrame = screen.visibleFrame
        let maxWidth = screenFrame.width * 0.75
        let maxHeight = screenFrame.height * 0.75

        var width = maxWidth
        var height = width / videoAspectRatio

        if height > maxHeight {
            height = maxHeight
            width = height * videoAspectRatio
        }

        return CGSize(width: width, height: height)
    }

    // MARK: - Persistence

    /// Save the current window frame to UserDefaults.
    func saveFrame(_ frame: NSRect) {
        windowFrame = frame
        let dict: [String: Double] = [
            "x": Double(frame.origin.x),
            "y": Double(frame.origin.y),
            "w": Double(frame.size.width),
            "h": Double(frame.size.height)
        ]
        UserDefaults.standard.set(dict, forKey: frameKey)
    }

    /// Load the previously saved window frame, if any.
    func loadSavedFrame() -> NSRect? {
        guard let dict = UserDefaults.standard.dictionary(forKey: frameKey) as? [String: Double] else { return nil }
        guard let x = dict["x"], let y = dict["y"], let w = dict["w"], let h = dict["h"] else { return nil }
        return NSRect(x: x, y: y, width: w, height: h)
    }
}
