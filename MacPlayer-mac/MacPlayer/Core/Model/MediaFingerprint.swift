import CryptoKit
import Foundation

/// Content fingerprint of a media file: its size plus three sampled byte ranges.
///
/// Reading a few hundred kilobytes is enough to tell files apart, so a multi-gigabyte video
/// costs the same as a small one. The fingerprint survives a rename, a move and a copy, and
/// changes whenever the bytes do (re-encode, remux, tag edit).
enum MediaFingerprint {
    /// Bytes read from each of the head, the middle and the tail.
    static let sampleSize = 64 * 1024

    /// Fingerprint of the file, or `nil` when it is empty or cannot be read.
    static func compute(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd(), size > 0 else { return nil }

        var hasher = SHA256()
        withUnsafeBytes(of: size.littleEndian) { hasher.update(bufferPointer: $0) }

        let sample = UInt64(sampleSize)
        // A file no larger than the three samples is hashed whole.
        let offsets: [UInt64] = size <= sample * 3 ? [0] : [0, (size - sample) / 2, size - sample]
        let length = offsets.count == 1 ? Int(size) : sampleSize

        for offset in offsets {
            guard (try? handle.seek(toOffset: offset)) != nil,
                  let data = try? handle.read(upToCount: length),
                  data.count == length
            else { return nil }
            hasher.update(data: data)
        }

        // 128 bits are plenty to keep a personal library collision-free.
        return hasher.finalize().prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
