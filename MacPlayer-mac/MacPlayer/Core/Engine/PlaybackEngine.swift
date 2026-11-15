import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Central playback engine managing decoder lifecycle and state.
/// Uses @Observable for direct SwiftUI integration (replacing IINA's KVO/NotificationCenter pattern).
@MainActor
@Observable
final class PlaybackEngine {
    // MARK: - Observable State

    private(set) var state: PlayerState = .idle
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var mediaTitle: String = ""
    private(set) var mediaInfo: MediaInfo?
    private(set) var currentURL: URL?
    var volume: Float = 1.0 {
        didSet {
            decoder.volume = volume
            UserDefaults.standard.set(volume, forKey: "MacPlayer.volume")
            osd.show(.volume(effectiveVolume))
        }
    }
    var isMuted: Bool = false {
        didSet {
            decoder.isMuted = isMuted
            UserDefaults.standard.set(isMuted, forKey: "MacPlayer.isMuted")
            osd.show(.muted(isMuted))
        }
    }
    var playbackRate: Float = 1.0 {
        didSet {
            decoder.setPlaybackRate(playbackRate)
            osd.show(.playbackRate(playbackRate))
        }
    }
    private(set) var isSeeking: Bool = false

    /// Flag set when a frame step occurs so display link renders the new frame even while paused
    var needsFrameRefresh: Bool = false

    /// Video rotation in degrees (0, 90, 180, 270), cycles with Cmd+K
    private(set) var videoRotation: Int = 0

    /// Image displayed when viewing a static image file
    private(set) var displayedImage: NSImage?

    // MARK: - Sub-managers

    let osd = OSDManager()
    let windowState = WindowState()
    let playlist = PlaylistManager()
    let bookmarks: BookmarkManager
    let highlights: HighlightManager
    let history: PlaybackHistoryManager
    let filters = FilterManager()
    let hdr = HDRManager()
    let nowPlaying = NowPlayingManager()
    let sleepPreventer = SleepPreventer()
    let abLoop = ABLoopManager()
    let pip = PiPManager()
    let thumbnails = ThumbnailGenerator()
    let tracks = TrackManager()
    let keyBindings: KeyBindingManager

    // MARK: - Private

    private(set) var decoder: MPVDecoder
    let perFileStore: PerFileSettingsStore

    /// Timer for mpv time/subtitle synchronization (mpv doesn't use copyCurrentPixelBuffer path)
    private var mpvTimeUpdateTimer: Timer?

    /// Whether playback has reached the end of the video
    private(set) var isAtEnd = false

    init() {
        self.decoder = MPVDecoder()
        self.keyBindings = KeyBindingManager()

        // Open database before initializing managers that depend on it
        DatabaseManager.shared.setup()
        self.history = PlaybackHistoryManager()
        self.bookmarks = BookmarkManager()
        self.highlights = HighlightManager()
        self.perFileStore = PerFileSettingsStore()
        nowPlaying.setup(engine: self)
        keyBindings.setup(engine: self)
        decoder.hdrManager = hdr
        decoder.trackManager = tracks

        // Restore saved volume/mute
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "MacPlayer.volume") != nil {
            volume = defaults.float(forKey: "MacPlayer.volume")
        }
        isMuted = defaults.bool(forKey: "MacPlayer.isMuted")
        decoder.volume = volume
        decoder.isMuted = isMuted

        // Handle end of playback — auto-advance to next track if available
        setupPlaybackEndHandler()

        // PiP callbacks (videoView is registered later by the NSView)
        pip.onTogglePlayPause = { [weak self] in self?.togglePlayPause() }
        pip.playbackStateProvider = { [weak self] in self?.state == .playing }

