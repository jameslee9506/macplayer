import Foundation
import AppKit

/// Generates thumbnail images from video frames at specific timestamps using ffmpeg C API.
/// Pre-generates thumbnails at regular intervals on video load for instant access,
/// and falls back to on-demand generation for uncached times.
/// Thumbnail granularity scales with video duration to avoid excessive cycling during fast scrub.
@MainActor
@Observable
final class ThumbnailGenerator {
    /// Cache keyed by bucketed time index
    private var cache: [Int: NSImage] = [:]
    private var pendingKeys: Set<Int> = []
    private var pregenTask: Task<Void, Never>?

    /// Last successfully displayed thumbnail — shown while next one generates (prevents flicker)
    private(set) var lastImage: NSImage?
    /// Track the last key we actually displayed, to avoid cycling through intermediates
    private var lastDisplayedKey: Int = -1

    /// Bucket size in seconds — scales with video duration
    /// Short (<5m): 2s, Medium (5-30m): 5s, Long (30m-2h): 8s, Very long (>2h): 12s
    private var bucketSize: Double = 2.0

    /// Video URL for thumbnail extraction
    private var videoURL: URL?

    /// Convert a time in seconds to a cache key based on current bucket size
    private func cacheKey(for time: Double) -> Int {
        Int(time / bucketSize)
    }

    /// Calculate bucket size based on video duration
    private static func bucketSize(for duration: Double) -> Double {
        switch duration {
        case ..<300:    return 2    // < 5min
        case ..<1800:   return 5    // 5–30min
        case ..<7200:   return 8    // 30min–2h
        default:        return 12   // > 2h
        }
    }

    /// Set up the generator for a new video URL and start pre-generating thumbnails.
    func setup(url: URL, duration: Double = 0) {
        pregenTask?.cancel()
        cache.removeAll()
        pendingKeys.removeAll()
        lastImage = nil
        lastDisplayedKey = -1
        videoURL = url

        if duration > 0 {
            bucketSize = Self.bucketSize(for: duration)
            startPregeneration(url: url, duration: duration)
        } else {
            bucketSize = 2.0
        }
    }

    /// Pre-generate thumbnails at bucket intervals across the video duration.
    private func startPregeneration(url: URL, duration: Double) {
        pregenTask?.cancel()
        let bucket = bucketSize

        var times: [Double] = []
        var t = 0.0
        while t < duration {
            times.append(t)
            t += bucket
        }

        pregenTask = Task { [weak self] in
            for time in times {
                guard !Task.isCancelled else { return }
                let key = Int(time / bucket)

                // Skip if already cached
                let alreadyCached = await MainActor.run { self?.cache[key] != nil }
                if alreadyCached { continue }

                let image = await Self.generateThumbnail(url: url, time: time)
                guard !Task.isCancelled else { return }
                if let image {
                    await MainActor.run { [weak self] in
                        self?.cache[key] = image
                    }
                }

                // Throttle to avoid CPU spike
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Get a thumbnail for the given time (seconds).
    /// Returns cached image immediately if available, otherwise returns the last known image
    /// while kicking off async generation — eliminates flicker.
    func thumbnail(at time: Double) -> NSImage? {
        let key = cacheKey(for: time)

        // Same bucket as last request — return current image
        if key == lastDisplayedKey {
            return lastImage
        }

        // Exact cache hit
        if let cached = cache[key] {
            lastDisplayedKey = key
            lastImage = cached
            return cached
        }

        // Try nearest cached neighbor (±1–2 buckets)
        for offset in [1, -1, 2, -2] {
            if let neighbor = cache[key + offset] {
                lastDisplayedKey = key
                lastImage = neighbor
                break
            }
        }

        // Kick off async generation if not already pending
        if !pendingKeys.contains(key), let url = videoURL {
            pendingKeys.insert(key)

            Task { [weak self] in
                let image = await Self.generateThumbnail(url: url, time: time)
                await MainActor.run { [weak self] in
                    if let image {
                        self?.cache[key] = image
                        if self?.lastDisplayedKey == key {
                            self?.lastImage = image
                        }
                    }
                    self?.pendingKeys.remove(key)
                }
            }
        }

        return lastImage
    }

    // MARK: - ffmpeg C API

    /// Generate a single thumbnail via ffmpeg C API at the given time.
    nonisolated private static func generateThumbnail(
        url: URL, time: Double
    ) async -> NSImage? {
        let path = url.path
        let result = macplayer_extract_frame(path, time, 240)

        guard let pixels = result.pixels else { return nil }
        defer { free(pixels) }

        let w = Int(result.width)
        let h = Int(result.height)
        guard w > 0, h > 0 else { return nil }

        let bytesPerRow = w * 4
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: pixels,
                  width: w,
                  height: h,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let cgImage = ctx.makeImage()
        else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: w, height: h))
    }

    /// Clear all cached thumbnails.
    func clearCache() {
        pregenTask?.cancel()
        cache.removeAll()
        pendingKeys.removeAll()
        lastImage = nil
        lastDisplayedKey = -1
    }
}
