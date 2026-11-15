import Foundation
import OpenGL.GL
import OpenGL.GL3

/// mpv-based decoder using libmpv render API with OpenGL.
/// Provides superior format support (MKV, WebM, AVI) and built-in subtitle rendering.
@MainActor
final class MPVDecoder {

    // MARK: - mpv handles (nonisolated for C callback access)

    nonisolated(unsafe) private(set) var mpv: OpaquePointer?
    nonisolated(unsafe) private(set) var mpvRenderContext: OpaquePointer?

    // MARK: - State

    private(set) var isPlaying: Bool = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var audioDelay: Double = 0

    /// HDR manager reference — set by PlaybackEngine so property changes flow to it
    weak var hdrManager: HDRManager?

    /// Track manager reference — set by PlaybackEngine so track changes flow to it
    weak var trackManager: TrackManager?

    var volume: Float = 1.0 {
        didSet { setMPVProperty("volume", Double(volume * 100)) }
    }

    var rate: Float = 1.0 {
        didSet { setMPVProperty("speed", Double(rate)) }
    }

    var isMuted: Bool = false {
        didSet { setMPVFlag("mute", isMuted) }
    }

    var onPlaybackDidEnd: (() -> Void)?

    /// Callback invoked on the render thread when mpv has a new frame to display.
    /// nonisolated(unsafe) because it is set on MainActor but read from GL callback thread.
    nonisolated(unsafe) var onRenderUpdate: (() -> Void)?

    // MARK: - Private

    /// Event processing queue — reads mpv events off the main thread
    private let eventQueue = DispatchQueue(label: "io.github.jameslee9506.macplayer.mpv.events", qos: .userInitiated)
    nonisolated(unsafe) private var isShuttingDown = false

    /// Continuation for awaiting FILE_LOADED event during load()
    private var fileLoadContinuation: CheckedContinuation<Void, any Error>?

    /// Bumped by every load(); a call that finds it changed after suspending was superseded
    private var loadGeneration = 0

    // MARK: - Initialization

    init() {
        setupMPV()
    }

    deinit {
        destroyMPV()
    }

