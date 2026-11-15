import Foundation

/// What `MediaIdentityStore.identify` found out about a file.
struct MediaIdentity: Sendable {
    /// ID of the `media` row. Resume position, bookmarks, highlights and per-file settings hang off it.
    let id: String
    /// Rows keyed by another ID were folded into this one; anything that caches them must reload.
    let didMerge: Bool
}

/// Tells which media a file is, by content rather than by location.
///
/// A `media` row stands for one piece of content, recognised by its `MediaFingerprint`. Its
/// `path` only remembers where that content was last seen, which makes it a shortcut: a file
/// still at the same path with the same size and modification date is not read again.
///
/// - A renamed, moved or copied file has a known fingerprint: it stays the same media and the
///   row takes the new path.
/// - A path whose content was replaced gets a new media row; the old row loses its path and
///   keeps its data for when that content turns up elsewhere.
/// - Rows created before fingerprints existed have none. They get one the first time their
///   file is opened, at the path they were recorded under.
@MainActor
final class MediaIdentityStore {
    private struct Row {
        let id: String
        let fingerprint: String?
        let size: Int64?
        let mtime: Double?
    }

    private var db: SQLiteDatabase { DatabaseManager.shared.db }

    /// Identifies the file at `url`, registering it when it is new.
    ///
    /// `expectedID` is the media the caller believes the file to be: a recent file reopened
    /// through its bookmark, which follows a move. It only matters while that row has no
    /// fingerprint yet, and then lets the row follow the file to its new path.
    func identify(_ url: URL, expecting expectedID: String? = nil) async -> MediaIdentity {
        let path = url.path
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value
        let mtime = (attributes?[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate

        // Unchanged since it was last identified here: no need to read it.
        if let known = row(atPath: path), known.fingerprint != nil,
           let size, let mtime, known.size == size, known.mtime == mtime {
            let didMerge = merge(unfingerprinted(expectedID, otherThan: known.id), into: known.id)
            return MediaIdentity(id: known.id, didMerge: didMerge)
        }

        let fingerprint = await Task.detached { MediaFingerprint.compute(at: url) }.value

        // Rows are read after the suspension: another identify() may have run meanwhile.
        let atPath = row(atPath: path)

        guard let fingerprint else {
            // Unreadable: the location is all there is to go by.
            if let atPath { return MediaIdentity(id: atPath.id, didMerge: false) }
            if let expected = unfingerprinted(expectedID, otherThan: nil) {
                update(expected.id, fingerprint: nil, size: size, mtime: mtime, path: path)
                return MediaIdentity(id: expected.id, didMerge: false)
            }
            let id = insert()
            update(id, fingerprint: nil, size: size, mtime: mtime, path: path)
            return MediaIdentity(id: id, didMerge: false)
        }

        // Rows without a fingerprint that describe this very file: the one recorded at this
        // path and the one the caller expected.
        var legacy: [Row] = []
        if let atPath, atPath.fingerprint == nil { legacy.append(atPath) }
        if let expected = unfingerprinted(expectedID, otherThan: legacy.first?.id) { legacy.append(expected) }

        let id: String
        var didMerge = false
        if let known = row(withFingerprint: fingerprint) {
            // Known content, possibly at a new path.
            id = known.id
            for row in legacy {
                didMerge = merge(row, into: id) || didMerge
            }
        } else if let adopted = legacy.first {
            // First read of a file recorded before fingerprints: the row becomes its identity.
            id = adopted.id
            for row in legacy.dropFirst() {
                didMerge = merge(row, into: id) || didMerge
            }
        } else {
            id = insert()
        }

        // Whatever else was recorded at this path is no longer there.
        try? db.execute(
            "UPDATE media SET path = NULL WHERE path = ? AND id != ?",
            parameters: [.text(path), .text(id)]
        )
        update(id, fingerprint: fingerprint, size: size, mtime: mtime, path: path)
        return MediaIdentity(id: id, didMerge: didMerge)
    }

    /// Stores the security-scoped bookmark that lets the sandbox reopen the media's file later.
    func storeBookmark(_ bookmark: Data, for id: String) {
        try? db.execute(
            "UPDATE media SET bookmark = ? WHERE id = ?",
            parameters: [.blob(bookmark), .text(id)]
        )
    }

    // MARK: - Rows

    private func row(atPath path: String) -> Row? {
        row(where: "path = ?", .text(path))
    }

    private func row(withFingerprint fingerprint: String) -> Row? {
        row(where: "fingerprint = ?", .text(fingerprint))
    }

    /// The row with this ID, when it has no fingerprint yet and is not `excludedID`.
    private func unfingerprinted(_ id: String?, otherThan excludedID: String?) -> Row? {
        guard let id, id != excludedID else { return nil }
        return row(where: "id = ? AND fingerprint IS NULL", .text(id))
    }

    private func row(where condition: String, _ value: SQLiteValue) -> Row? {
        let rows = try? db.query(
            "SELECT id, fingerprint, size, mtime FROM media WHERE \(condition) LIMIT 1",
            parameters: [value]
        )
        guard let row = rows?.first, let id = row["id"]?.textValue else { return nil }
        return Row(
            id: id,
            fingerprint: row["fingerprint"]?.textValue,
            size: row["size"]?.integerValue,
            mtime: row["mtime"]?.realValue
        )
    }

    /// Adds an empty row; `update` fills it in.
    private func insert() -> String {
        let id = UUID().uuidString
        try? db.execute("INSERT INTO media (id) VALUES (?)", parameters: [.text(id)])
        return id
    }

    private func update(_ id: String, fingerprint: String?, size: Int64?, mtime: Double?, path: String?) {
        try? db.execute("""
            UPDATE media SET fingerprint = ?, size = ?, mtime = ?, path = ? WHERE id = ?
        """, parameters: [
            fingerprint.map { .text($0) } ?? .null,
            size.map { .integer($0) } ?? .null,
            mtime.map { .real($0) } ?? .null,
            path.map { .text($0) } ?? .null,
            .text(id)
        ])
    }

    /// Folds a row that turned out to describe the same content into `targetID`: bookmarks and
    /// highlights are combined, while the target keeps its own resume position and settings
    /// when it has them.
    private func merge(_ row: Row?, into targetID: String) -> Bool {
        guard let row, row.id != targetID else { return false }
        let source: SQLiteValue = .text(row.id)
        let target: SQLiteValue = .text(targetID)

        do {
            try db.transaction {
                try db.execute("UPDATE bookmarks SET media_id = ? WHERE media_id = ?", parameters: [target, source])
                try db.execute("UPDATE highlights SET media_id = ? WHERE media_id = ?", parameters: [target, source])
                for table in ["playback_history", "per_file_settings"] {
                    try db.execute(
                        "UPDATE OR IGNORE \(table) SET media_id = ? WHERE media_id = ?",
                        parameters: [target, source]
                    )
                    try db.execute("DELETE FROM \(table) WHERE media_id = ?", parameters: [source])
                }
                try db.execute("""
                    UPDATE media SET bookmark = COALESCE(bookmark, (SELECT bookmark FROM media WHERE id = ?))
                    WHERE id = ?
                """, parameters: [source, target])
                try db.execute("DELETE FROM media WHERE id = ?", parameters: [source])
            }
            return true
        } catch {
            print("[MediaIdentityStore] merge failed: \(error)")
            return false
        }
    }
}
