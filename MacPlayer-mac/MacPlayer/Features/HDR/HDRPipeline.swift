import Foundation
import AppKit

/// HDR state observer — reads HDR metadata from mpv and exposes it for UI display.
/// All tone mapping, color space conversion, and gamut mapping are handled by mpv internally.
@MainActor
@Observable
final class HDRManager {
    // MARK: - Observable State (read from mpv properties)

    /// Whether the current video is HDR content
    private(set) var isHDRContent: Bool = false

    /// Transfer function name from mpv (e.g. "pq", "hlg", "bt.1886")
    private(set) var transferFunction: String = "bt.1886"

    /// Color primaries from mpv (e.g. "bt.2020", "bt.709", "display-p3")
    private(set) var primaries: String = "bt.709"

    /// Display EDR headroom (1.0 = SDR, >1.0 = HDR-capable)
    private(set) var maxEDR: CGFloat = 1.0

    /// Human-readable HDR format label for UI
    var formatLabel: String {
        guard isHDRContent else { return "SDR" }
        switch transferFunction {
        case "pq": return "HDR10 (PQ)"
        case "hlg": return "HLG"
        default: return "HDR"
        }
    }

    // MARK: - Property Updates (called from mpv event handler)

    /// Update HDR state from mpv property change. Called from event handler on main thread.
    func handlePropertyChange(name: String, value: String?) {
        switch name {
        case "video-params/gamma":
            let gamma = value ?? "bt.1886"
            transferFunction = gamma
            isHDRContent = (gamma == "pq" || gamma == "hlg")

        case "video-params/primaries":
            primaries = value ?? "bt.709"

        default:
            break
        }

        if isHDRContent {
            updateEDRHeadroom()
        }
    }

    /// Reset state when playback stops or new file loads.
    func reset() {
        isHDRContent = false
        transferFunction = "bt.1886"
        primaries = "bt.709"
        maxEDR = 1.0
    }

    // MARK: - Private

    private func updateEDRHeadroom() {
        if let screen = NSScreen.main {
            maxEDR = screen.maximumExtendedDynamicRangeColorComponentValue
        }
    }
}