        startMPVTimeUpdateTimer()
    }

    private func setupPlaybackEndHandler() {
        decoder.onPlaybackDidEnd = { [weak self] in
            guard let self else { return }

            // If highlights mode is on, loop to first segment
            if self.highlights.isEnabled, let url = self.currentURL {
                let segs = self.highlights.segments(for: url)
                if let first = segs.first {
                    Task { await self.seek(to: first.startTime); self.play() }
                    return
                }
            }

            if self.playlist.hasNext {
                Task { await self.playNext() }
            } else {
                self.isAtEnd = true
                self.state = .paused
                self.sleepPreventer.allowSleep()
                self.nowPlaying.updatePlaybackState(isPlaying: false)
                self.pip.updatePlayingState(false)
            }
        }
    }

    // MARK: - mpv Time Sync Timer

    private func startMPVTimeUpdateTimer() {
        mpvTimeUpdateTimer?.invalidate()
        mpvTimeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .playing else { return }

                self.currentTime = self.decoder.currentTime
                self.duration = self.decoder.duration
                self.nowPlaying.updateNowPlayingInfo(
                    title: self.mediaTitle,
                    currentTime: self.currentTime,
                    duration: self.duration,
                    rate: self.playbackRate
                )

                // Check A-B loop
                if let loopTarget = self.abLoop.shouldLoop(currentTime: self.currentTime) {
                    Task { await self.seek(to: loopTarget) }
                }

                // Check highlights
                if self.highlights.isEnabled, let url = self.currentURL,
                   let target = self.highlights.nextTarget(currentTime: self.currentTime, videoURL: url) {
                    Task { await self.seek(to: target) }
                }
            }
        }
    }

    // MARK: - Playback Control

    func load(url: URL) async {
        // Save settings of previous file
        if let prevURL = currentURL {
            if state.isActive {
                history.recordPosition(
                    videoURL: prevURL, title: mediaTitle,
                    position: currentTime, duration: duration
                )
            }
            savePerFileSettings(for: prevURL)
        }

        state = .loading
        currentURL = url
        mediaTitle = url.deletingPathExtension().lastPathComponent
        mediaInfo = nil
        displayedImage = nil

        // Check if it's an image file
        if let utType = UTType(filenameExtension: url.pathExtension), utType.conforms(to: .image) {
            loadImage(url: url)
            return
        }

        // Reset state before loading — observers will repopulate after file-loaded event
        hdr.reset()
        tracks.reset()

        do {
            try await decoder.load(url: url)
            // Re-apply volume/mute after decoder is loaded
            decoder.volume = volume
            decoder.isMuted = isMuted
            duration = decoder.duration
            playlist.updateCurrentDuration(duration)

            // Setup thumbnail generator — pass duration so pre-generation starts immediately
            thumbnails.setup(url: url, duration: duration)

            // Check for resume position
            if let resumePos = history.resumePosition(for: url), resumePos > 5 {
                state = .paused
                await seek(to: resumePos)
                osd.show(.text("Resumed at \(formatTime(resumePos))"))
            }

            // Clear A-B loop on new media
            abLoop.clearLoop()

            // Reset audio delay before restoring per-file settings
            if decoder.audioDelay != 0 {
                await decoder.applyAudioDelay(0)
            }

            // Restore per-file settings (rotation, filters, audio delay)
            restorePerFileSettings(for: url)

            mediaInfo = decoder.getMediaInfo()
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                mediaInfo?.createdAt = attrs[.creationDate] as? Date
                mediaInfo?.modifiedAt = attrs[.modificationDate] as? Date
            }
            state = .paused
            play()
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Image Viewing

    private func loadImage(url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            state = .error("Failed to load image")
            return
        }
        displayedImage = image
        duration = 0
        currentTime = 0
        state = .viewingImage
    }

    func play() {
        guard state == .paused || state == .stopped else { return }

        // If at the end, restart from beginning
        if isAtEnd {
            isAtEnd = false
            currentTime = 0
            decoder.scrub(to: 0)
            // Wait a moment for the seek to start, then play
            Task {
                await decoder.seek(to: 0)
                decoder.play()
                if playbackRate != 1.0 {
                    decoder.setPlaybackRate(playbackRate)
                }
            }
            state = .playing
            sleepPreventer.preventSleep()
            nowPlaying.updatePlaybackState(isPlaying: true)
            pip.updatePlayingState(true)
            return
        }

        decoder.play()
        if playbackRate != 1.0 {
            decoder.setPlaybackRate(playbackRate)
        }
        state = .playing
        sleepPreventer.preventSleep()
        nowPlaying.updatePlaybackState(isPlaying: true)
        pip.updatePlayingState(true)
    }

    func pause() {
        guard state == .playing else { return }
        decoder.pause()
        state = .paused
        sleepPreventer.allowSleep()
        nowPlaying.updatePlaybackState(isPlaying: false)
        pip.updatePlayingState(false)
    }

    func togglePlayPause() {
        switch state {
        case .playing:
            pause()
            osd.show(.paused)
        case .paused:
            play()
            osd.show(.playing, duration: 0.8)
        default: break
        }
    }

    func stop() {
        if let url = currentURL {
            history.recordPosition(
                videoURL: url, title: mediaTitle,
                position: currentTime, duration: duration
            )
            savePerFileSettings(for: url)
        }
        decoder.stop()
        state = .stopped
        currentTime = 0
        sleepPreventer.allowSleep()
        nowPlaying.clearNowPlayingInfo()
        nowPlaying.updatePlaybackState(isPlaying: false)
        pip.teardown()
    }

    // MARK: - Seeking

    func seek(to time: Double) async {
        guard state.isActive else { return }
        isAtEnd = false
        isSeeking = true
        currentTime = time
        await decoder.seek(to: time)
        isSeeking = false
        needsFrameRefresh = true
    }

    func seekRelative(by delta: Double) async {
        guard state.isActive else { return }
        isAtEnd = false
        decoder.seekRelativeFast(by: delta)
        currentTime = decoder.currentTime
        osd.show(.seek(currentTime, duration))
    }

    /// Whether playback was active before a scrub drag began (to resume after)
    private var wasPlayingBeforeScrub = false

    /// Called when drag begins — pauses playback so video doesn't advance during scrub.
    func scrubBegan() {
        guard state.isActive else { return }
        wasPlayingBeforeScrub = (state == .playing)
        if wasPlayingBeforeScrub {
            decoder.pause()
        }
    }

    /// Lightweight scrub for real-time drag preview — non-blocking, shows frame instantly.
    func scrub(to time: Double) {
        guard state.isActive else { return }
        currentTime = time
        decoder.scrub(to: time)
        needsFrameRefresh = true
    }

    /// Called when drag ends — does precise seek then resumes playback if needed.
    func scrubEnded(at time: Double) {
        guard state.isActive else { return }
        Task {
            await seek(to: time)
            if wasPlayingBeforeScrub {
                decoder.play()
                if playbackRate != 1.0 {
                    decoder.setPlaybackRate(playbackRate)
                }
            }
            wasPlayingBeforeScrub = false
        }
    }

    // MARK: - Frame Stepping

    func stepForward() {
        if state == .playing {
            pause()
        } else if state != .paused {
            return
        }
        decoder.stepForward()
        needsFrameRefresh = true
        osd.show(.text("Frame \u{2192}"))
    }

    func stepBackward() {
        if state == .playing {
            pause()
        } else if state != .paused {
            return
        }
        decoder.stepBackward()
        needsFrameRefresh = true
        osd.show(.text("\u{2190} Frame"))
    }

    // MARK: - Audio Delay

    /// Current audio delay in seconds
    var audioDelay: Double { decoder.audioDelay }

    func setAudioDelay(_ delay: Double) {
        let clamped = max(-5, min(delay, 5))
        Task { await decoder.applyAudioDelay(clamped) }
        if clamped != 0 {
            let sign = clamped > 0 ? "+" : ""
            osd.show(.text("Audio delay: \(sign)\(String(format: "%.2f", clamped))s"))
        }
    }

    func adjustAudioDelay(by delta: Double) {
        setAudioDelay(decoder.audioDelay + delta)
    }

    func resetAudioDelay() {
        setAudioDelay(0)
        osd.show(.text("Audio delay: 0.0s"))
    }

    // MARK: - Track Selection

    func cycleSubtitleTrack() {
        let subs = tracks.subtitleTracks
        guard !subs.isEmpty else {
            osd.show(.text("No subtitle tracks"))
            return
        }

        let currentID = tracks.currentSubtitleID
        // Build cycle: each track ID, then 0 (off)
        let ids = subs.map(\.id) + [0]
        let currentIndex = ids.firstIndex(of: currentID) ?? ids.count - 1
        let nextID = ids[(currentIndex + 1) % ids.count]

        if nextID == 0 {
            decoder.setMPVString("sid", "no")
            tracks.updateCurrentSubtitleID(0)
        } else {
            decoder.setMPVInt64("sid", Int64(nextID))
        }

        if nextID == 0 {
            osd.show(.text("Subtitle: Off"))
        } else if let track = subs.first(where: { $0.id == nextID }) {
            let idx = subs.firstIndex(where: { $0.id == nextID }).map { $0 + 1 } ?? 0
            osd.show(.text("Subtitle: \(track.displayLabel) (\(idx)/\(subs.count))"))
        }
    }

    func cycleAudioTrack() {
        let audios = tracks.audioTracks
        guard audios.count > 1 else {
            osd.show(.text("No other audio tracks"))
            return
        }

        let currentID = tracks.currentAudioID
        let ids = audios.map(\.id)
        let currentIndex = ids.firstIndex(of: currentID) ?? 0
        let nextID = ids[(currentIndex + 1) % ids.count]

        decoder.setMPVInt64("aid", Int64(nextID))

        if let track = audios.first(where: { $0.id == nextID }) {
            let idx = audios.firstIndex(where: { $0.id == nextID }).map { $0 + 1 } ?? 0
            osd.show(.text("Audio: \(track.displayLabel) (\(idx)/\(audios.count))"))
        }
    }

    func addExternalSubtitle(url: URL) {
        decoder.addSubtitle(path: url.path)
        osd.show(.text("Subtitle loaded: \(url.lastPathComponent)"))
    }

    func removeSubtitle(id: Int) {
        decoder.removeSubtitle(id: id)
    }

    func setSubtitleTrack(id: Int) {
        if id == 0 {
            decoder.setMPVString("sid", "no")
            tracks.updateCurrentSubtitleID(0)
        } else {
            decoder.setMPVInt64("sid", Int64(id))
        }
    }

    func setAudioTrack(id: Int) {
        decoder.setMPVInt64("aid", Int64(id))
    }

    // MARK: - Volume

    func adjustVolume(by delta: Float) {
        volume = max(0, min(volume + delta, 1.0))
    }

    func toggleMute() {
        isMuted.toggle()
    }

    // MARK: - Rate

    func cyclePlaybackRate() {
        let rates: [Float] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0]
        guard let currentIndex = rates.firstIndex(of: playbackRate) else {
            playbackRate = 1.0
            return
        }
        let nextIndex = (currentIndex + 1) % rates.count
        playbackRate = rates[nextIndex]
    }

    // MARK: - Playlist Navigation

    func playNext() async {
        guard let url = playlist.next() else { return }
        await load(url: url)
    }

    func playPrevious() async {
        guard let url = playlist.previous() else { return }
        await load(url: url)
    }

    // MARK: - Bookmarks

    func addBookmark(name: String? = nil) {
        guard let url = currentURL else { return }
        let bookmarkName = name ?? ""

        // Duplicate check + insert — no heavy work
        guard let bookmarkID = bookmarks.addBookmark(videoURL: url, time: currentTime, name: bookmarkName) else {
            osd.show(.text("Bookmark already exists"))
            return
        }
        osd.show(.text("Bookmark added"))

        // Capture thumbnail async — screenshot on main actor, resize off main thread
        Task { [weak self] in
            guard let self else { return }
            let tempPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("macplayer_bm_\(UUID().uuidString).jpg").path
            guard self.decoder.takeScreenshot(to: tempPath) else { return }

            // File I/O + resize off main thread (CoreGraphics is thread-safe)
            let data = await Task.detached { () -> Data? in
                defer { try? FileManager.default.removeItem(atPath: tempPath) }
                guard let source = CGImageSourceCreateWithURL(
                    URL(fileURLWithPath: tempPath) as CFURL, nil
                ), let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
                else { return nil }

                let srcW = CGFloat(cgImage.width), srcH = CGFloat(cgImage.height)
                let w = min(srcW, 160), h = w * srcH / srcW
                guard let ctx = CGContext(
                    data: nil, width: Int(w), height: Int(h),
                    bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return nil }
                ctx.interpolationQuality = .low
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
                guard let resized = ctx.makeImage() else { return nil }

                let jpegData = NSMutableData()
                guard let dest = CGImageDestinationCreateWithData(
                    jpegData, "public.jpeg" as CFString, 1, nil
                ) else { return nil }
                CGImageDestinationAddImage(dest, resized, [
                    kCGImageDestinationLossyCompressionQuality: 0.5
                ] as CFDictionary)
                guard CGImageDestinationFinalize(dest) else { return nil }
                return jpegData as Data
            }.value

            if let data {
                self.bookmarks.updateThumbnail(for: bookmarkID, data: data)
            }
        }
    }

    // MARK: - Bookmark Navigation

    func seekToNextBookmark() async {
        guard let url = currentURL else { return }
        let marks = bookmarks.bookmarks(for: url)
        if let next = marks.first(where: { $0.time > currentTime + 0.5 }) {
            await seek(to: next.time)
            osd.show(.text("\u{25B8} \(next.name)"))
        }
    }

    func seekToPreviousBookmark() async {
        guard let url = currentURL else { return }
        let marks = bookmarks.bookmarks(for: url)
        if let prev = marks.last(where: { $0.time < currentTime - 0.5 }) {
            await seek(to: prev.time)
            osd.show(.text("\u{25C2} \(prev.name)"))
        }
    }

    // MARK: - A-B Loop

    func setLoopPointA() {
        abLoop.setPointA(currentTime)
        osd.show(.text("Loop A: \(formatTime(currentTime))  — \\ to clear"))
    }

    func setLoopPointB() {
        abLoop.setPointB(currentTime)
        if abLoop.isActive {
            osd.show(.text("Loop A-B active  — \\ to clear"))
        }
    }

    func clearABLoop() {
        abLoop.clearLoop()
        osd.show(.text("Loop cleared"))
    }

    // MARK: - Highlights

    func toggleHighlights() {
        guard let url = currentURL else { return }
        let segs = highlights.segments(for: url)
        if segs.isEmpty {
            osd.show(.text("No highlights to play"))
            return
        }
        highlights.isEnabled.toggle()
        if highlights.isEnabled {
            osd.show(.text("Highlights ON (\(segs.count) segments)"))
            // Jump to first segment if outside any segment
            if let target = highlights.nextTarget(currentTime: currentTime, videoURL: url) {
                Task { await seek(to: target) }
            }
        } else {
            osd.show(.text("Highlights OFF"))
        }
    }

    func markHighlightStart() {
        highlights.pendingStart = currentTime
        osd.show(.text("Highlight start: \(formatTime(currentTime))"))
    }

    func markHighlightEnd() {
        guard let url = currentURL else { return }
        guard let start = highlights.pendingStart else {
            osd.show(.text("Set highlight start first (Shift+H)"))
            return
        }
        guard currentTime > start else {
            osd.show(.text("End must be after start"))
            return
        }
        if highlights.addSegment(videoURL: url, startTime: start, endTime: currentTime) != nil {
            osd.show(.text("Highlight added: \(formatTime(start)) - \(formatTime(currentTime))"))
        } else {
            osd.show(.text("Duplicate highlight"))
        }
        highlights.pendingStart = nil
    }

    // MARK: - PiP

    func togglePiP() {
        pip.togglePiP()
    }

    // MARK: - Open File

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .movie, .video, .mpeg4Movie, .quickTimeMovie, .avi,
            .image, .png, .jpeg, .gif, .tiff, .heic, .bmp, .webP
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true

        guard panel.runModal() == .OK else { return }

        let urls = panel.urls
        Task {
            await open(urls: urls)
        }
    }

    /// Opens a selection of files or folders: one item plays directly, several become a playlist.
    func open(urls: [URL]) async {
        if urls.count == 1, let url = urls.first {
            await open(url)
        } else if urls.count > 1 {
            await openAsPlaylist(urls)
        }
    }

    /// Opens one file, or a folder as a playlist starting at its first item.
    func open(_ url: URL) async {
        if PlaylistManager.isDirectory(url) {
            playlist.replace(folder: url)
            if let firstURL = playlist.play(at: 0) {
                await load(url: firstURL)
            }
        } else {
            await load(url: url)
        }
    }

    /// Replaces the playlist with the given items (folders are expanded) and plays the first one.
    func openAsPlaylist(_ urls: [URL]) async {
        var allURLs: [URL] = []
        for url in urls {
            if PlaylistManager.isDirectory(url) {
                let temp = PlaylistManager()
                temp.add(folder: url)
                allURLs.append(contentsOf: temp.items.map(\.url))
            } else {
                allURLs.append(url)
            }
        }
        guard !allURLs.isEmpty else { return }

        playlist.replace(urls: allURLs)
        if let firstURL = playlist.play(at: 0) {
            await load(url: firstURL)
        }
    }

    // MARK: - Rotation

    func rotateVideo() {
        rotateBy(90)
    }

    func rotateBy(_ degrees: Int) {
        setRotation((videoRotation + degrees + 360) % 360)
    }

    func setRotation(_ degrees: Int) {
        videoRotation = degrees % 360
        decoder.setMPVInt64("video-rotate", Int64(videoRotation))
        needsFrameRefresh = true
        osd.show(.text("Rotation: \(videoRotation)°"))
    }

    var videoRotationRadians: Float {
        Float(videoRotation) * .pi / 180
    }

    // MARK: - Screenshot

    func takeScreenshot() {
        let dir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MacPlayer Screenshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let path = dir.appendingPathComponent("MacPlayer_\(timestamp).png").path

        if decoder.takeScreenshot(to: path) {
            osd.show(.text("Screenshot saved"))
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else {
            osd.show(.text("Screenshot failed"))
        }
    }

    // MARK: - mpv Filter Sync

    /// Push current filter values to mpv backend.
    func syncFiltersToMPV() {
        for filter in filters.filters {
            let value = filter.isEnabled ? filter.parameters[0].value : filter.parameters[0].defaultValue
            switch filter.id {
            case "brightness":
                // mpv brightness: -100..100 (our range -1..1)
                decoder.setMPVProperty("brightness", Double(value * 100))
            case "contrast":
                // mpv contrast: -100..100 (our range 0..3, default 1)
                decoder.setMPVProperty("contrast", Double((value - 1) * 100))
            case "saturation":
                // mpv saturation: -100..100 (our range 0..3, default 1)
                decoder.setMPVProperty("saturation", Double((value - 1) * 100))
            case "sharpen":
                // mpv unsharp sigma (0 = off)
                decoder.setMPVString("vf", value > 0 ? "unsharp=la=\(value)" : "")
            case "deband":
                decoder.setMPVFlag("deband", filter.isEnabled)
                if filter.isEnabled {
                    decoder.setMPVInt64("deband-threshold", Int64(value))
                }
            default:
                break
            }
        }
    }

    // MARK: - Per-File Settings

    /// Reset all adjustments (filters, rotation, audio sync) to defaults.
    func resetAllAdjustments() {
        filters.resetAll()
        syncFiltersToMPV()
        needsFrameRefresh = true
        setRotation(0)
        setAudioDelay(0)
    }

    private func savePerFileSettings(for url: URL) {
        var settings = PerFileSettings()
        settings.rotation = videoRotation
        settings.audioDelay = decoder.audioDelay
        settings.filters = filters.filters.map { filter in
            PerFileSettings.FilterState(
                id: filter.id,
                isEnabled: filter.isEnabled,
                parameters: Dictionary(uniqueKeysWithValues: filter.parameters.map { ($0.id, $0.value) })
            )
        }
        perFileStore.save(settings, for: url)
    }

    private func restorePerFileSettings(for url: URL) {
        let settings = perFileStore.settings(for: url)

        // Restore rotation
        setRotation(settings.rotation)

        // Restore audio delay
        if settings.audioDelay != 0 {
            Task { await decoder.applyAudioDelay(settings.audioDelay) }
        }

        // Restore filters
        if settings.filters.isEmpty {
            filters.resetAll()
        } else {
            for saved in settings.filters {
                if let idx = filters.filters.firstIndex(where: { $0.id == saved.id }) {
                    filters.filters[idx].isEnabled = saved.isEnabled
                    for (paramID, value) in saved.parameters {
                        if let pIdx = filters.filters[idx].parameters.firstIndex(where: { $0.id == paramID }) {
                            filters.filters[idx].parameters[pIdx].value = value
                        }
                    }
                }
            }
        }
        syncFiltersToMPV()
    }

    // MARK: - Computed

    var progress: Double {
        guard duration > 0 else { return 0 }
        if isAtEnd { return 1.0 }
        return min(currentTime / duration, 1.0)
    }

    var effectiveVolume: Float {
        isMuted ? 0 : volume
    }
}