    private func setupMPV() {
        guard let ctx = mpv_create() else {
            print("[MPVDecoder] mpv_create() failed")
            return
        }
        mpv = ctx

        // Core options for embedded library use
        checkError(mpv_set_option_string(ctx, "vo", "libmpv"))
        checkError(mpv_set_option_string(ctx, "config", "no"))
        checkError(mpv_set_option_string(ctx, "input-default-bindings", "no"))
        checkError(mpv_set_option_string(ctx, "input-vo-keyboard", "no"))
        checkError(mpv_set_option_string(ctx, "hwdec", "auto"))
        checkError(mpv_set_option_string(ctx, "osd-level", "0"))
        checkError(mpv_set_option_string(ctx, "keep-open", "yes"))
        checkError(mpv_set_option_string(ctx, "ytdl", "no"))
        checkError(mpv_set_option_string(ctx, "idle", "yes"))
        checkError(mpv_set_option_string(ctx, "input-media-keys", "no"))

        // HDR: let mpv handle tone mapping via its GPU shader pipeline
        checkError(mpv_set_option_string(ctx, "tone-mapping", "auto"))
        checkError(mpv_set_option_string(ctx, "hdr-compute-peak", "auto"))
        checkError(mpv_set_option_string(ctx, "target-colorspace-hint", "auto"))

        // Disable cache to skip initial buffer fill — start playback immediately
        checkError(mpv_set_option_string(ctx, "cache", "no"))

        // Trust container metadata (moov/mkv header) — skip stream probing like AVFoundation
        checkError(mpv_set_option_string(ctx, "demuxer-lavf-analyzeduration", "0"))
        checkError(mpv_set_option_string(ctx, "demuxer-lavf-probesize", "32"))

        // Auto-load subtitle files with fuzzy name matching
        checkError(mpv_set_option_string(ctx, "sub-auto", "fuzzy"))

        // Precise seeking — always decode to exact frame (critical for scrub responsiveness)
        checkError(mpv_set_option_string(ctx, "hr-seek", "yes"))
        checkError(mpv_set_option_string(ctx, "hr-seek-framedrop", "yes"))

        // Initialize mpv
        checkError(mpv_initialize(ctx))

        // Observe properties for state synchronization
        mpv_observe_property(ctx, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(ctx, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(ctx, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(ctx, 0, "eof-reached", MPV_FORMAT_FLAG)

        // HDR property observers
        mpv_observe_property(ctx, 0, "video-params/primaries", MPV_FORMAT_STRING)
        mpv_observe_property(ctx, 0, "video-params/gamma", MPV_FORMAT_STRING)

        // Track property observers
        mpv_observe_property(ctx, 0, "track-list/count", MPV_FORMAT_INT64)
        mpv_observe_property(ctx, 0, "aid", MPV_FORMAT_INT64)
        mpv_observe_property(ctx, 0, "sid", MPV_FORMAT_INT64)

        // Set up wakeup callback for event processing
        let ud = Unmanaged.passUnretained(self).toOpaque()
        mpv_set_wakeup_callback(mpv, { ctx in
            guard let ctx else { return }
            let decoder = Unmanaged<MPVDecoder>.fromOpaque(ctx).takeUnretainedValue()
            decoder.eventQueue.async { [weak decoder] in
                decoder?.readEvents()
            }
        }, ud)
    }

    // MARK: - Render Context

    /// Stable C string for the API type — must outlive the render context.
    /// Swift's #define import of MPV_RENDER_API_TYPE_OPENGL creates a temporary
    /// that gets freed before mpv reads it, causing "operation not implemented".
    nonisolated(unsafe) private static let apiTypeOpenGL: UnsafeMutablePointer<CChar> = {
        let ptr = strdup("opengl")!
        return ptr
    }()

    /// Initialize the OpenGL render context. Must be called from the GL thread.
    nonisolated func initRenderContext(getProcAddress: @escaping @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?) {
        guard let mpv, mpvRenderContext == nil else { return }

        var glInitParams = mpv_opengl_init_params(
            get_proc_address: getProcAddress,
            get_proc_address_ctx: nil
        )
        var advancedControl: Int32 = 1

        // All pointers must remain valid until mpv_render_context_create returns.
        // Use nested withUnsafeMutablePointer to guarantee lifetimes.
        withUnsafeMutablePointer(to: &glInitParams) { glPtr in
            withUnsafeMutablePointer(to: &advancedControl) { ctrlPtr in
                var params: [mpv_render_param] = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(MPVDecoder.apiTypeOpenGL)),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: UnsafeMutableRawPointer(glPtr)),
                    mpv_render_param(type: MPV_RENDER_PARAM_ADVANCED_CONTROL, data: UnsafeMutableRawPointer(ctrlPtr)),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                ]

                var renderCtx: OpaquePointer?
                let err = mpv_render_context_create(&renderCtx, mpv, &params)
                if err < 0 {
                    print("[MPVDecoder] mpv_render_context_create failed: \(String(cString: mpv_error_string(err)))")
                    return
                }
                mpvRenderContext = renderCtx
                print("[MPVDecoder] Render context created successfully")

                // Set update callback — fires when mpv has a new frame
                let ud = Unmanaged.passUnretained(self).toOpaque()
                mpv_render_context_set_update_callback(renderCtx, { ctx in
                    guard let ctx else { return }
                    let decoder = Unmanaged<MPVDecoder>.fromOpaque(ctx).takeUnretainedValue()
                    decoder.onRenderUpdate?()
                }, ud)
            }
        }
    }

