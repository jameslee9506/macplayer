import Foundation

/// Record of a played video file with resume position.
struct PlaybackRecord: Identifiable, Sendable {
    let id: UUID
    let videoURL: URL
    let title: String
    var lastPosition: Double
    var duration: Double
    var lastPlayedAt: Date
    /// Security-scoped bookmark: lets the sandboxed app read the file again in a later launch.
    var bookmark: Data?

    init(videoURL: URL, title: String, position: Double, duration: Double, bookmark: Data? = nil) {
        self.id = UUID()
        self.videoURL = videoURL
        self.title = title
        self.lastPosition = position
        self.duration = duration
        self.lastPlayedAt = Date()
        self.bookmark = bookmark
    }

    init(
        id: UUID, videoURL: URL, title: String, lastPosition: Double, duration: Double,
        lastPlayedAt: Date, bookmark: Data? = nil
    ) {
        self.id = id
        self.videoURL = videoURL
        self.title = title
        self.lastPosition = lastPosition
        self.duration = duration
        self.lastPlayedAt = lastPlayedAt
        self.bookmark = bookmark
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return lastPosition / duration
    }
}

/// Manages playback history with resume support. Backed by SQLite.
@MainActor
@Observable
final class PlaybackHistoryManager {
    private(set) var history: [PlaybackRecord] = []
    private let maxHistoryCount = 50
    private var db: SQLiteDatabase { DatabaseManager.shared.db }

    init() {
        loadHistory()
    }

    /// Marks a file as opened just now, so it leads the recent list. Its resume position is kept.
    ///
    /// Call while the app can read the file: the bookmark stored here is what lets the sandbox
    /// reopen it later.
    func recordOpened(videoURL: URL, title: String) {
        let now = Date()
        let bookmark = try? videoURL.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        if let index = history.firstIndex(where: { $0.videoURL == videoURL }) {
            history[index].lastPlayedAt = now
            if let bookmark { history[index].bookmark = bookmark }

            try? db.execute("""
                UPDATE playback_history SET last_played_at = ?, bookmark = COALESCE(?, bookmark)
                WHERE video_url = ?
            """, parameters: [
                .real(now.timeIntervalSinceReferenceDate),
                bookmark.map { .blob($0) } ?? .null,
                .text(videoURL.absoluteString)
            ])
        } else {
            let record = PlaybackRecord(
                videoURL: videoURL, title: title, position: 0, duration: 0, bookmark: bookmark
            )
            history.insert(record, at: 0)

            try? db.execute("""
                INSERT OR REPLACE INTO playback_history
                    (id, video_url, title, last_position, duration, last_played_at, bookmark)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, parameters: [
                .text(record.id.uuidString),
                .text(videoURL.absoluteString),
                .text(title),
                .real(0), .real(0),
                .real(now.timeIntervalSinceReferenceDate),
                bookmark.map { .blob($0) } ?? .null
            ])

            trimIfNeeded()
        }
    }

    /// Resolves the record's bookmark to a security-scoped URL. The caller starts and stops
    /// access on it. `nil` when there is no bookmark or the file can no longer be found.
    func securityScopedURL(for record: PlaybackRecord) -> URL? {
        guard let bookmark = record.bookmark else { return nil }
        var isStale = false
        // A stale bookmark still resolves; opening the file records a fresh one.
        return try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    /// Record or update playback position for a video.
    func recordPosition(videoURL: URL, title: String, position: Double, duration: Double) {
        // Only record if past 5 seconds and not near end
        guard position > 5 && position < duration - 5 else { return }

        let now = Date()

        // UPSERT: insert or replace by video_url
        if let index = history.firstIndex(where: { $0.videoURL == videoURL }) {
            history[index].lastPosition = position
            history[index].duration = duration
            history[index].lastPlayedAt = now

            try? db.execute("""
                UPDATE playback_history SET last_position = ?, duration = ?, last_played_at = ?
                WHERE video_url = ?
            """, parameters: [
                .real(position), .real(duration),
                .real(now.timeIntervalSinceReferenceDate),
                .text(videoURL.absoluteString)
            ])
        } else {
            let record = PlaybackRecord(
                videoURL: videoURL, title: title, position: position, duration: duration
            )
            history.insert(record, at: 0)

            try? db.execute("""
                INSERT OR REPLACE INTO playback_history (id, video_url, title, last_position, duration, last_played_at)
                VALUES (?, ?, ?, ?, ?, ?)
            """, parameters: [
                .text(record.id.uuidString),
                .text(videoURL.absoluteString),
                .text(title),
                .real(position), .real(duration),
                .real(now.timeIntervalSinceReferenceDate)
            ])

            trimIfNeeded()
        }
    }

    /// Trim old entries in memory and DB.
    private func trimIfNeeded() {
        guard history.count > maxHistoryCount else { return }
        history = Array(history.prefix(maxHistoryCount))
        trimDatabase()
    }

    /// Get resume position for a video URL.
    func resumePosition(for videoURL: URL) -> Double? {
        history.first(where: { $0.videoURL == videoURL })?.lastPosition
    }

    /// Get the most recent playback records, sorted by last played date.
    func recentRecords(limit: Int) -> [PlaybackRecord] {
        Array(
            history.sorted { $0.lastPlayedAt > $1.lastPlayedAt }.prefix(limit)
        )
    }

    func clearHistory() {
        history.removeAll()
        try? db.execute("DELETE FROM playback_history")
    }

    func removeRecord(_ record: PlaybackRecord) {
        history.removeAll { $0.id == record.id }
        try? db.execute("DELETE FROM playback_history WHERE id = ?", parameters: [.text(record.id.uuidString)])
    }

    // MARK: - Persistence

    private func loadHistory() {
        guard db.isOpen else { return }
        do {
            let rows = try db.query(
                "SELECT * FROM playback_history ORDER BY last_played_at DESC LIMIT ?",
                parameters: [.integer(Int64(maxHistoryCount))]
            )
            history = rows.compactMap { row -> PlaybackRecord? in
                guard let id = row["id"]?.textValue.flatMap(UUID.init),
                      let urlStr = row["video_url"]?.textValue,
                      let url = URL(string: urlStr),
                      let title = row["title"]?.textValue,
                      let lastPlayedRef = row["last_played_at"]?.realValue
                else { return nil }

                return PlaybackRecord(
                    id: id,
                    videoURL: url,
                    title: title,
                    lastPosition: row["last_position"]?.realValue ?? 0,
                    duration: row["duration"]?.realValue ?? 0,
                    lastPlayedAt: Date(timeIntervalSinceReferenceDate: lastPlayedRef),
                    bookmark: row["bookmark"]?.blobValue
                )
            }
        } catch {
            print("[PlaybackHistoryManager] loadHistory failed: \(error)")
        }
    }

    /// Keep only the most recent N entries in the database.
    private func trimDatabase() {
        try? db.execute("""
            DELETE FROM playback_history WHERE id NOT IN (
                SELECT id FROM playback_history ORDER BY last_played_at DESC LIMIT ?
            )
        """, parameters: [.integer(Int64(maxHistoryCount))])
    }
}
