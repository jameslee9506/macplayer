import Foundation

/// Manages the app's SQLite database: schema creation, UserDefaults migration, and TTL cleanup.
@MainActor
final class DatabaseManager {
    static let shared = DatabaseManager()

    let db = SQLiteDatabase()

    private init() {}

    /// Open the database, bring the schema up to date, migrate from UserDefaults, and run cleanup.
    func setup() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("MacPlayer", isDirectory: true)
        setup(at: dbDir.appendingPathComponent("macplayer.db"))
    }

    func setup(at dbURL: URL) {
        do {
            try db.open(at: dbURL)
            try migrateLegacyTables()
            try createTables()
            migrateFromUserDefaults()
            cleanupExpiredData()
        } catch {
            print("[DatabaseManager] setup failed: \(error)")
        }
    }

    // MARK: - Schema

    /// Everything the player remembers about a file hangs off a `media` row, which stands for
    /// the content rather than a location: see `MediaIdentityStore`.
    private func createTables() throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS schema_info (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )
        """)

        // `fingerprint` is NULL until the file is first read. `head_hash` covers its first
        // bytes only, to recognise a file that is still growing. `path` is where the content was
        // last seen, NULL once other content took that path. `bookmark` is the security-scoped
        // bookmark that lets the sandbox reopen the file in a later launch.
        try db.execute("""
            CREATE TABLE IF NOT EXISTS media (
                id TEXT PRIMARY KEY,
                fingerprint TEXT UNIQUE,
                head_hash TEXT,
                size INTEGER,
                mtime REAL,
                path TEXT,
                bookmark BLOB
            )
        """)

        // Added later: filled in the next time the file is read.
        let mediaColumns = try db.query("PRAGMA table_info(media)")
        if !mediaColumns.contains(where: { $0["name"]?.textValue == "head_hash" }) {
            try db.execute("ALTER TABLE media ADD COLUMN head_hash TEXT")
        }

        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_media_path ON media(path)
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS playback_history (
                media_id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                last_position REAL,
                duration REAL,
                last_played_at REAL NOT NULL
            )
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS bookmarks (
                id TEXT PRIMARY KEY,
                media_id TEXT NOT NULL,
                time REAL NOT NULL,
                name TEXT NOT NULL,
                created_at REAL NOT NULL,
                thumbnail_data BLOB
            )
        """)

        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_bookmarks_media ON bookmarks(media_id)
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS per_file_settings (
                media_id TEXT PRIMARY KEY,
                settings_json TEXT NOT NULL,
                updated_at REAL NOT NULL
            )
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS highlights (
                id TEXT PRIMARY KEY,
                media_id TEXT NOT NULL,
                start_time REAL NOT NULL,
                end_time REAL NOT NULL,
                created_at REAL NOT NULL
            )
        """)

        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_highlights_media ON highlights(media_id)
        """)
    }

    /// ID of the media row last seen at `path`, created without a fingerprint when there is none.
    /// For data that predates fingerprints: the fingerprint is filled in when the file is next opened.
    private func mediaID(forPath path: String) throws -> String {
        let rows = try db.query("SELECT id FROM media WHERE path = ? LIMIT 1", parameters: [.text(path)])
        if let id = rows.first?["id"]?.textValue { return id }

        let id = UUID().uuidString
        try db.execute("INSERT INTO media (id, path) VALUES (?, ?)", parameters: [.text(id), .text(path)])
        return id
    }

    // MARK: - Legacy Tables (keyed by file location)

    /// Tables that used to identify a file by its location, with the column that held it.
    private static let legacyLocationColumns = [
        "playback_history": "video_url",
        "bookmarks": "video_url",
        "highlights": "video_url",
        "per_file_settings": "file_path"
    ]

    /// Rebuilds location-keyed tables around `media`: one row, not yet fingerprinted, per
    /// location the old tables mention.
    private func migrateLegacyTables() throws {
        let legacy = try Self.legacyLocationColumns.filter { table, column in
            try db.query("PRAGMA table_info(\(table))").contains { $0["name"]?.textValue == column }
        }.keys
        guard !legacy.isEmpty else { return }

        try db.transaction {
            for table in legacy {
                try db.execute("ALTER TABLE \(table) RENAME TO \(table)_legacy")
            }
            try createTables()

            if legacy.contains("playback_history") { try copyLegacyHistory() }
            if legacy.contains("bookmarks") { try copyLegacyBookmarks() }
            if legacy.contains("highlights") { try copyLegacyHighlights() }
            if legacy.contains("per_file_settings") { try copyLegacySettings() }

            for table in legacy {
                try db.execute("DROP TABLE \(table)_legacy")
            }
        }
        print("[DatabaseManager] Rebuilt \(legacy.sorted().joined(separator: ", ")) around media identities")
    }

    /// File path behind a stored `file://` URL string.
    private static func path(fromURLString string: String?) -> String? {
        guard let string, let url = URL(string: string), url.isFileURL else { return nil }
        return url.path
    }

    private func copyLegacyHistory() throws {
        // Newest first: should two rows name the same file, the recent one is kept.
        let rows = try db.query("SELECT * FROM playback_history_legacy ORDER BY last_played_at DESC")
        for row in rows {
            guard let path = Self.path(fromURLString: row["video_url"]?.textValue),
                  let title = row["title"]?.textValue,
                  let lastPlayedAt = row["last_played_at"]?.realValue
            else { continue }

            let id = try mediaID(forPath: path)
            if let bookmark = row["bookmark"]?.blobValue {
                try db.execute(
                    "UPDATE media SET bookmark = ? WHERE id = ? AND bookmark IS NULL",
                    parameters: [.blob(bookmark), .text(id)]
                )
            }
            try db.execute("""
                INSERT OR IGNORE INTO playback_history (media_id, title, last_position, duration, last_played_at)
                VALUES (?, ?, ?, ?, ?)
            """, parameters: [
                .text(id), .text(title),
                .real(row["last_position"]?.realValue ?? 0),
                .real(row["duration"]?.realValue ?? 0),
                .real(lastPlayedAt)
            ])
        }
    }

    private func copyLegacyBookmarks() throws {
        let urls = try db.query("SELECT DISTINCT video_url FROM bookmarks_legacy")
        for row in urls {
            guard let urlString = row["video_url"]?.textValue,
                  let path = Self.path(fromURLString: urlString)
            else { continue }

            try db.execute("""
                INSERT OR IGNORE INTO bookmarks (id, media_id, time, name, created_at, thumbnail_data)
                SELECT id, ?, time, name, created_at, thumbnail_data FROM bookmarks_legacy WHERE video_url = ?
            """, parameters: [.text(try mediaID(forPath: path)), .text(urlString)])
        }
    }

    private func copyLegacyHighlights() throws {
        let urls = try db.query("SELECT DISTINCT video_url FROM highlights_legacy")
        for row in urls {
            guard let urlString = row["video_url"]?.textValue,
                  let path = Self.path(fromURLString: urlString)
            else { continue }

            try db.execute("""
                INSERT OR IGNORE INTO highlights (id, media_id, start_time, end_time, created_at)
                SELECT id, ?, start_time, end_time, created_at FROM highlights_legacy WHERE video_url = ?
            """, parameters: [.text(try mediaID(forPath: path)), .text(urlString)])
        }
    }

    private func copyLegacySettings() throws {
        let rows = try db.query("SELECT * FROM per_file_settings_legacy")
        for row in rows {
            guard let path = row["file_path"]?.textValue,
                  let json = row["settings_json"]?.textValue,
                  let updatedAt = row["updated_at"]?.realValue
            else { continue }

            try db.execute("""
                INSERT OR IGNORE INTO per_file_settings (media_id, settings_json, updated_at)
                VALUES (?, ?, ?)
            """, parameters: [.text(try mediaID(forPath: path)), .text(json), .real(updatedAt)])
        }
    }

    // MARK: - TTL Cleanup (90 days)

    private func cleanupExpiredData() {
        let cutoff = Date().addingTimeInterval(-90 * 24 * 60 * 60).timeIntervalSinceReferenceDate

        do {
            let historyDeleted = try db.execute(
                "DELETE FROM playback_history WHERE last_played_at < ?",
                parameters: [.real(cutoff)]
            )
            let settingsDeleted = try db.execute(
                "DELETE FROM per_file_settings WHERE updated_at < ?",
                parameters: [.real(cutoff)]
            )
            if historyDeleted + settingsDeleted > 0 {
                print("[DatabaseManager] TTL cleanup: \(historyDeleted) history, \(settingsDeleted) settings removed")
            }

            // A media row nothing refers to any more carries no data worth keeping.
            try db.execute("""
                DELETE FROM media
                WHERE id NOT IN (SELECT media_id FROM playback_history)
                  AND id NOT IN (SELECT media_id FROM bookmarks)
                  AND id NOT IN (SELECT media_id FROM highlights)
                  AND id NOT IN (SELECT media_id FROM per_file_settings)
            """)
        } catch {
            print("[DatabaseManager] TTL cleanup failed: \(error)")
        }
    }

    // MARK: - UserDefaults Migration (one-time)

    private func migrateFromUserDefaults() {
        do {
            let rows = try db.query(
                "SELECT value FROM schema_info WHERE key = ?",
                parameters: [.text("migrated_from_userdefaults")]
            )
            if !rows.isEmpty { return }
        } catch {
            return
        }

        let defaults = UserDefaults.standard

        do {
            try db.transaction {
                // Migrate playback history
                if let data = defaults.data(forKey: "MacPlayer.PlaybackHistory") {
                    try migrateHistory(from: data)
                }

                // Migrate bookmarks
                if let data = defaults.data(forKey: "MacPlayer.Bookmarks") {
                    try migrateBookmarks(from: data)
                }

                // Migrate per-file settings
                if let data = defaults.data(forKey: "MacPlayer.PerFileSettings") {
                    try migratePerFileSettings(from: data)
                }

                // Mark migration as complete
                try db.execute(
                    "INSERT INTO schema_info (key, value) VALUES (?, ?)",
                    parameters: [.text("migrated_from_userdefaults"), .text("1")]
                )
            }

            // Remove old keys after successful migration
            defaults.removeObject(forKey: "MacPlayer.PlaybackHistory")
            defaults.removeObject(forKey: "MacPlayer.Bookmarks")
            defaults.removeObject(forKey: "MacPlayer.PerFileSettings")
            print("[DatabaseManager] UserDefaults migration completed")
        } catch {
            print("[DatabaseManager] Migration failed (will retry next launch): \(error)")
        }
    }

    private func migrateHistory(from data: Data) throws {
        struct LegacyRecord: Decodable {
            let id: UUID
            let videoURL: URL
            let title: String
            var lastPosition: Double
            var duration: Double
            var lastPlayedAt: Date
        }

        let records = try JSONDecoder().decode([LegacyRecord].self, from: data)
        for r in records where r.videoURL.isFileURL {
            try db.execute("""
                INSERT OR IGNORE INTO playback_history (media_id, title, last_position, duration, last_played_at)
                VALUES (?, ?, ?, ?, ?)
            """, parameters: [
                .text(try mediaID(forPath: r.videoURL.path)),
                .text(r.title),
                .real(r.lastPosition),
                .real(r.duration),
                .real(r.lastPlayedAt.timeIntervalSinceReferenceDate)
            ])
        }
    }

    private func migrateBookmarks(from data: Data) throws {
        struct LegacyBookmark: Decodable {
            let id: UUID
            let videoURL: URL
            let time: Double
            let name: String
            let createdAt: Date
            let thumbnailData: Data?
        }

        let bookmarks = try JSONDecoder().decode([LegacyBookmark].self, from: data)
        for b in bookmarks where b.videoURL.isFileURL {
            try db.execute("""
                INSERT OR IGNORE INTO bookmarks (id, media_id, time, name, created_at, thumbnail_data)
                VALUES (?, ?, ?, ?, ?, ?)
            """, parameters: [
                .text(b.id.uuidString),
                .text(try mediaID(forPath: b.videoURL.path)),
                .real(b.time),
                .text(b.name),
                .real(b.createdAt.timeIntervalSinceReferenceDate),
                b.thumbnailData.map { .blob($0) } ?? .null
            ])
        }
    }

    private func migratePerFileSettings(from data: Data) throws {
        let dict = try JSONDecoder().decode([String: PerFileSettings].self, from: data)
        let now = Date().timeIntervalSinceReferenceDate
        for (path, settings) in dict {
            guard let json = try? JSONEncoder().encode(settings),
                  let jsonStr = String(data: json, encoding: .utf8) else { continue }
            try db.execute("""
                INSERT OR IGNORE INTO per_file_settings (media_id, settings_json, updated_at)
                VALUES (?, ?, ?)
            """, parameters: [.text(try mediaID(forPath: path)), .text(jsonStr), .real(now)])
        }
    }
}
