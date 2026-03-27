import Foundation
import SQLite3

final class ChargeHistoryStore: Sendable {
    static let shared = ChargeHistoryStore()

    private let dbPath: String

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("BatteryAgent", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        dbPath = appDir.appendingPathComponent("history.sqlite").path
        createTableIfNeeded()
    }

    private func withDB<T>(_ block: (OpaquePointer) throws -> T) rethrows -> T? {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK, let db else { return nil }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        return try block(db)
    }

    private func createTableIfNeeded() {
        withDB { db in
            let sql = """
                CREATE TABLE IF NOT EXISTS charge_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp INTEGER NOT NULL,
                    charge INTEGER NOT NULL,
                    is_charging INTEGER NOT NULL,
                    is_plugged_in INTEGER NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_timestamp ON charge_history(timestamp);
                """
            sqlite3_exec(db, sql, nil, nil, nil)
        }
    }

    func record(charge: Int, isCharging: Bool, isPluggedIn: Bool) {
        withDB { db in
            let sql = "INSERT INTO charge_history (timestamp, charge, is_charging, is_plugged_in) VALUES (?, ?, ?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            let now = Int64(Date().timeIntervalSince1970)
            sqlite3_bind_int64(stmt, 1, now)
            sqlite3_bind_int64(stmt, 2, Int64(charge))
            sqlite3_bind_int64(stmt, 3, isCharging ? 1 : 0)
            sqlite3_bind_int64(stmt, 4, isPluggedIn ? 1 : 0)
            sqlite3_step(stmt)
        }
    }

    func fetchRecords(hours: Int) -> [ChargeRecord] {
        withDB { db in
            let cutoff = Int(Date().timeIntervalSince1970) - (hours * 3600)
            let sql = "SELECT timestamp, charge, is_charging, is_plugged_in FROM charge_history WHERE timestamp > ? ORDER BY timestamp ASC"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, Int64(cutoff))
            var records: [ChargeRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let ts = Double(sqlite3_column_int(stmt, 0))
                let charge = Int(sqlite3_column_int(stmt, 1))
                let charging = sqlite3_column_int(stmt, 2) == 1
                let pluggedIn = sqlite3_column_int(stmt, 3) == 1
                records.append(ChargeRecord(
                    timestamp: Date(timeIntervalSince1970: ts),
                    charge: charge,
                    isCharging: charging,
                    isPluggedIn: pluggedIn
                ))
            }
            return records
        } ?? []
    }

    func pruneOldRecords() {
        withDB { db in
            let cutoff = Int(Date().timeIntervalSince1970) - (Constants.historyRetentionDays * 24 * 3600)
            let sql = "DELETE FROM charge_history WHERE timestamp < ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, Int64(cutoff))
            sqlite3_step(stmt)
        }
    }
}
