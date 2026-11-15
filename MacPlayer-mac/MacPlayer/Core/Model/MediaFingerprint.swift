import CryptoKit
import Foundation

/// Content fingerprint of a media file: its size plus three sampled byte ranges.
///
/// Reading a few hundred kilobytes is enough to tell files apart, so a multi-gigabyte video
/// costs the same as a small one. The fingerprint survives a rename, a move and a copy, and
/// changes whenever the bytes do (re-encode, remux, tag edit).
struct MediaFingerprint: Sendable {
    /// Identifies the content: the size and all three samples.
    let content: String
    /// The head sample alone. Unlike `content`, it stays the same while the file is still
    /// being written, which is how a download in progress is recognised as the same media.
    let head: String

    /// Bytes read from each of the head, the middle and the tail.
    static let sampleSize = 64 * 1024

    /// Fingerprint of the file, or `nil` when it is empty or cannot be read.
    static func compute(at url: URL) -> MediaFingerprint? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd(), size > 0 else { return nil }

        var hasher = SHA256()
        withUnsafeBytes(of: size.littleEndian) { hasher.update(bufferPointer: $0) }

        let sample = UInt64(sampleSize)
        // A file no larger than the three samples is hashed whole.
        let offsets: [UInt64] = size <= sample * 3 ? [0] : [0, (size - sample) / 2, size - sample]
        let length = offsets.count == 1 ? Int(size) : sampleSize

        var head: String?
        for offset in offsets {
            guard (try? handle.seek(toOffset: offset)) != nil,
                  let data = try? handle.read(upToCount: length),
                  data.count == length
            else { return nil }
            hasher.update(data: data)
            if offset == 0 {
                head = hex(SHA256.hash(data: data.prefix(sampleSize)))
            }
        }

        guard let head else { return nil }
        return MediaFingerprint(content: hex(hasher.finalize()), head: head)
    }

    /// First 128 bits of a digest: plenty to keep a personal library collision-free.
    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
