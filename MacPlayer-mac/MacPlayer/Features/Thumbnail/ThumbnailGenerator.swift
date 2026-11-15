import Foundation
import AppKit

/// Owns an open C frame extractor and closes it when released.
private final class ExtractorHandle {
    let raw: OpaquePointer

    init?(path: String) {
        guard let raw = macplayer_frame_extractor_open(path) else { return nil }
        self.raw = raw
    }

    deinit {
        macplayer_frame_extractor_close(raw)
    }
}

/// Holds one video open for thumbnail extraction, so each thumbnail is a seek in an already-open
/// file. Re-opening per thumbnail repeats the container's whole open cost every time, which
/// for some layouts means walking the entire file.
/// The actor serialises access: the C extractor is not thread-safe.
private actor FrameExtractor {
    private static let thumbnailWidth: Int32 = 240

    private let path: String
    private var handle: ExtractorHandle?
    private var openFailed = false
    /// The keyframe most recently made into an image. Times a few seconds apart often share a
    /// keyframe; they then share this image, and the keyframe is not decoded a second time.
    private var latest: (keyframe: Int64, image: NSImage)?

    init(path: String) {
        self.path = path
    }

    /// Thumbnail of the keyframe at `time` (seconds), or nil if there is none to be had.
    func thumbnail(at time: Double) -> NSImage? {
        if handle == nil && !openFailed {
            handle = ExtractorHandle(path: path)
            openFailed = handle == nil
        }
        guard let handle else { return nil }

        let result = macplayer_frame_extractor_extract(
            handle.raw, time, Self.thumbnailWidth, latest?.keyframe ?? -1
        )
        if result.unchanged != 0 { return latest?.image }
        guard let pixels = result.pixels else { return nil }

        let width = Int(result.width)
        let height = Int(result.height)
        // Data takes ownership of the malloc'd buffer.
        let data = Data(bytesNoCopy: pixels, count: width * height * 4, deallocator: .free)
        guard let image = Self.makeImage(rgba: data, width: width, height: height) else { return nil }
        if result.keyframe >= 0 {
            latest = (result.keyframe, image)
        }
        return image
    }

    /// Wraps tightly packed RGBA rows (`width * 4` bytes each) in an image, without copying them.
    private static func makeImage(rgba: Data, width: Int, height: Int) -> NSImage? {
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: rgba as CFData),
              let cgImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              )
        else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
}

/// Supplies the seek bar's preview thumbnails, extracted with the ffmpeg C API.
///
/// A video is divided into buckets of a few seconds with one thumbnail each. They are
/// pre-generated in the background once the video is loaded; a bucket the pointer reaches
/// before that is extracted on demand.
/// The bucket size scales with duration, so fast scrubbing doesn't cycle through near-identical
/// frames and no video has more than `maxThumbnails`.
@MainActor
@Observable
final class ThumbnailGenerator {
    /// Most thumbnails one video gets. Bounds the cache (about 130 KB each) and the
    /// pre-generation work, whatever the video's length.
    private static let maxThumbnails = 360

    /// Thumbnail the preview shows. While the pointer's bucket is still being extracted this
    /// stays a neighbouring or the previous one, so the preview doesn't flicker. The only
    /// observed property: setting it is what redraws the seek bar.
    private(set) var lastImage: NSImage?

    /// Thumbnails by bucket index
    @ObservationIgnored private var cache: [Int: NSImage] = [:]
    /// Bucket the preview shows or is waiting for
    @ObservationIgnored private var wantedKey: Int?
    /// Bucket still to be extracted on demand. A newer one replaces it, so buckets the pointer
    /// only passed over on its way are never decoded.
    @ObservationIgnored private var request: (key: Int, time: Double)?
    @ObservationIgnored private var requestTask: Task<Void, Never>?
    @ObservationIgnored private var pregenTask: Task<Void, Never>?

    /// Bucket size in seconds
    @ObservationIgnored private var bucketSize: Double = 2.0

    /// Extractor for the current video; replaced when a new video is set up
    @ObservationIgnored private var extractor: FrameExtractor?

