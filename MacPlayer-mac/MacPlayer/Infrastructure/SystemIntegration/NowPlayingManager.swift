import Foundation
import MediaPlayer

/// Integrates with macOS Now Playing (Control Center) and media key commands.
@MainActor
final class NowPlayingManager {
    private var commandCenter: MPRemoteCommandCenter?

    weak var engine: PlaybackEngine?

    func setup(engine: PlaybackEngine) {
        self.engine = engine
        setupNowPlaying()
        setupRemoteCommands()
    }

    /// Update Now Playing info center with current playback state.
    func updateNowPlayingInfo(title: String, currentTime: Double, duration: Double, rate: Float) {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = title
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Private

    private func setupNowPlaying() {
        MPNowPlayingInfoCenter.default().playbackState = .paused
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        self.commandCenter = center

        center.playCommand.addTarget { [weak self] _ in
            self?.engine?.play()
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            self?.engine?.pause()
            return .success
        }

        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.engine?.togglePlayPause()
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in
                await self?.engine?.seek(to: posEvent.positionTime)
            }
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.engine?.playNext()
            }
            return .success
        }

        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.engine?.playPrevious()
            }
            return .success
        }
    }

    func updatePlaybackState(isPlaying: Bool) {
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }
}
