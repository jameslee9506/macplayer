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

/// Manages per-file settings storage backed by SQLite.
@MainActor
final class PerFileSettingsStore {
    private var cache: [String: PerFileSettings] = [:]
    private var db: SQLiteDatabase { DatabaseManager.shared.db }

    init() {
        loadAll()
    }

    func settings(for url: URL) -> PerFileSettings {
        cache[url.path] ?? PerFileSettings()
    }

    func save(_ settings: PerFileSettings, for url: URL) {
        let path = url.path
        let now = Date().timeIntervalSinceReferenceDate

        if settings.isDefault {
            cache.removeValue(forKey: path)
            try? db.execute("DELETE FROM per_file_settings WHERE file_path = ?", parameters: [.text(path)])
        } else {
            cache[path] = settings
            guard let json = try? JSONEncoder().encode(settings),
                  let jsonStr = String(data: json, encoding: .utf8) else { return }
            try? db.execute("""
                INSERT OR REPLACE INTO per_file_settings (file_path, settings_json, updated_at)
                VALUES (?, ?, ?)
            """, parameters: [.text(path), .text(jsonStr), .real(now)])
        }
    }

    private func loadAll() {
        guard db.isOpen else { return }
        do {
            let rows = try db.query("SELECT file_path, settings_json FROM per_file_settings")
            for row in rows {
                guard let path = row["file_path"]?.textValue,
                      let jsonStr = row["settings_json"]?.textValue,
                      let data = jsonStr.data(using: .utf8),
                      let settings = try? JSONDecoder().decode(PerFileSettings.self, from: data)
                else { continue }
                cache[path] = settings
            }
        } catch {
            print("[PerFileSettingsStore] loadAll failed: \(error)")
        }
    }
}
