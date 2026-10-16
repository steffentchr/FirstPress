import Foundation
import PressingCore
import SQLite3

/// Plays in a SQLite database, one row per Play, keyed by its id.
///
/// SQLite rather than a JSON file or UserDefaults: History grows without end,
/// and a Play is saved at its start, at its end and as its scrobble status
/// moves on. Each save then writes one row instead of rewriting the whole
/// list, a crash mid-write can't lose what was already kept, and the system
/// library needs no dependency. The Play itself is stored as JSON, so new
/// fields need no schema change: `Play` decodes missing fields to defaults.
final class PlayDatabase {
    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    private var db: OpaquePointer?

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            let failure = Failure(description: db.map { String(cString: sqlite3_errmsg($0)) } ?? "can't open \(url.path)")
            sqlite3_close(db)
            db = nil
            throw failure
        }
        try execute("""
            PRAGMA journal_mode = WAL;
            CREATE TABLE IF NOT EXISTS plays (
                id TEXT PRIMARY KEY NOT NULL,
                started_at REAL NOT NULL,
                play BLOB NOT NULL
            );
            CREATE INDEX IF NOT EXISTS plays_started_at ON plays (started_at);
            CREATE TABLE IF NOT EXISTS scrobble_queue (
                position INTEGER PRIMARY KEY NOT NULL,
                play_id TEXT NOT NULL
            );
            """)
    }

    deinit {
        sqlite3_close(db)
    }

    /// Inserts the Play, or replaces the one with the same id.
    func save(_ play: Play) throws {
        let json = try JSONEncoder().encode(play)
        try withStatement("INSERT OR REPLACE INTO plays (id, started_at, play) VALUES (?, ?, ?)") { statement in
            sqlite3_bind_text(statement, 1, play.id.uuidString, -1, Self.transient)
            sqlite3_bind_double(statement, 2, play.startedAt.timeIntervalSince1970)
            _ = json.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 3, bytes.baseAddress, Int32(bytes.count), Self.transient)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
        }
    }

    /// Every Play, newest first. A row that no longer decodes is skipped.
    func all() throws -> [Play] {
        try withStatement("SELECT play FROM plays ORDER BY started_at DESC") { statement in
            var plays: [Play] = []
            let decoder = JSONDecoder()
            while true {
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE { break }
                guard step == SQLITE_ROW else { throw lastError() }
                let count = Int(sqlite3_column_bytes(statement, 0))
                guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
                if let play = try? decoder.decode(Play.self, from: Data(bytes: bytes, count: count)) {
                    plays.append(play)
                }
            }
            return plays
        }
    }

    /// Replaces the scrobble queue, in one transaction so a crash keeps
    /// either the old queue or the new one.
    func saveScrobbleQueue(_ queue: [UUID]) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("DELETE FROM scrobble_queue")
            for (position, id) in queue.enumerated() {
                try withStatement("INSERT INTO scrobble_queue (position, play_id) VALUES (?, ?)") { statement in
                    sqlite3_bind_int64(statement, 1, Int64(position))
                    sqlite3_bind_text(statement, 2, id.uuidString, -1, Self.transient)
                    guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
                }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// The scrobble queue, in order.
    func scrobbleQueue() throws -> [UUID] {
        try withStatement("SELECT play_id FROM scrobble_queue ORDER BY position") { statement in
            var queue: [UUID] = []
            while true {
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE { break }
                guard step == SQLITE_ROW else { throw lastError() }
                if let text = sqlite3_column_text(statement, 0), let id = UUID(uuidString: String(cString: text)) {
                    queue.append(id)
                }
            }
            return queue
        }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw lastError() }
    }

    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer?) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError() }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func lastError() -> Failure {
        Failure(description: String(cString: sqlite3_errmsg(db)))
    }

    /// SQLite copies bound values before the call returns.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
