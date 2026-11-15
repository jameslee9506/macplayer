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
    /// Identity of the loaded file's content: what its resume position, bookmarks, highlights
    /// and per-file settings are stored under. `nil` until the file has been identified.
    private(set) var currentMediaID: String?
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
    private let media = MediaIdentityStore()

    /// Timer for mpv time/subtitle synchronization (mpv doesn't use copyCurrentPixelBuffer path)
    private var mpvTimeUpdateTimer: Timer?

    /// Whether playback has reached the end of the video
    private(set) var isAtEnd = false

    /// Security-scoped URL of a file reopened from the history. Sandbox access to it is held
    /// for as long as that file stays loaded.
    private var scopedAccessURL: URL?

    /// Bumped by every load(); a load that finds it changed after suspending was superseded.
    private var loadGeneration = 0

    /// Whether the seek bar is being dragged. The drag owns `currentTime` until it ends.
    private var isScrubbing = false

    init() {
        self.decoder = MPVDecoder()
        self.keyBindings = KeyBindingManager()

        // Open database before initializing managers that depend on it
        DatabaseManager.shared.setup()
        self.history = PlaybackHistoryManager(media: media)
        self.bookmarks = BookmarkManager()
        self.highlights = HighlightManager()
        self.perFileStore = PerFileSettingsStore()
        nowPlaying.setup(engine: self)
        keyBindings.setup(engine: self)
        decoder.hdrManager = hdr
        decoder.trackManager = tracks

        // Start at the default volume when asked to, otherwise where the last session left it
        let defaults = UserDefaults.standard
        if AppSettings.startAtDefaultVolume.value {
            volume = Float(AppSettings.defaultVolume.value)
        } else if defaults.object(forKey: "MacPlayer.volume") != nil {
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
            if self.highlights.isEnabled, let mediaID = self.currentMediaID {
                let segs = self.highlights.segments(for: mediaID)
                if let first = segs.first {
                    Task { await self.seek(to: first.startTime); self.play() }
                    return
                }
            }

            if self.playlist.hasNext {
                // A playlist plays through: the next item starts whatever "auto-play" says.
                Task { await self.playNext(autoPlay: true) }
            } else {
                self.isAtEnd = true
                self.state = .paused
                self.playbackStateDidChange()
                // Played to the end: the file starts over next time instead of resuming.
                self.savePlaybackState()
            }
        }
    }

    // MARK: - mpv Time Sync Timer

    private func startMPVTimeUpdateTimer() {
        mpvTimeUpdateTimer?.invalidate()
        mpvTimeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state.isActive else { return }

                // Follow mpv while paused as well: a frame step or a keyframe seek moves the
                // position without playback running. Assign only on change, so a player that
                // sits paused invalidates nothing.
                if !self.isSeeking, !self.isScrubbing, self.currentTime != self.decoder.currentTime {
                    self.currentTime = self.decoder.currentTime
                }
                if self.duration != self.decoder.duration {
                    self.duration = self.decoder.duration
                }

                guard self.state == .playing else { return }

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
                if self.highlights.isEnabled, let mediaID = self.currentMediaID,
                   let target = self.highlights.nextTarget(currentTime: self.currentTime, mediaID: mediaID) {
                    Task { await self.seek(to: target) }
                }
            }
        }
    }

    // MARK: - Playback Control

    /// Loads a file and, when `autoPlay` is set, starts it. Left out, `autoPlay` follows Settings.
    /// `expectedMediaID` is the media a recent file is reopened as: see `MediaIdentityStore.identify`.
    func load(
        url: URL,
        autoPlay: Bool = AppSettings.autoPlayOnOpen.value,
        expecting expectedMediaID: String? = nil
    ) async {
        savePlaybackState()

        // Sandbox access held for a file reopened from the history ends once another file replaces it.
        if scopedAccessURL?.path != url.path {
            holdScopedAccess(nil)
        }

        loadGeneration += 1
        let generation = loadGeneration

        state = .loading
        currentURL = url
        currentMediaID = nil
        currentTime = 0
        isAtEnd = false
        mediaTitle = url.deletingPathExtension().lastPathComponent
        mediaInfo = nil
        displayedImage = nil
        // The previous file's thumbnails go with it, whether or not this one turns out to load.
        thumbnails.reset()

        // Work out which media the file is while it loads: everything stored for it is keyed by that.
        async let identification = media.identify(url, expecting: expectedMediaID)

        // Check if it's an image file
        if let utType = UTType(filenameExtension: url.pathExtension), utType.conforms(to: .image) {
            let isShown = loadImage(url: url)
            let identity = await identification
            guard generation == loadGeneration else { return }
            adopt(identity)
            if isShown {
                history.recordOpened(mediaID: identity.id, url: url, title: mediaTitle)
            }
            return
        }

        // Reset state before loading — observers will repopulate after file-loaded event
        hdr.reset()
        tracks.reset()

        // Without auto-play, hold mpv paused from the start so nothing plays before the first frame.
        if !autoPlay {
            decoder.pause()
        }

        do {
            try await decoder.load(url: url)
            let identity = await identification
            // A newer load() took over while this one was waiting; the player is its to set up.
            guard generation == loadGeneration else { return }

            adopt(identity)
            history.recordOpened(mediaID: identity.id, url: url, title: mediaTitle)
            // Re-apply volume/mute after decoder is loaded
            decoder.volume = volume
            decoder.isMuted = isMuted
            currentTime = decoder.currentTime
            duration = decoder.duration
            playlist.updateCurrentDuration(duration)

            // Setup thumbnail generator — pass duration so pre-generation starts immediately
            thumbnails.setup(url: url, duration: duration)

            // Check for resume position
            if AppSettings.resumePlayback.value,
               let resumePos = history.resumePosition(for: identity.id), resumePos > 5 {
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
            restorePerFileSettings(for: identity.id)

            mediaInfo = decoder.getMediaInfo()
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                mediaInfo?.createdAt = attrs[.creationDate] as? Date
                mediaInfo?.modifiedAt = attrs[.modificationDate] as? Date
            }
            state = .paused
            if autoPlay {
                play()
            } else {
                playbackStateDidChange()
            }
        } catch {
            // A superseded load fails with a cancellation; that is not an error to show.
            guard generation == loadGeneration else { return }
            state = .error(error.localizedDescription)
            playbackStateDidChange()
        }
    }

    /// Makes `identity` the loaded file's. Rows merged into it were cached under another ID.
    private func adopt(_ identity: MediaIdentity) {
        currentMediaID = identity.id
        if identity.didMerge {
            bookmarks.reload()
            highlights.reload()
            perFileStore.reload()
        }
    }

    /// Loads the current file again, after an attempt that failed.
    func retryLoad() {
        guard let url = currentURL else { return }
        Task { await load(url: url) }
    }

    // MARK: - Image Viewing

    /// Shows an image file. Returns whether it could be read.
    private func loadImage(url: URL) -> Bool {
        // The video before it, or one still loading, would otherwise play on under the image.
        decoder.stop()

        guard let image = NSImage(contentsOf: url) else {
            state = .error("Failed to load image")
            playbackStateDidChange()
            return false
        }
        displayedImage = image
        duration = 0
        currentTime = 0
        state = .viewingImage
        playbackStateDidChange()
        return true
    }

    func play() {
        guard state == .paused else { return }

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
            playbackStateDidChange()
            return
        }

        decoder.play()
        if playbackRate != 1.0 {
            decoder.setPlaybackRate(playbackRate)
        }
        state = .playing
        playbackStateDidChange()
    }

    func pause() {
        guard state == .playing else { return }
        decoder.pause()
        state = .paused
        playbackStateDidChange()
        // A pause is often the last thing before the app goes away without a clean quit.
        savePlaybackState()
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

    /// Unloads the current file and returns to the start screen.
    func stop() {
        savePlaybackState()
        loadGeneration += 1
        decoder.stop()
        if pip.isActive {
            pip.togglePiP()
        }
        holdScopedAccess(nil)
        thumbnails.reset()

        state = .stopped
        currentURL = nil
        currentMediaID = nil
        mediaTitle = ""
        mediaInfo = nil
        displayedImage = nil
        currentTime = 0
        duration = 0
        isAtEnd = false
        playbackStateDidChange()
        nowPlaying.clearNowPlayingInfo()
    }

    /// Brings sleep prevention, Now Playing and PiP in line with `state`.
    private func playbackStateDidChange() {
        let isPlaying = state == .playing
        updateSleepPrevention()
        nowPlaying.updatePlaybackState(isPlaying: isPlaying)
        pip.updatePlayingState(isPlaying)
    }

    /// Keeps the display awake while a file plays, unless Settings turns that off.
    /// Also called when the setting changes, so it applies to playback in progress.
    func updateSleepPrevention() {
        if state == .playing, AppSettings.preventSleep.value {
            sleepPreventer.preventSleep()
        } else {
            sleepPreventer.allowSleep()
        }
    }

    /// Switches VideoToolbox decoding on or off to match Settings, for the playing file too.
    func applyHardwareDecodingSetting() {
        decoder.setHardwareDecoding(AppSettings.hardwareDecoding.value)
    }

    /// Stores the resume position and the per-file adjustments of the file being played.
    ///
    /// Runs when the file is left, on every pause, and when the app quits. Only a file that
    /// actually loaded has anything to store: while loading or after an error, the position
    /// and the adjustments still belong to the file before it.
    func savePlaybackState() {
        guard let mediaID = currentMediaID, state.isActive else { return }
        history.recordPosition(
            mediaID: mediaID, title: mediaTitle,
            position: currentTime, duration: duration
        )
        savePerFileSettings(for: mediaID)
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
        isScrubbing = true
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
        isScrubbing = false
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

    func playNext(autoPlay: Bool = AppSettings.autoPlayOnOpen.value) async {
        guard let url = playlist.next() else { return }
        await load(url: url, autoPlay: autoPlay)
    }

    func playPrevious() async {
        guard let url = playlist.previous() else { return }
        await load(url: url)
    }

    // MARK: - Bookmarks

    func addBookmark(name: String? = nil) {
        guard let mediaID = currentMediaID else { return }
        let bookmarkName = name ?? ""

        // Duplicate check + insert — no heavy work
        guard let bookmarkID = bookmarks.addBookmark(mediaID: mediaID, time: currentTime, name: bookmarkName) else {
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
        guard let mediaID = currentMediaID else { return }
        let marks = bookmarks.bookmarks(for: mediaID)
        if let next = marks.first(where: { $0.time > currentTime + 0.5 }) {
            await seek(to: next.time)
            osd.show(.text("\u{25B8} \(next.name)"))
        }
    }

    func seekToPreviousBookmark() async {
        guard let mediaID = currentMediaID else { return }
        let marks = bookmarks.bookmarks(for: mediaID)
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
        guard let mediaID = currentMediaID else { return }
        let segs = highlights.segments(for: mediaID)
        if segs.isEmpty {
            osd.show(.text("No highlights to play"))
            return
        }
        highlights.isEnabled.toggle()
        if highlights.isEnabled {
            osd.show(.text("Highlights ON (\(segs.count) segments)"))
            // Jump to first segment if outside any segment
            if let target = highlights.nextTarget(currentTime: currentTime, mediaID: mediaID) {
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
        guard let mediaID = currentMediaID else { return }
        guard let start = highlights.pendingStart else {
            osd.show(.text("Set highlight start first (Shift+H)"))
            return
        }
        guard currentTime > start else {
            osd.show(.text("End must be after start"))
            return
        }
        if highlights.addSegment(mediaID: mediaID, startTime: start, endTime: currentTime) != nil {
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

    /// Shows the open panel. `unreachableURL` is a recent file that could not be reopened
    /// directly: the panel then starts in its folder and asks for that file.
    func openFile(reopening unreachableURL: URL? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .movie, .video, .mpeg4Movie, .quickTimeMovie, .avi,
            .image, .png, .jpeg, .gif, .tiff, .heic, .bmp, .webP
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        if let unreachableURL {
            panel.directoryURL = unreachableURL.deletingLastPathComponent()
            panel.message = "Choose \u{201C}\(unreachableURL.lastPathComponent)\u{201D} to open it again."
        }

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
    /// A file opened on its own becomes the playlist, unless it is already in it.
    func open(_ url: URL) async {
        if PlaylistManager.isDirectory(url) {
            playlist.replace(folder: url)
            if let firstURL = playlist.play(at: 0) {
                await load(url: firstURL)
            }
        } else {
            playlist.setCurrent(url)
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

    // MARK: - Recent Files

    /// Reopens a file from the playback history. When it cannot be read any more — the sandbox
    /// holds no permission for it, or it is gone — the open panel asks for it again.
    func openRecent(_ record: PlaybackRecord) {
        Task {
            if await !reopen(record) {
                openFile(reopening: record.videoURL)
            }
        }
    }

    private func reopen(_ record: PlaybackRecord) async -> Bool {
        let scopedURL = history.securityScopedURL(for: record)
        let hasScopedAccess = scopedURL?.startAccessingSecurityScopedResource() ?? false

        // The bookmark follows a file that was moved or renamed: load it from where it is now.
        var url = record.videoURL
        if let scopedURL, scopedURL.path != url.path {
            url = scopedURL
        }

        guard FileManager.default.isReadableFile(atPath: url.path) else {
            if hasScopedAccess { scopedURL?.stopAccessingSecurityScopedResource() }
            return false
        }

        holdScopedAccess(hasScopedAccess ? scopedURL : nil)
        playlist.setCurrent(url)
        // The record stays with the file: identifying it moves the record to the new location.
        await load(url: url, expecting: record.id)
        return true
    }

    /// Replaces the security-scoped URL whose sandbox access is held, releasing the previous one.
    private func holdScopedAccess(_ url: URL?) {
        scopedAccessURL?.stopAccessingSecurityScopedResource()
        scopedAccessURL = url
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

    private func savePerFileSettings(for mediaID: String) {
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
        perFileStore.save(settings, for: mediaID)
    }

    private func restorePerFileSettings(for mediaID: String) {
        let settings = perFileStore.settings(for: mediaID)

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
