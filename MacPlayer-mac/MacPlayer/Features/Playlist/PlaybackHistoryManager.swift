import Foundation

/// Record of a played file with resume position.
struct PlaybackRecord: Identifiable, Sendable {
    /// ID of the media the record belongs to: see `MediaIdentityStore`.
    let id: String
    /// Where the file was last seen.
    let videoURL: URL
    let title: String
    var lastPosition: Double
    var duration: Double
    var lastPlayedAt: Date
    /// Security-scoped bookmark: lets the sandboxed app read the file again in a later launch.
    var bookmark: Data?

    var progress: Double {
        guard duration > 0 else { return 0 }
        return lastPosition / duration
    }
}

/// Manages playback history with resume support. Backed by SQLite.
///
/// Records are keyed by media ID, so a resume position follows a file that was renamed or moved.
@MainActor
@Observable
final class PlaybackHistoryManager {
    private(set) var history: [PlaybackRecord] = []
    private let maxHistoryCount = 50
    private let media: MediaIdentityStore
    private var db: SQLiteDatabase { DatabaseManager.shared.db }

    init(media: MediaIdentityStore) {
        self.media = media
        loadHistory()
    }

    /// Marks a file as opened just now, so it leads the recent list. Its resume position is kept.
    ///
    /// Call while the app can read the file: the bookmark stored here is what lets the sandbox
    /// reopen it later.
    func recordOpened(mediaID: String, url: URL, title: String) {
        let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        if let bookmark {
            media.storeBookmark(bookmark, for: mediaID)
        }

        // The title follows the file name, which may have changed since the last time.
        try? db.execute("""
            INSERT INTO playback_history (media_id, title, last_position, duration, last_played_at)
            VALUES (?, ?, 0, 0, ?)
            ON CONFLICT(media_id) DO UPDATE SET title = excluded.title, last_played_at = excluded.last_played_at
        """, parameters: [
            .text(mediaID),
            .text(title),
            .real(Date().timeIntervalSinceReferenceDate)
        ])

        trimDatabase()
        // Reloading picks up the new location of a moved file, and drops the record of
        // content that this file replaced at its path.
        loadHistory()
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

    /// Stores where playback of a file was left.
    ///
    /// A position in the first or the last five seconds leaves nothing to resume, so it is
    /// stored as 0: a file played to its end starts over next time, rather than at whatever
    /// point an earlier session happened to stop.
    func recordPosition(mediaID: String, title: String, position: Double, duration: Double) {
        let isResumable = position > 5 && position < duration - 5
        let position = isResumable ? position : 0
        let now = Date()

        if let index = history.firstIndex(where: { $0.id == mediaID }) {
            history[index].lastPosition = position
            history[index].duration = duration
            history[index].lastPlayedAt = now

            try? db.execute("""
                UPDATE playback_history SET last_position = ?, duration = ?, last_played_at = ?
                WHERE media_id = ?
            """, parameters: [
                .real(position), .real(duration),
                .real(now.timeIntervalSinceReferenceDate),
                .text(mediaID)
            ])
        } else if isResumable {
            // Not in the list: its record was removed while the file was playing.
            try? db.execute("""
                INSERT OR REPLACE INTO playback_history (media_id, title, last_position, duration, last_played_at)
                VALUES (?, ?, ?, ?, ?)
            """, parameters: [
                .text(mediaID),
                .text(title),
                .real(position), .real(duration),
                .real(now.timeIntervalSinceReferenceDate)
            ])

            trimDatabase()
            loadHistory()
        }
    }

    /// Resume position of a media, when it has been played before.
    func resumePosition(for mediaID: String) -> Double? {
        history.first(where: { $0.id == mediaID })?.lastPosition
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
        try? db.execute("DELETE FROM playback_history WHERE media_id = ?", parameters: [.text(record.id)])
    }

    // MARK: - Persistence

    /// Loads the records whose file has a known location. A media whose path was taken over by
    /// other content keeps its record, out of sight, until its file is found again.
    private func loadHistory() {
        guard db.isOpen else { return }
        do {
            let rows = try db.query("""
                SELECT h.media_id, h.title, h.last_position, h.duration, h.last_played_at, m.path, m.bookmark
                FROM playback_history h JOIN media m ON m.id = h.media_id
                WHERE m.path IS NOT NULL
                ORDER BY h.last_played_at DESC LIMIT ?
            """, parameters: [.integer(Int64(maxHistoryCount))])
            history = rows.compactMap { row -> PlaybackRecord? in
                guard let id = row["media_id"]?.textValue,
                      let path = row["path"]?.textValue,
                      let title = row["title"]?.textValue,
                      let lastPlayedRef = row["last_played_at"]?.realValue
                else { return nil }

                return PlaybackRecord(
                    id: id,
                    videoURL: URL(fileURLWithPath: path),
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
            DELETE FROM playback_history WHERE media_id NOT IN (
                SELECT media_id FROM playback_history ORDER BY last_played_at DESC LIMIT ?
            )
        """, parameters: [.integer(Int64(maxHistoryCount))])
    }
}
