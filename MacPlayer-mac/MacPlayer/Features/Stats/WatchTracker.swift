import Foundation

/// Records which parts of the loaded media get played, and keeps the graph of it up to date.
///
/// The engine reports the playback position on every tick of its timer. What the position
/// advances by between two reports, at the pace playback runs at, was watched and is added to
/// the media's watch-time series. A position that moves any other way was a seek and adds
/// nothing. So only what actually played counts, once per pass whatever the playback rate.
///
/// The series lives in memory while the media is loaded. It is written back whenever playback
/// stops, and once a minute while it runs, so that a crash loses little. A tick costs a few
/// comparisons and an addition.
@MainActor
@Observable
final class WatchTracker {
    /// How the loaded media has been watched so far. `nil` with nothing loaded, or nothing
    /// watched yet.
    private(set) var heatmap: WatchHeatmap?

    /// Seconds between two redraws of the graph while playback runs.
    private static let refreshInterval: TimeInterval = 5
    /// Seconds between two writes to the database while playback runs.
    private static let saveInterval: TimeInterval = 60
    /// Seconds the position may be ahead of the clock: it moves a frame at a time, and a
    /// tick can come late.
    private static let timingSlack: TimeInterval = 0.15
    /// How far beyond the playback rate the position may advance and still count as playing.
    private static let rateTolerance = 1.5

    @ObservationIgnored private let store = TimelineStatsStore()
    @ObservationIgnored private var mediaID: String?
    @ObservationIgnored private var series = TimelineSeries()
    @ObservationIgnored private var duration: Double = 0

    /// Position last reported while playing, and the uptime at which playback got there.
    /// `nil` while playback is not running.
    @ObservationIgnored private var anchor: (position: Double, time: TimeInterval)?

    @ObservationIgnored private var hasUnsavedData = false
    @ObservationIgnored private var isHeatmapStale = false
    @ObservationIgnored private var lastSaveTime: TimeInterval = 0
    @ObservationIgnored private var lastRefreshTime: TimeInterval = 0

    // MARK: - Lifecycle

    /// Starts recording a media, picking up what was recorded for it before.
    func begin(mediaID: String, duration: Double) {
        end()

        let now = ProcessInfo.processInfo.systemUptime
        self.mediaID = mediaID
        self.duration = duration
        series = store.series(for: mediaID, metric: .watchTime) ?? TimelineSeries()
        series.fit(duration: duration)
        lastSaveTime = now
        refreshHeatmap(at: now)
    }

    /// Stops recording: what was gathered is saved and the graph goes away.
    func end() {
        persist(at: ProcessInfo.processInfo.systemUptime)
        mediaID = nil
        series = TimelineSeries()
        duration = 0
        anchor = nil
        hasUnsavedData = false
        isHeatmapStale = false
        if heatmap != nil {
            heatmap = nil
        }
    }

    // MARK: - Recording

    /// Takes in the current playback position. Called on every tick while a media is loaded.
    ///
    /// `isPlaying` is whether playback is running on its own: not paused, and not being
    /// scrubbed. `rate` is the playback rate, 1 being normal speed.
    func sample(
        position: Double,
        duration: Double,
        rate: Double,
        isPlaying: Bool,
        at now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        guard mediaID != nil else { return }

        guard isPlaying else {
            // Playback just stopped: show what it added while the seek bar is likely looked at.
            if anchor != nil {
                anchor = nil
                refreshHeatmapIfStale(at: now)
            }
            return
        }

        if duration != self.duration {
            self.duration = duration
            series.fit(duration: duration)
            isHeatmapStale = true
        }

        guard let last = anchor else {
            anchor = (position, now)
            return
        }

        // The position moves a frame at a time, less often than the ticks come. The clock
        // keeps running from when the position last changed, so the two can be compared.
        let advance = position - last.position
        guard advance != 0 else { return }
        anchor = (position, now)

        // Playback moves the position forward about as fast as the clock, times the rate.
        // Backwards, or further than that, was a seek.
        let playable = (now - last.time + Self.timingSlack) * max(rate, 1) * Self.rateTolerance
        guard advance > 0, advance <= playable else { return }

        series.add(from: last.position, to: position)
        hasUnsavedData = true
        isHeatmapStale = true

        if now - lastRefreshTime >= Self.refreshInterval {
            refreshHeatmap(at: now)
        }
        if now - lastSaveTime >= Self.saveInterval {
            persist(at: now)
        }
    }

    /// Saves what was gathered and brings the graph up to date. Called whenever playback
    /// stops: on pause, at the end of the file, and when the app quits.
    func save() {
        let now = ProcessInfo.processInfo.systemUptime
        refreshHeatmapIfStale(at: now)
        persist(at: now)
    }

    /// Writes the series to the database, unless nothing was added since it was last written.
    private func persist(at now: TimeInterval) {
        guard hasUnsavedData, let mediaID else { return }
        if store.save(series, for: mediaID, metric: .watchTime) {
            hasUnsavedData = false
        }
        // Counts as an attempt even when it failed: the next one waits for the interval too.
        lastSaveTime = now
    }

    // MARK: - Graph

    private func refreshHeatmapIfStale(at now: TimeInterval) {
        if isHeatmapStale {
            refreshHeatmap(at: now)
        }
    }

    /// Derives the graph from the series again. The result is kept until the series changes,
    /// so drawing never works on the series itself.
    private func refreshHeatmap(at now: TimeInterval) {
        isHeatmapStale = false
        lastRefreshTime = now

        let updated = WatchHeatmap(watchTime: series, duration: duration)
        // An assignment notifies every view that reads the graph, even when nothing changed.
        if updated != heatmap {
            heatmap = updated
        }
    }
}
