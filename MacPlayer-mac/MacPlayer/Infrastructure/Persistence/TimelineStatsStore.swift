import Foundation

/// What a `TimelineSeries` measures. The raw value names the metric in the database.
enum TimelineMetric: String, Sendable {
    /// Seconds of playback each part of the timeline has had.
    case watchTime = "watch_time"
}

/// Reads and writes timeline series: one `timeline_stats` row per media and metric, holding
/// the bins as a blob.
///
/// A row is replaced as a whole and its size depends on the bin count alone, so what is stored
/// for a media stays within a couple of kilobytes however much it is played.
@MainActor
final class TimelineStatsStore {
    private var db: SQLiteDatabase { DatabaseManager.shared.db }

    /// The series recorded for a media, or `nil` when there is none.
    func series(for mediaID: String, metric: TimelineMetric) -> TimelineSeries? {
        let rows = try? db.query(
            "SELECT bin_width, bins FROM timeline_stats WHERE media_id = ? AND metric = ?",
            parameters: [.text(mediaID), .text(metric.rawValue)]
        )
        guard let row = rows?.first,
              let binWidth = row["bin_width"]?.realValue,
              let data = row["bins"]?.blobValue
        else { return nil }
        return TimelineSeries(binWidth: binWidth, bins: Self.decode(data))
    }

    /// Stores `series` as what is recorded for the media. Returns whether it was written.
    @discardableResult
    func save(_ series: TimelineSeries, for mediaID: String, metric: TimelineMetric) -> Bool {
        // SQLite would take an empty blob for NULL, and there is nothing in it to keep anyway.
        guard !series.bins.isEmpty else { return false }

        do {
            try db.execute("""
                INSERT INTO timeline_stats (media_id, metric, bin_width, bins, updated_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(media_id, metric) DO UPDATE SET
                    bin_width = excluded.bin_width, bins = excluded.bins, updated_at = excluded.updated_at
            """, parameters: [
                .text(mediaID),
                .text(metric.rawValue),
                .real(series.binWidth),
                .blob(Self.encode(series.bins)),
                .real(Date().timeIntervalSinceReferenceDate)
            ])
            return true
        } catch {
            print("[TimelineStatsStore] save failed: \(error)")
            return false
        }
    }

    // MARK: - Blob Format

    // One little-endian Float32 per bin, in timeline order.

    private static let valueSize = MemoryLayout<UInt32>.size

    private static func encode(_ bins: [Float]) -> Data {
        var data = Data(capacity: bins.count * valueSize)
        for value in bins {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    private static func decode(_ data: Data) -> [Float] {
        data.withUnsafeBytes { bytes in
            (0..<bytes.count / valueSize).map { index in
                let bits = bytes.loadUnaligned(fromByteOffset: index * valueSize, as: UInt32.self)
                return Float(bitPattern: UInt32(littleEndian: bits))
            }
        }
    }
}
