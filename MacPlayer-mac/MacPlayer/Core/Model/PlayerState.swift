import Foundation

/// Finite state machine for playback lifecycle
enum PlayerState: Sendable, Equatable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case viewingImage
    case error(String)

    var isActive: Bool {
        switch self {
        case .playing, .paused: return true
        default: return false
        }
    }

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .loading: return "Loading..."
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .stopped: return "Stopped"
        case .viewingImage: return "Image"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

/// OSD message types displayed as temporary overlays
enum OSDMessage: Equatable {
    case volume(Float)
    case seek(Double, Double)
    case playbackRate(Float)
    case paused
    case playing
    case muted(Bool)
    case text(String)

    var icon: String {
        switch self {
        case .volume(let v): return v == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .seek: return "arrow.right"
        case .playbackRate: return "gauge.with.needle"
        case .paused: return "pause.fill"
        case .playing: return "play.fill"
        case .muted(let m): return m ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .text: return "info.circle"
        }
    }

    var text: String {
        switch self {
        case .volume(let v): return "Volume: \(Int(v * 100))%"
        case .seek(let t, let d): return "\(formatTime(t)) / \(formatTime(d))"
        case .playbackRate(let r): return "\(String(format: "%.2g", r))x"
        case .paused: return "Paused"
        case .playing: return "Playing"
        case .muted(let m): return m ? "Muted" : "Unmuted"
        case .text(let s): return s
        }
    }
}
