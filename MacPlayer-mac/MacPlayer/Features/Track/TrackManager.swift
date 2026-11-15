import Foundation

/// Represents a single media track (audio, subtitle, or video) from mpv's track-list.
struct MediaTrack: Identifiable, Equatable {
    let id: Int           // mpv track ID
    let type: TrackType
    let title: String?
    let lang: String?
    let codec: String?
    let isDefault: Bool
    let isExternal: Bool

    enum TrackType: String, Equatable {
        case audio
        case sub
        case video
    }

    /// Human-readable label for UI display.
    var displayLabel: String {
        var parts: [String] = []
        if let title { parts.append(title) }
        if let lang { parts.append(lang.uppercased()) }
        if parts.isEmpty, let codec { parts.append(codec) }
        if parts.isEmpty { parts.append("Track \(id)") }
        return parts.joined(separator: " — ")
    }
}

/// Manages audio and subtitle track lists and selection state.
/// Updated by MPVDecoder when track-list or sid/aid properties change.
@MainActor
@Observable
final class TrackManager {
    private(set) var audioTracks: [MediaTrack] = []
    private(set) var subtitleTracks: [MediaTrack] = []
    private(set) var currentAudioID: Int = 0
    private(set) var currentSubtitleID: Int = 0  // 0 = no subtitle

    var currentAudioTrack: MediaTrack? {
        audioTracks.first { $0.id == currentAudioID }
    }

    var currentSubtitleTrack: MediaTrack? {
        subtitleTracks.first { $0.id == currentSubtitleID }
    }

    /// Replace all tracks from mpv track-list data.
    func updateTracks(_ tracks: [MediaTrack]) {
        audioTracks = tracks.filter { $0.type == .audio }
        subtitleTracks = tracks.filter { $0.type == .sub }
    }

    func updateCurrentAudioID(_ id: Int) {
        currentAudioID = id
    }

    func updateCurrentSubtitleID(_ id: Int) {
        currentSubtitleID = id
    }

    func reset() {
        audioTracks = []
        subtitleTracks = []
        currentAudioID = 0
        currentSubtitleID = 0
    }
}
