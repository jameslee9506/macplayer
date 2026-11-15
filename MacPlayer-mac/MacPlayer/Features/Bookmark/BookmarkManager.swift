import Foundation

/// Timestamp bookmark in a media, optionally with a thumbnail.
struct Bookmark: Identifiable, Sendable {
    let id: UUID
    /// ID of the media the bookmark belongs to: see `MediaIdentityStore`.
    let mediaID: String
    let time: Double
    let name: String
    let createdAt: Date
    var thumbnailData: Data?
}

/// Manages bookmarks with SQLite persistence. They are keyed by media ID, so they follow a
/// file that was renamed or moved.
@MainActor
@Observable
final class BookmarkManager {
    private(set) var bookmarks: [Bookmark] = []
    private var db: SQLiteDatabase { DatabaseManager.shared.db }

    init() {
        reload()
    }

    // MARK: - CRUD

    /// Add a bookmark. Returns the bookmark ID, or `nil` if a duplicate exists within 1 second.
    @discardableResult
    func addBookmark(mediaID: String, time: Double, name: String, thumbnailData: Data? = nil) -> UUID? {
        let isDuplicate = bookmarks.contains {
            $0.mediaID == mediaID && abs($0.time - time) < 1.0
        }
        if isDuplicate { return nil }

        let bookmark = Bookmark(
            id: UUID(), mediaID: mediaID, time: time, name: name, createdAt: Date(), thumbnailData: thumbnailData
        )
        bookmarks.append(bookmark)

        try? db.execute("""
            INSERT INTO bookmarks (id, media_id, time, name, created_at, thumbnail_data)
            VALUES (?, ?, ?, ?, ?, ?)
        """, parameters: [
            .text(bookmark.id.uuidString),
            .text(mediaID),
            .real(time),
            .text(name),
            .real(bookmark.createdAt.timeIntervalSinceReferenceDate),
            thumbnailData.map { .blob($0) } ?? .null
        ])
        return bookmark.id
    }

    /// Update thumbnail data for an existing bookmark.
    func updateThumbnail(for bookmarkID: UUID, data: Data) {
        if let idx = bookmarks.firstIndex(where: { $0.id == bookmarkID }) {
            bookmarks[idx].thumbnailData = data
        }
        try? db.execute(
            "UPDATE bookmarks SET thumbnail_data = ? WHERE id = ?",
            parameters: [.blob(data), .text(bookmarkID.uuidString)]
        )
    }

    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        try? db.execute("DELETE FROM bookmarks WHERE id = ?", parameters: [.text(bookmark.id.uuidString)])
    }

    func removeBookmarks(at offsets: IndexSet) {
        let ids = offsets.map { bookmarks[$0].id }
        bookmarks.remove(atOffsets: offsets)
        for id in ids {
            try? db.execute("DELETE FROM bookmarks WHERE id = ?", parameters: [.text(id.uuidString)])
        }
    }

    /// Remove all bookmarks of a media.
    func removeAllBookmarks(for mediaID: String) {
        bookmarks.removeAll { $0.mediaID == mediaID }
        try? db.execute(
            "DELETE FROM bookmarks WHERE media_id = ?",
            parameters: [.text(mediaID)]
        )
    }

    /// Bookmarks of a media, sorted by time.
    func bookmarks(for mediaID: String) -> [Bookmark] {
        bookmarks
            .filter { $0.mediaID == mediaID }
            .sorted { $0.time < $1.time }
    }

    // MARK: - Persistence

    /// Reads the bookmarks from the database again. Needed after media rows were merged.
    func reload() {
        guard db.isOpen else { return }
        do {
            let rows = try db.query("SELECT * FROM bookmarks ORDER BY created_at DESC")
            bookmarks = rows.compactMap { row -> Bookmark? in
                guard let id = row["id"]?.textValue.flatMap(UUID.init),
                      let mediaID = row["media_id"]?.textValue,
                      let time = row["time"]?.realValue,
                      let name = row["name"]?.textValue,
                      let createdRef = row["created_at"]?.realValue
                else { return nil }

                return Bookmark(
                    id: id,
                    mediaID: mediaID,
                    time: time,
                    name: name,
                    createdAt: Date(timeIntervalSinceReferenceDate: createdRef),
                    thumbnailData: row["thumbnail_data"]?.blobValue
                )
            }
        } catch {
            print("[BookmarkManager] reload failed: \(error)")
        }
    }
}
