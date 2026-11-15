import Foundation

/// Per-file settings for rotation and filter state, persisted across sessions.
struct PerFileSettings: Codable {
    var rotation: Int = 0
    var filters: [FilterState] = []
    var audioDelay: Double = 0

    struct FilterState: Codable {
        let id: String
        var isEnabled: Bool
        var parameters: [String: Float]
    }

    /// Whether all values are at defaults (no need to store).
    var isDefault: Bool {
        rotation == 0 && filters.allSatisfy { !$0.isEnabled } && audioDelay == 0
    }
}

/// Manages per-file settings storage backed by SQLite. Settings are keyed by media ID, so they
/// follow a file that was renamed or moved.
@MainActor
final class PerFileSettingsStore {
    private var cache: [String: PerFileSettings] = [:]
    private var db: SQLiteDatabase { DatabaseManager.shared.db }

    init() {
        reload()
    }

    func settings(for mediaID: String) -> PerFileSettings {
        cache[mediaID] ?? PerFileSettings()
    }

    func save(_ settings: PerFileSettings, for mediaID: String) {
        let now = Date().timeIntervalSinceReferenceDate

        if settings.isDefault {
            cache.removeValue(forKey: mediaID)
            try? db.execute("DELETE FROM per_file_settings WHERE media_id = ?", parameters: [.text(mediaID)])
        } else {
            cache[mediaID] = settings
            guard let json = try? JSONEncoder().encode(settings),
                  let jsonStr = String(data: json, encoding: .utf8) else { return }
            try? db.execute("""
                INSERT OR REPLACE INTO per_file_settings (media_id, settings_json, updated_at)
                VALUES (?, ?, ?)
            """, parameters: [.text(mediaID), .text(jsonStr), .real(now)])
        }
    }

    /// Reads the settings from the database again. Needed after media rows were merged.
    func reload() {
        guard db.isOpen else { return }
        do {
            let rows = try db.query("SELECT media_id, settings_json FROM per_file_settings")
            var loaded: [String: PerFileSettings] = [:]
            for row in rows {
                guard let mediaID = row["media_id"]?.textValue,
                      let jsonStr = row["settings_json"]?.textValue,
                      let data = jsonStr.data(using: .utf8),
                      let settings = try? JSONDecoder().decode(PerFileSettings.self, from: data)
                else { continue }
                loaded[mediaID] = settings
            }
            cache = loaded
        } catch {
            print("[PerFileSettingsStore] reload failed: \(error)")
        }
    }
}