    /// Render the current frame to the given FBO. Must be called from the GL thread.
    nonisolated func render(fbo: Int32, width: Int32, height: Int32) {
        guard let mpvRenderContext else { return }

        var fboInfo = mpv_opengl_fbo(
            fbo: fbo,
            w: width,
            h: height,
            internal_format: 0
        )
        var flipY: Int32 = 1

        withUnsafeMutablePointer(to: &fboInfo) { fboPtr in
            withUnsafeMutablePointer(to: &flipY) { flipPtr in
                var params: [mpv_render_param] = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(fboPtr)),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: UnsafeMutableRawPointer(flipPtr)),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                ]
                mpv_render_context_render(mpvRenderContext, &params)
            }
        }
    }

    // MARK: - Playback Control

    func load(url: URL) async throws {
        let loadStart = CFAbsoluteTimeGetCurrent()
        let path = url.path

        // Probe the container layout off the main actor — on a disk that has spun down,
        // even these few header reads can take seconds.
        loadGeneration += 1
        let generation = loadGeneration
        let hasSplitMdat = await Task.detached(priority: .userInitiated) {
            macplayer_mp4_has_split_mdat(path) != 0
        }.value
        // A newer load() started while we were probing; let that one win.
        guard generation == loadGeneration else { throw CancellationError() }

        guard let mpv else { throw MPVError.notInitialized }

        // Cancel any pending load
        fileLoadContinuation?.resume(throwing: CancellationError())
        fileLoadContinuation = nil

        var cmd = ["loadfile", path]
        if hasSplitMdat {
            // moov already indexes every sample. Without this, lavf walks every remaining
            // top-level box before the file opens — seconds on a hard disk. With it, those
            // boxes are read only as playback or a seek reaches them. Per-file option.
            cmd += ["replace", "-1", "index=recreate"]
        }

        // Wait for FILE_LOADED event instead of arbitrary sleep
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            self.fileLoadContinuation = continuation

            let cmdStart = CFAbsoluteTimeGetCurrent()
            let result = cmd.withCStrings { ptrs in
                var mutPtrs = ptrs
                return mpv_command(mpv, &mutPtrs)
            }
            print("[PERF] mpv_command(loadfile): \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - cmdStart))s")

            if result < 0 {
                self.fileLoadContinuation = nil
                continuation.resume(throwing: MPVError.commandFailed(String(cString: mpv_error_string(result))))
            }
        }

        print("[PERF] FILE_LOADED event: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - loadStart))s total")

        // File is fully loaded — duration is now available
        var dur: Double = 0
        if mpv_get_property(mpv, "duration", MPV_FORMAT_DOUBLE, &dur) >= 0 {
            duration = dur
        }
    }

    func play() {
        setMPVFlag("pause", false)
    }

    func pause() {
        setMPVFlag("pause", true)
    }

    func stop() {
        guard let mpv else { return }
        let cmd = ["stop"]
        cmd.withCStrings { ptrs in
            var mutPtrs = ptrs
            _ = mpv_command(mpv, &mutPtrs)
        }
        currentTime = 0
        duration = 0
        isPlaying = false
    }

    func seek(to time: Double) async {
        guard let mpv else { return }
        let timeStr = String(format: "%.3f", time)
        let cmd = ["seek", timeStr, "absolute", "exact"]
        cmd.withCStrings { ptrs in
            var mutPtrs = ptrs
            _ = mpv_command(mpv, &mutPtrs)
        }
        currentTime = time
    }

    /// Fast seek using relative + keyframes — non-blocking, for arrow key navigation.
    func seekRelativeFast(by delta: Double) {
        guard let mpv else { return }
        let deltaStr = String(format: "%.3f", delta)
        let cmd = ["seek", deltaStr, "relative", "keyframes"]
        cmd.withCStrings { ptrs in
            var mutPtrs = ptrs
            _ = mpv_command_async(mpv, 0, &mutPtrs)
        }
        currentTime = max(0, min(currentTime + delta, duration))
    }

    func seekRelative(by delta: Double) async {
        let target = max(0, min(currentTime + delta, duration))
        await seek(to: target)
    }

    func scrub(to time: Double) {
        guard let mpv else { return }
        // Use seek command with absolute+exact for frame-accurate scrub preview
        let timeStr = String(format: "%.3f", time)
        let cmd = ["seek", timeStr, "absolute", "exact"]
        cmd.withCStrings { ptrs in
            var mutPtrs = ptrs
            _ = mpv_command_async(mpv, 0, &mutPtrs)
        }
        currentTime = time
    }

    func setPlaybackRate(_ rate: Float) {
        self.rate = rate
    }

    func stepForward() {
        guard let mpv else { return }
        let cmd = ["frame-step"]
        cmd.withCStrings { ptrs in
            var mutPtrs = ptrs
            _ = mpv_command(mpv, &mutPtrs)
        }
    }

    func stepBackward() {
        guard let mpv else { return }
        let cmd = ["frame-back-step"]
        cmd.withCStrings { ptrs in
            var mutPtrs = ptrs
            _ = mpv_command(mpv, &mutPtrs)
        }
    }

    func applyAudioDelay(_ delay: Double) async {
        setMPVProperty("audio-delay", delay)
        audioDelay = delay
    }

    func addSubtitle(path: String, select: Bool = true) {
        guard let mpv else { return }
        let mode = select ? "select" : "auto"
        let cmd = ["sub-add", path, mode]
        cmd.withCStrings { ptrs in
            var mutPtrs = ptrs
            mpv_command_async(mpv, 0, &mutPtrs)
        }
    }

    func removeSubtitle(id: Int) {
        guard let mpv else { return }
        let cmd = ["sub-remove", "\(id)"]
        cmd.withCStrings { ptrs in
            var mutPtrs = ptrs
            mpv_command_async(mpv, 0, &mutPtrs)
        }
    }

    func takeScreenshot(to path: String) -> Bool {
        guard let mpv else { return false }
        let cmd = ["screenshot-to-file", path, "video"]
        let result = cmd.withCStrings { ptrs in
            var mutPtrs = ptrs
            return mpv_command(mpv, &mutPtrs)
        }
        return result >= 0
    }

    // MARK: - Event Loop

    /// Read all pending events from mpv. Called on eventQueue.
    nonisolated private func readEvents() {
        guard let mpv else { return }

        while true {
            let event = mpv_wait_event(mpv, 0)
            guard let event else { break }

            if event.pointee.event_id == MPV_EVENT_NONE { break }

            handleEvent(event.pointee)
        }
    }

    nonisolated private func handleEvent(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_PROPERTY_CHANGE:
            guard let data = event.data else { return }
            let prop = data.assumingMemoryBound(to: mpv_event_property.self).pointee
            guard let name = prop.name else { return }
            let propName = String(cString: name)
            handlePropertyChange(propName, prop)

        case MPV_EVENT_FILE_LOADED:
            // File finished loading — track list is now available.
            // This is the most reliable point to query tracks (same approach as IINA).
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let tracks = self.getTrackList()
                self.trackManager?.updateTracks(tracks)

                // Also read current selections
                if let aid = self.getMPVPropertyInt64("aid") {
                    self.trackManager?.updateCurrentAudioID(Int(aid))
                }
                if let sid = self.getMPVPropertyInt64("sid") {
                    self.trackManager?.updateCurrentSubtitleID(Int(sid))
                }

                // Resume load() continuation — file is ready for playback
                self.fileLoadContinuation?.resume()
                self.fileLoadContinuation = nil
            }

        case MPV_EVENT_END_FILE:
            // Don't call onPlaybackDidEnd here — it fires for loadfile/stop too,
            // which would incorrectly auto-advance the playlist.
            // Natural EOF is handled by the "eof-reached" property observer instead.
            let isError: Bool
            if let data = event.data {
                isError = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee.reason == MPV_END_FILE_REASON_ERROR
            } else {
                isError = false
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isPlaying = false

                // If waiting for file load and mpv reports error, fail the continuation
                if isError,
                   let cont = self.fileLoadContinuation {
                    self.fileLoadContinuation = nil
                    cont.resume(throwing: MPVError.commandFailed("Failed to load file"))
                }
            }

        case MPV_EVENT_SHUTDOWN:
            break

        default:
            break
        }
    }

    nonisolated private func handlePropertyChange(_ name: String, _ prop: mpv_event_property) {
        switch name {
        case "pause":
            guard prop.format == MPV_FORMAT_FLAG, let data = prop.data else { return }
            let paused = data.assumingMemoryBound(to: Int32.self).pointee != 0
            DispatchQueue.main.async { [weak self] in
                self?.isPlaying = !paused
            }

        case "time-pos":
            guard prop.format == MPV_FORMAT_DOUBLE, let data = prop.data else { return }
            let time = data.assumingMemoryBound(to: Double.self).pointee
            DispatchQueue.main.async { [weak self] in
                self?.currentTime = time
            }

        case "duration":
            guard prop.format == MPV_FORMAT_DOUBLE, let data = prop.data else { return }
            let dur = data.assumingMemoryBound(to: Double.self).pointee
            DispatchQueue.main.async { [weak self] in
                self?.duration = dur
            }

        case "eof-reached":
            guard prop.format == MPV_FORMAT_FLAG, let data = prop.data else { return }
            let eof = data.assumingMemoryBound(to: Int32.self).pointee != 0
            if eof {
                DispatchQueue.main.async { [weak self] in
                    self?.onPlaybackDidEnd?()
                }
            }

        case "video-params/primaries", "video-params/gamma":
            let value: String?
            if prop.format == MPV_FORMAT_STRING, let data = prop.data {
                let cStr = data.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee
                value = cStr.map { String(cString: $0) }
            } else {
                value = nil
            }
            DispatchQueue.main.async { [weak self] in
                self?.hdrManager?.handlePropertyChange(name: name, value: value)
            }

        case "track-list/count":
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let tracks = self.getTrackList()
                self.trackManager?.updateTracks(tracks)
            }

        case "aid":
            guard prop.format == MPV_FORMAT_INT64, let data = prop.data else { return }
            let aid = Int(data.assumingMemoryBound(to: Int64.self).pointee)
            DispatchQueue.main.async { [weak self] in
                self?.trackManager?.updateCurrentAudioID(aid)
            }

        case "sid":
            guard prop.format == MPV_FORMAT_INT64, let data = prop.data else { return }
            let sid = Int(data.assumingMemoryBound(to: Int64.self).pointee)
            DispatchQueue.main.async { [weak self] in
                self?.trackManager?.updateCurrentSubtitleID(sid)
            }

        default:
            break
        }
    }

    // MARK: - Shutdown

    /// Synchronous cleanup callable from deinit. Accesses only nonisolated(unsafe) fields.
    nonisolated private func destroyMPV() {
        guard !isShuttingDown else { return }
        isShuttingDown = true

        if let renderCtx = mpvRenderContext {
            mpv_render_context_set_update_callback(renderCtx, nil, nil)
            mpv_render_context_free(renderCtx)
            mpvRenderContext = nil
        }

        if let mpv {
            mpv_destroy(mpv)
            self.mpv = nil
        }
    }

    func shutdown() {
        destroyMPV()
    }

    // MARK: - Render Helpers

    /// Check if mpv has a new frame to render. Must be called from the GL thread.
    /// This is the equivalent of IINA's `shouldRenderUpdateFrame()`.
    nonisolated func shouldRenderUpdateFrame() -> Bool {
        guard let mpvRenderContext else { return false }
        let flags = mpv_render_context_update(mpvRenderContext)
        return flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) > 0
    }

    /// Report that a frame was displayed. Must be called after rendering.
    nonisolated func reportSwap() {
        guard let mpvRenderContext else { return }
        mpv_render_context_report_swap(mpvRenderContext)
    }

    // MARK: - Media Info

    func getMediaInfo() -> MediaInfo? {
        guard mpv != nil else { return nil }
        return MediaInfo(
            filename: getMPVPropertyString("filename") ?? "",
            fileSize: getMPVPropertyInt64("file-size"),
            container: getMPVPropertyString("file-format"),
            videoCodec: getMPVPropertyString("video-codec"),
            width: getMPVPropertyInt64("width"),
            height: getMPVPropertyInt64("height"),
            fps: getMPVPropertyDouble("container-fps"),
            videoBitrate: getMPVPropertyInt64("video-bitrate"),
            pixelFormat: getMPVPropertyString("video-params/pixelformat"),
            audioCodec: getMPVPropertyString("audio-codec"),
            audioChannels: getMPVPropertyInt64("audio-params/channel-count"),
            audioSampleRate: getMPVPropertyInt64("audio-params/samplerate"),
            audioBitrate: getMPVPropertyInt64("audio-bitrate")
        )
    }

    // MARK: - Track List

    /// Parse mpv's track-list into MediaTrack models.
    /// mpv exposes track-list/count and per-track properties like track-list/N/type.
    func getTrackList() -> [MediaTrack] {
        guard let mpv else { return [] }
        var count: Int64 = 0
        guard mpv_get_property(mpv, "track-list/count", MPV_FORMAT_INT64, &count) >= 0 else { return [] }

        var tracks: [MediaTrack] = []
        for i in 0..<Int(count) {
            let prefix = "track-list/\(i)"

            guard let typeStr = getMPVPropertyString("\(prefix)/type"),
                  let type = MediaTrack.TrackType(rawValue: typeStr)
            else { continue }

            var trackID: Int64 = 0
            mpv_get_property(mpv, "\(prefix)/id", MPV_FORMAT_INT64, &trackID)

            var isDefault: Int32 = 0
            mpv_get_property(mpv, "\(prefix)/default", MPV_FORMAT_FLAG, &isDefault)

            var isExternal: Int32 = 0
            mpv_get_property(mpv, "\(prefix)/external", MPV_FORMAT_FLAG, &isExternal)

            tracks.append(MediaTrack(
                id: Int(trackID),
                type: type,
                title: getMPVPropertyString("\(prefix)/title"),
                lang: getMPVPropertyString("\(prefix)/lang"),
                codec: getMPVPropertyString("\(prefix)/codec"),
                isDefault: isDefault != 0,
                isExternal: isExternal != 0
            ))
        }
        return tracks
    }

    // MARK: - Property Getters

    func getMPVPropertyString(_ name: String) -> String? {
        guard let mpv else { return nil }
        guard let cStr = mpv_get_property_string(mpv, name) else { return nil }
        let value = String(cString: cStr)
        mpv_free(cStr)
        return value
    }

    func getMPVPropertyDouble(_ name: String) -> Double? {
        guard let mpv else { return nil }
        var value: Double = 0
        let err = mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &value)
        return err >= 0 ? value : nil
    }

    func getMPVPropertyInt64(_ name: String) -> Int64? {
        guard let mpv else { return nil }
        var value: Int64 = 0
        let err = mpv_get_property(mpv, name, MPV_FORMAT_INT64, &value)
        return err >= 0 ? value : nil
    }

    // MARK: - Property Setters

    func setMPVProperty(_ name: String, _ value: Double) {
        guard let mpv else { return }
        var val = value
        mpv_set_property(mpv, name, MPV_FORMAT_DOUBLE, &val)
    }

    func setMPVInt64(_ name: String, _ value: Int64) {
        guard let mpv else { return }
        var val = value
        mpv_set_property(mpv, name, MPV_FORMAT_INT64, &val)
    }

    func setMPVString(_ name: String, _ value: String) {
        guard let mpv else { return }
        value.withCString { cStr in
            var ptr = UnsafeMutablePointer(mutating: cStr)
            mpv_set_property(mpv, name, MPV_FORMAT_STRING, &ptr)
        }
    }

    func setMPVFlag(_ name: String, _ value: Bool) {
        guard let mpv else { return }
        var val: Int32 = value ? 1 : 0
        mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &val)
    }

    private func checkError(_ status: Int32) {
        if status < 0 {
            print("[MPVDecoder] mpv error: \(String(cString: mpv_error_string(status)))")
        }
    }
}

// MARK: - MPV Error

enum MPVError: Error, LocalizedError {
    case notInitialized
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized: return "mpv not initialized"
        case .commandFailed(let msg): return "mpv command failed: \(msg)"
        }
    }
}

// MARK: - String Array C Helper

extension Array where Element == String {
    @discardableResult
    func withCStrings<R>(_ body: ([UnsafePointer<CChar>?]) -> R) -> R {
        var cStrings: [UnsafeMutablePointer<CChar>?] = self.map { strdup($0) }
        cStrings.append(nil)
        defer { cStrings.forEach { free($0) } }
        let constPtrs = cStrings.map { UnsafePointer($0) }
        return body(constPtrs)
    }
}
