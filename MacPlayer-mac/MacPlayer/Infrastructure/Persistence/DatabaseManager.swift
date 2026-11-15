import Foundation

/// Manages the app's SQLite database: schema creation, UserDefaults migration, and TTL cleanup.
@MainActor
final class DatabaseManager {
    static let shared = DatabaseManager()

    let db = SQLiteDatabase()

    private init() {}

    /// Open the database, create tables, migrate from UserDefaults, and run TTL cleanup.
    func setup() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("MacPlayer", isDirectory: true)
        let dbURL = dbDir.appendingPathComponent("macplayer.db")

        do {
            try db.open(at: dbURL)
            try createTables()
            migrateFromUserDefaults()
            cleanupExpiredData()
        } catch {
            print("[DatabaseManager] setup failed: \(error)")
        }
    }

    // MARK: - Schema

    private func createTables() throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS schema_info (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS playback_history (
                id TEXT PRIMARY KEY,
                video_url TEXT NOT NULL UNIQUE,
                title TEXT NOT NULL,
                last_position REAL,
                duration REAL,
                last_played_at REAL NOT NULL
            )
        """)

        // Added later: security-scoped bookmark that lets the sandbox reopen a recent file.
        let historyColumns = try db.query("PRAGMA table_info(playback_history)")
        if !historyColumns.contains(where: { $0["name"]?.textValue == "bookmark" }) {
            try db.execute("ALTER TABLE playback_history ADD COLUMN bookmark BLOB")
        }

        try db.execute("""
            CREATE TABLE IF NOT EXISTS bookmarks (
                id TEXT PRIMARY KEY,
                video_url TEXT NOT NULL,
                time REAL NOT NULL,
                name TEXT NOT NULL,
                created_at REAL NOT NULL,
                thumbnail_data BLOB
            )
        """)

        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_bookmarks_url ON bookmarks(video_url)
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS per_file_settings (
                file_path TEXT PRIMARY KEY,
                settings_json TEXT NOT NULL,
                updated_at REAL NOT NULL
            )
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS highlights (
                id TEXT PRIMARY KEY,
                video_url TEXT NOT NULL,
                start_time REAL NOT NULL,
                end_time REAL NOT NULL,
                created_at REAL NOT NULL
            )
        """)

        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_highlights_url ON highlights(video_url)
        """)
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
        for r in records {
            try db.execute("""
                INSERT OR IGNORE INTO playback_history (id, video_url, title, last_position, duration, last_played_at)
                VALUES (?, ?, ?, ?, ?, ?)
            """, parameters: [
                .text(r.id.uuidString),
                .text(r.videoURL.absoluteString),
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
        for b in bookmarks {
            try db.execute("""
                INSERT OR IGNORE INTO bookmarks (id, video_url, time, name, created_at, thumbnail_data)
                VALUES (?, ?, ?, ?, ?, ?)
            """, parameters: [
                .text(b.id.uuidString),
                .text(b.videoURL.absoluteString),
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
                INSERT OR IGNORE INTO per_file_settings (file_path, settings_json, updated_at)
                VALUES (?, ?, ?)
            """, parameters: [.text(path), .text(jsonStr), .real(now)])
        }
    }
}
