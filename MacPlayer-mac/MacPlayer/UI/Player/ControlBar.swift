import SwiftUI

/// Bottom control bar overlay with play/pause, seek bar, volume, and time display.
struct ControlBar: View {
    let engine: PlaybackEngine
    @Binding var sidebarTab: SidebarTab?

    @AppStorage(AppSettings.controlBarOpacity.key) private var barOpacity = AppSettings.controlBarOpacity.defaultValue
    @AppStorage(AppSettings.showWatchHeatmap.key) private var showWatchHeatmap = AppSettings.showWatchHeatmap.defaultValue

    var body: some View {
        VStack(spacing: 8) {
            // Seek bar with A-B loop markers, watch heatmap and thumbnail preview
            SeekBar(
                progress: engine.progress,
                duration: engine.duration,
                onSeek: { time in
                    engine.scrubEnded(at: time)
                },
                onScrubBegan: {
                    engine.scrubBegan()
                },
                onScrub: { time in
                    engine.scrub(to: time)
                },
                loopA: engine.abLoop.pointA,
                loopB: engine.abLoop.pointB,
                bookmarkTimes: currentBookmarkTimes,
                highlightSegments: currentHighlightSegments,
                watchHeatmap: showWatchHeatmap ? engine.watchStats.heatmap : nil,
                thumbnailGenerator: engine.thumbnails
            )

            // Controls row
            HStack(spacing: 12) {
                // Play/Pause button
                Button(action: { engine.togglePlayPause() }) {
                    Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(PlayerControlButtonStyle())
                .accessibilityLabel(engine.state == .playing ? "Pause" : "Play")

                // Time label
                TimeLabel(
                    currentTime: engine.currentTime,
                    duration: engine.duration
                )

                Spacer()

                // Playback rate indicator (only show when not 1.0x)
                if engine.playbackRate != 1.0 {
                    Button(action: { engine.cyclePlaybackRate() }) {
                        Text("\(String(format: "%.2g", engine.playbackRate))x")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(PlayerControlButtonStyle())
                    .accessibilityLabel("Playback rate \(String(format: "%.2g", engine.playbackRate))x")
                }

                // Filter active indicator — only visible when adjustments are active
                if hasActiveAdjustments {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            sidebarTab = sidebarTab == .filters ? nil : .filters
                        }
                    }) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.blue)
                            .frame(width: 24, height: 24)
                            .overlay(alignment: .topTrailing) {
                                Circle()
                                    .fill(.blue)
                                    .frame(width: 5, height: 5)
                                    .offset(x: 1, y: 1)
                            }
                    }
                    .buttonStyle(PlayerControlButtonStyle())
                    .accessibilityLabel("Adjustments active")
                }

                // Bookmark indicator — only visible when current video has bookmarks
                if !currentBookmarkTimes.isEmpty {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            sidebarTab = sidebarTab == .bookmarks ? nil : .bookmarks
                        }
                    }) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(PlayerControlButtonStyle())
                    .accessibilityLabel("Bookmarks")
                }

                // Highlight mode indicator
                if engine.highlights.isEnabled || !currentHighlightSegments.isEmpty {
                    Button(action: {
                        engine.toggleHighlights()
                    }) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(engine.highlights.isEnabled ? .yellow : .white.opacity(0.6))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(PlayerControlButtonStyle())
                    .accessibilityLabel("Highlights")
                }

                // Subtitle/Audio track indicator — visible when tracks are available
                if !engine.tracks.subtitleTracks.isEmpty || engine.tracks.audioTracks.count > 1 {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            sidebarTab = sidebarTab == .tracks ? nil : .tracks
                        }
                    }) {
                        Image(systemName: "captions.bubble")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(engine.tracks.currentSubtitleID != 0 ? .blue : .white.opacity(0.6))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(PlayerControlButtonStyle())
                    .accessibilityLabel("Track selection")
                }

                // Playlist indicator — only visible when there is more to play than this one file
                if engine.playlist.currentIndex != nil && engine.playlist.items.count > 1 {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            sidebarTab = sidebarTab == .playlist ? nil : .playlist
                        }
                    }) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.blue)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(PlayerControlButtonStyle())
                    .accessibilityLabel("Playlist active")
                }

                // Volume control
                VolumeSlider(
                    volume: Bindable(engine).volume,
                    isMuted: Bindable(engine).isMuted
                )

                // PiP toggle
                if engine.pip.isPossible {
                    Button(action: { engine.togglePiP() }) {
                        Image(systemName: engine.pip.isActive ? "pip.fill" : "pip")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(engine.pip.isActive ? Color.accentColor : .white)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(PlayerControlButtonStyle())
                    .accessibilityLabel("PiP")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(barOpacity * 0.75), .black.opacity(barOpacity)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var currentBookmarkTimes: [Double] {
        guard let mediaID = engine.currentMediaID else { return [] }
        return engine.bookmarks.bookmarks(for: mediaID).map(\.time)
    }

    private var currentHighlightSegments: [(start: Double, end: Double)] {
        guard let mediaID = engine.currentMediaID else { return [] }
        return engine.highlights.segments(for: mediaID).map { (start: $0.startTime, end: $0.endTime) }
    }

    private var hasActiveAdjustments: Bool {
        engine.filters.hasActiveFilters
            || engine.videoRotation != 0
            || engine.audioDelay != 0
    }
}

// MARK: - Player Control Button Style

/// Custom button style for player controls with hover and press feedback.
/// Provides comfortable hit area without increasing layout height.
struct PlayerControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PlayerControlButtonBody(configuration: configuration)
    }
}

private struct PlayerControlButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(.white.opacity(isHovered && !configuration.isPressed ? 0.08 : 0))
            )
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
    }
}
