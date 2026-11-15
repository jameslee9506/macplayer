import Foundation

/// A highlight segment marking a time range in a video.
struct HighlightSegment: Identifiable, Sendable {
    let id: UUID
    let videoURL: URL
    let startTime: Double
    let endTime: Double
    let createdAt: Date

    init(videoURL: URL, startTime: Double, endTime: Double) {
        self.id = UUID()
        self.videoURL = videoURL
        self.startTime = startTime
        self.endTime = endTime
        self.createdAt = Date()
    }

    init(id: UUID, videoURL: URL, startTime: Double, endTime: Double, createdAt: Date) {
        self.id = id
        self.videoURL = videoURL
        self.startTime = startTime
        self.endTime = endTime
        self.createdAt = createdAt
    }
}

/// Manages highlight segments for videos with SQLite persistence.
/// When enabled, playback jumps between highlight segments, skipping everything else.
@MainActor
@Observable
final class HighlightManager {
    private(set) var segments: [HighlightSegment] = []
    var isEnabled: Bool = false

    /// Pending start time for a new segment being marked
    var pendingStart: Double?

    private var db: SQLiteDatabase { DatabaseManager.shared.db }

    init() {
        loadSegments()
    }

    // MARK: - CRUD

    @discardableResult
    func addSegment(videoURL: URL, startTime: Double, endTime: Double) -> UUID? {
        guard endTime > startTime else { return nil }

        // Reject duplicates (same start within 0.5s)
        let isDuplicate = segments.contains {
            $0.videoURL == videoURL && abs($0.startTime - startTime) < 0.5
        }
        if isDuplicate { return nil }

        let segment = HighlightSegment(videoURL: videoURL, startTime: startTime, endTime: endTime)
        segments.append(segment)

        try? db.execute("""
            INSERT INTO highlights (id, video_url, start_time, end_time, created_at)
            VALUES (?, ?, ?, ?, ?)
        """, parameters: [
            .text(segment.id.uuidString),
            .text(videoURL.absoluteString),
            .real(startTime),
            .real(endTime),
            .real(segment.createdAt.timeIntervalSinceReferenceDate)
        ])
        return segment.id
    }

    func removeSegment(_ segment: HighlightSegment) {
        segments.removeAll { $0.id == segment.id }
        try? db.execute("DELETE FROM highlights WHERE id = ?", parameters: [.text(segment.id.uuidString)])
    }

    func removeAllSegments(for videoURL: URL) {
        segments.removeAll { $0.videoURL == videoURL }
        try? db.execute(
            "DELETE FROM highlights WHERE video_url = ?",
            parameters: [.text(videoURL.absoluteString)]
        )
    }

    /// Get segments for a specific video, sorted by start time.
    func segments(for videoURL: URL) -> [HighlightSegment] {
        segments
            .filter { $0.videoURL == videoURL }
            .sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Playback Logic

    /// Determine if playback should jump to a different position.
    /// Returns the target time to seek to, or nil if playback should continue normally.
    func nextTarget(currentTime: Double, videoURL: URL) -> Double? {
        let sorted = segments(for: videoURL)
        guard !sorted.isEmpty else { return nil }

        // Find which segment we're in (if any)
        for (i, seg) in sorted.enumerated() {
            if currentTime >= seg.startTime && currentTime < seg.endTime {
                // Inside this segment — play normally
                return nil
            }
            if currentTime >= seg.endTime {
                // Past this segment's end
                if i == sorted.count - 1 {
                    // Past the last segment — loop to first
                    return sorted[0].startTime
                }
                // Check if we're between this segment's end and the next segment's start
                if currentTime < sorted[i + 1].startTime {
                    return sorted[i + 1].startTime
                }
                continue
            }
            if currentTime < seg.startTime {
                // Before this segment — jump to it
                return seg.startTime
            }
        }
        return nil
    }

    // MARK: - Persistence

    private func loadSegments() {
        guard db.isOpen else { return }
        do {
            let rows = try db.query("SELECT * FROM highlights ORDER BY created_at DESC")
            segments = rows.compactMap { row -> HighlightSegment? in
                guard let id = row["id"]?.textValue.flatMap(UUID.init),
                      let urlStr = row["video_url"]?.textValue,
                      let url = URL(string: urlStr),
                      let startTime = row["start_time"]?.realValue,
                      let endTime = row["end_time"]?.realValue,
                      let createdRef = row["created_at"]?.realValue
                else { return nil }

                return HighlightSegment(
                    id: id,
                    videoURL: url,
                    startTime: startTime,
                    endTime: endTime,
                    createdAt: Date(timeIntervalSinceReferenceDate: createdRef)
                )
            }
        } catch {
            print("[HighlightManager] loadSegments failed: \(error)")
        }
    }
}
