import Foundation
import MacPlayerSQLite

/// Lightweight SQLite3 C API wrapper with WAL mode.
@MainActor
final class SQLiteDatabase {
    private var db: OpaquePointer?

    var isOpen: Bool { db != nil }

    /// Open or create a database at the given file URL. Enables WAL mode.
    func open(at url: URL) throws {
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        var handle: OpaquePointer?
        let rc = sqlite3_open(url.path, &handle)
        guard rc == SQLITE_OK, let handle else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            throw SQLiteError.open(msg)
        }
        db = handle

        // Enable WAL mode for better concurrent read performance
        // journal_mode returns a result row, so use query instead of execute
        _ = try query("PRAGMA journal_mode=WAL")
        try execute("PRAGMA foreign_keys=ON")
    }

    /// Execute a SQL statement that returns no rows.
    @discardableResult
    func execute(_ sql: String, parameters: [SQLiteValue] = []) throws -> Int {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, parameters: parameters)

        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE else {
            throw SQLiteError.step(errorMessage)
        }
        return Int(sqlite3_changes(db))
    }

    /// Execute a SQL query and return all result rows.
    func query(_ sql: String, parameters: [SQLiteValue] = []) throws -> [[String: SQLiteValue]] {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, parameters: parameters)

        var rows: [[String: SQLiteValue]] = []
        let colCount = sqlite3_column_count(stmt)

        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: SQLiteValue] = [:]
            for i in 0..<colCount {
                let name = String(cString: sqlite3_column_name(stmt, i))
                row[name] = readColumn(stmt, index: i)
            }
            rows.append(row)
        }
        return rows
    }

    /// Execute multiple statements inside a transaction. Rolls back on error.
    func transaction(_ block: () throws -> Void) throws {
        try execute("BEGIN TRANSACTION")
        do {
            try block()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func close() {
        if let db {
            sqlite3_close(db)
        }
        db = nil
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    // MARK: - Private

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            throw SQLiteError.prepare(errorMessage)
        }
        return stmt
    }

    private func bind(_ stmt: OpaquePointer, parameters: [SQLiteValue]) throws {
        for (i, param) in parameters.enumerated() {
            let idx = Int32(i + 1)
            let rc: Int32
            switch param {
            case .null:
                rc = sqlite3_bind_null(stmt, idx)
            case .integer(let v):
                rc = sqlite3_bind_int64(stmt, idx, v)
            case .real(let v):
                rc = sqlite3_bind_double(stmt, idx, v)
            case .text(let v):
                rc = sqlite3_bind_text(stmt, idx, v, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .blob(let v):
                rc = v.withUnsafeBytes { ptr in
                    sqlite3_bind_blob(stmt, idx, ptr.baseAddress, Int32(v.count),
                                      unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            }
            guard rc == SQLITE_OK else {
                throw SQLiteError.bind(errorMessage)
            }
        }
    }

    private func readColumn(_ stmt: OpaquePointer, index: Int32) -> SQLiteValue {
        switch sqlite3_column_type(stmt, index) {
        case SQLITE_NULL:
            return .null
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(stmt, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(stmt, index))
        case SQLITE_TEXT:
            return .text(String(cString: sqlite3_column_text(stmt, index)))
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(stmt, index))
            if count > 0, let ptr = sqlite3_column_blob(stmt, index) {
                return .blob(Data(bytes: ptr, count: count))
            }
            return .blob(Data())
        default:
            return .null
        }
    }

    private var errorMessage: String {
        db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "database not open"
    }
}

// MARK: - Supporting Types

enum SQLiteValue: Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    var textValue: String? {
        if case .text(let v) = self { return v }
        return nil
    }

    var realValue: Double? {
        if case .real(let v) = self { return v }
        return nil
    }

    var integerValue: Int64? {
        if case .integer(let v) = self { return v }
        return nil
    }

    var blobValue: Data? {
        if case .blob(let v) = self { return v }
        return nil
    }
}

enum SQLiteError: LocalizedError {
    case open(String)
    case prepare(String)
    case bind(String)
    case step(String)

    var errorDescription: String? {
        switch self {
        case .open(let msg): return "SQLite open: \(msg)"
        case .prepare(let msg): return "SQLite prepare: \(msg)"
        case .bind(let msg): return "SQLite bind: \(msg)"
        case .step(let msg): return "SQLite step: \(msg)"
        }
    }
}