    /// Convert a time in seconds to a cache key based on current bucket size
    private func cacheKey(for time: Double) -> Int {
        Int(time / bucketSize)
    }

    /// Calculate bucket size based on video duration
    private static func bucketSize(for duration: Double) -> Double {
        let preferred: Double
        switch duration {
        case ..<300:    preferred = 2    // < 5min
        case ..<1800:   preferred = 5    // 5–30min
        default:        preferred = 8    // longer, up to the 48min that fill maxThumbnails
        }
        return max(preferred, duration / Double(maxThumbnails))
    }

    /// Set up the generator for a new video URL and start pre-generating thumbnails.
    func setup(url: URL, duration: Double = 0) {
        reset()
        let extractor = FrameExtractor(path: url.path)
        self.extractor = extractor

        if duration > 0 {
            bucketSize = Self.bucketSize(for: duration)
            startPregeneration(from: extractor, duration: duration)
        } else {
            bucketSize = 2.0
        }
    }

    /// Let go of the current video: its thumbnails, the extraction in progress, the open file.
    func reset() {
        pregenTask?.cancel()
        pregenTask = nil
        requestTask?.cancel()
        requestTask = nil
        request = nil
        wantedKey = nil
        cache.removeAll()
        lastImage = nil
        extractor = nil
    }

    /// Pre-generate every bucket's thumbnail, in order from the start of the video.
    private func startPregeneration(from extractor: FrameExtractor, duration: Double) {
        let bucket = bucketSize
        let count = Int((duration / bucket).rounded(.up))

        // Below playback, and below a thumbnail the pointer is waiting for.
        pregenTask = Task(priority: .utility) { [weak self] in
            for key in 0..<count {
                guard let self, !Task.isCancelled else { return }
                if self.cache[key] != nil { continue }

                let image = await extractor.thumbnail(at: Double(key) * bucket)
                guard !Task.isCancelled else { return }
                if let image {
                    self.store(image, for: key)
                }

                // Throttle: leave the disk and the CPU to playback in between
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Thumbnail to show for `time` (seconds). The seek bar calls this as the pointer moves.
    /// Returns the bucket's own thumbnail if it is cached. Otherwise it requests that one and
    /// returns a stand-in; the real one replaces `lastImage` when it arrives.
    func thumbnail(at time: Double) -> NSImage? {
        let key = cacheKey(for: time)

        // Same bucket as the last call: nothing new to look up or to ask for.
        guard key != wantedKey else { return lastImage }
        wantedKey = key

        if let cached = cache[key] {
            show(cached)
        } else {
            // A neighbour (±1–2 buckets) is nearer the mark than wherever the pointer was before.
            if let neighbor = [1, -1, 2, -2].lazy.compactMap({ self.cache[key + $0] }).first {
                show(neighbor)
            }
            request = (key, time)
            serveRequests()
        }
        return lastImage
    }

    private func show(_ image: NSImage) {
        if lastImage !== image {
            lastImage = image
        }
    }

    private func store(_ image: NSImage, for key: Int) {
        cache[key] = image
        if key == wantedKey {
            show(image)
        }
    }

    /// Extract on-demand requests, one at a time. Each round takes whichever bucket is wanted
    /// by then, so however far the pointer travels meanwhile, the wait for the bucket it stops
    /// on is one or two extractions rather than one per bucket crossed.
    private func serveRequests() {
        guard requestTask == nil, let extractor else { return }

        requestTask = Task(priority: .userInitiated) { [weak self] in
            while let request = self?.takeRequest() {
                let image = await extractor.thumbnail(at: request.time)
                // Cancelled means another video took over; the state is no longer this task's.
                guard !Task.isCancelled else { return }
                if let image {
                    self?.store(image, for: request.key)
                }
            }
            self?.requestTask = nil
        }
    }

    /// Hands out the pending request, unless pre-generation got to that bucket first.
    private func takeRequest() -> (key: Int, time: Double)? {
        defer { request = nil }
        guard let request, cache[request.key] == nil else { return nil }
        return request
    }
}
