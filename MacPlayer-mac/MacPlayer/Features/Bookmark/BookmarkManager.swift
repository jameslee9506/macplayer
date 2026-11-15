import Foundation

/// Timestamp bookmark for a video file, optionally with a thumbnail.
struct Bookmark: Identifiable, Sendable {
    let id: UUID
    let videoURL: URL
    let time: Double
    let name: String
    let createdAt: Date
    let thumbnailData: Data?

    init(videoURL: URL, time: Double, name: String, thumbnailData: Data? = nil) {
        self.id = UUID()
        self.videoURL = videoURL
        self.time = time
        self.name = name
        self.createdAt = Date()
        self.thumbnailData = thumbnailData
    }

    init(id: UUID, videoURL: URL, time: Double, name: String, createdAt: Date, thumbnailData: Data?) {
        self.id = id
        self.videoURL = videoURL
        self.time = time
        self.name = name
        self.createdAt = createdAt
        self.thumbnailData = thumbnailData
    }
}

/// Manages bookmarks for video files with SQLite persistence.
@MainActor
@Observable
final class BookmarkManager {
    private(set) var bookmarks: [Bookmark] = []
    private var db: SQLiteDatabase { DatabaseManager.shared.db }

    init() {
        loadBookmarks()
    }

    // MARK: - CRUD

    /// Add a bookmark. Returns the bookmark ID, or `nil` if a duplicate exists within 1 second.
    @discardableResult
    func addBookmark(videoURL: URL, time: Double, name: String, thumbnailData: Data? = nil) -> UUID? {
        let isDuplicate = bookmarks.contains {
            $0.videoURL == videoURL && abs($0.time - time) < 1.0
        }
        if isDuplicate { return nil }

        let bookmark = Bookmark(videoURL: videoURL, time: time, name: name, thumbnailData: thumbnailData)
        bookmarks.append(bookmark)

        try? db.execute("""
            INSERT INTO bookmarks (id, video_url, time, name, created_at, thumbnail_data)
            VALUES (?, ?, ?, ?, ?, ?)
        """, parameters: [
            .text(bookmark.id.uuidString),
            .text(videoURL.absoluteString),
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
            let old = bookmarks[idx]
            bookmarks[idx] = Bookmark(
                id: old.id, videoURL: old.videoURL, time: old.time,
                name: old.name, createdAt: old.createdAt, thumbnailData: data
            )
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

    /// Remove all bookmarks for a specific video.
    func removeAllBookmarks(for videoURL: URL) {
        bookmarks.removeAll { $0.videoURL == videoURL }
        try? db.execute(
            "DELETE FROM bookmarks WHERE video_url = ?",
            parameters: [.text(videoURL.absoluteString)]
        )
    }

    /// Get bookmarks for a specific video file.
    func bookmarks(for videoURL: URL) -> [Bookmark] {
        bookmarks
            .filter { $0.videoURL == videoURL }
            .sorted { $0.time < $1.time }
    }

    // MARK: - Persistence

    private func loadBookmarks() {
        guard db.isOpen else { return }
        do {
            let rows = try db.query("SELECT * FROM bookmarks ORDER BY created_at DESC")
            bookmarks = rows.compactMap { row -> Bookmark? in
                guard let id = row["id"]?.textValue.flatMap(UUID.init),
                      let urlStr = row["video_url"]?.textValue,
                      let url = URL(string: urlStr),
                      let time = row["time"]?.realValue,
                      let name = row["name"]?.textValue,
                      let createdRef = row["created_at"]?.realValue
                else { return nil }

                return Bookmark(
                    id: id,
                    videoURL: url,
                    time: time,
                    name: name,
                    createdAt: Date(timeIntervalSinceReferenceDate: createdRef),
                    thumbnailData: row["thumbnail_data"]?.blobValue
                )
            }
        } catch {
            print("[BookmarkManager] loadBookmarks failed: \(error)")
        }
    }
}
