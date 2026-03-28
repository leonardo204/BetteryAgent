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
                CREATE TABLE IF NOT EXISTS usage_patterns (
                    day_of_week INTEGER NOT NULL,
                    half_hour   INTEGER NOT NULL,
                    probability REAL DEFAULT 0.0,
                    observations INTEGER DEFAULT 0,
                    last_updated TEXT,
                    PRIMARY KEY (day_of_week, half_hour)
                );
                CREATE TABLE IF NOT EXISTS detected_patterns (
                    id          INTEGER PRIMARY KEY AUTOINCREMENT,
                    day_of_week INTEGER NOT NULL,
                    start_slot  INTEGER NOT NULL,
                    end_slot    INTEGER NOT NULL,
                    confidence  REAL NOT NULL,
                    active      INTEGER DEFAULT 1,
                    created_at  TEXT,
                    updated_at  TEXT
                );
                CREATE TABLE IF NOT EXISTS smart_charging_meta (
                    key   TEXT PRIMARY KEY,
                    value TEXT
                );
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

    // MARK: - Usage Patterns

    func loadUsagePatterns() -> [[UsageSlot]] {
        var result = Array(repeating: Array(repeating: UsageSlot(probability: 0, observations: 0), count: 48), count: 7)
        withDB { db in
            let sql = "SELECT day_of_week, half_hour, probability, observations FROM usage_patterns"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let day = Int(sqlite3_column_int(stmt, 0))
                let slot = Int(sqlite3_column_int(stmt, 1))
                let prob = sqlite3_column_double(stmt, 2)
                let obs = Int(sqlite3_column_int(stmt, 3))
                guard day >= 0 && day < 7 && slot >= 0 && slot < 48 else { continue }
                result[day][slot] = UsageSlot(probability: prob, observations: obs)
            }
        }
        return result
    }

    func upsertUsageSlot(day: Int, slot: Int, probability: Double, observations: Int) {
        withDB { db in
            let sql = """
                INSERT INTO usage_patterns (day_of_week, half_hour, probability, observations, last_updated)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(day_of_week, half_hour) DO UPDATE SET
                    probability = excluded.probability,
                    observations = excluded.observations,
                    last_updated = excluded.last_updated;
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            let now = ISO8601DateFormatter().string(from: Date())
            sqlite3_bind_int(stmt, 1, Int32(day))
            sqlite3_bind_int(stmt, 2, Int32(slot))
            sqlite3_bind_double(stmt, 3, probability)
            sqlite3_bind_int(stmt, 4, Int32(observations))
            sqlite3_bind_text(stmt, 5, (now as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
    }

    // MARK: - Detected Patterns

    func loadDetectedPatterns() -> [DetectedPattern] {
        var patterns: [DetectedPattern] = []
        withDB { db in
            let sql = "SELECT day_of_week, start_slot, end_slot, confidence, active FROM detected_patterns ORDER BY id ASC"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let day = Int(sqlite3_column_int(stmt, 0))
                let start = Int(sqlite3_column_int(stmt, 1))
                let end = Int(sqlite3_column_int(stmt, 2))
                let conf = sqlite3_column_double(stmt, 3)
                let active = sqlite3_column_int(stmt, 4) != 0
                patterns.append(DetectedPattern(dayOfWeek: day, startSlot: start, endSlot: end, confidence: conf, active: active))
            }
        }
        return patterns
    }

    func replaceDetectedPatterns(_ patterns: [DetectedPattern]) {
        withDB { db in
            sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
            sqlite3_exec(db, "DELETE FROM detected_patterns;", nil, nil, nil)
            let now = ISO8601DateFormatter().string(from: Date())
            let sql = "INSERT INTO detected_patterns (day_of_week, start_slot, end_slot, confidence, active, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)"
            for pattern in patterns {
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                    return
                }
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_int(stmt, 1, Int32(pattern.dayOfWeek))
                sqlite3_bind_int(stmt, 2, Int32(pattern.startSlot))
                sqlite3_bind_int(stmt, 3, Int32(pattern.endSlot))
                sqlite3_bind_double(stmt, 4, pattern.confidence)
                sqlite3_bind_int(stmt, 5, pattern.active ? 1 : 0)
                sqlite3_bind_text(stmt, 6, (now as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 7, (now as NSString).utf8String, -1, nil)
                if sqlite3_step(stmt) != SQLITE_DONE {
                    sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                    return
                }
            }
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        }
    }

    func clearSmartChargingData() {
        withDB { db in
            sqlite3_exec(db, "DELETE FROM usage_patterns;", nil, nil, nil)
            sqlite3_exec(db, "DELETE FROM detected_patterns;", nil, nil, nil)
            sqlite3_exec(db, "DELETE FROM smart_charging_meta;", nil, nil, nil)
        }
    }

    // MARK: - Meta

    func loadMeta(key: String) -> String? {
        withDB { db in
            let sql = "SELECT value FROM smart_charging_meta WHERE key = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            guard let cStr = sqlite3_column_text(stmt, 0) else { return nil }
            return String(cString: cStr)
        } ?? nil
    }

    func saveMeta(key: String, value: String) {
        withDB { db in
            let sql = "INSERT INTO smart_charging_meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (value as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
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
