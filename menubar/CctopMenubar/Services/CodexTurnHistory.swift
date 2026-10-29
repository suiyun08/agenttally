import Foundation
import SQLite3

/// Codex's own record of how each thread's latest turn ended. Codex sends no hook when the user
/// stops a turn, so this record is the only evidence that the turn is over.
protocol CodexTurnHistoryProviding {
    /// Thread ID → when its latest turn was interrupted, for the threads whose latest turn was.
    /// A thread Codex has no readable record for is left out.
    func latestInterruptedTurns(threadIDs: Set<String>) -> [String: Date]
}

/// Tests and previews: no turn history.
struct NoCodexTurnHistory: CodexTurnHistoryProviding {
    func latestInterruptedTurns(threadIDs: Set<String>) -> [String: Date] { [:] }
}

/// Reads `thread_turns` from the turn history database Codex keeps beside its thread state
/// database. Read-only; any failure reads as "no record".
struct CodexTurnHistoryLookup: CodexTurnHistoryProviding {
    static let databaseFilename = "thread_history_1.sqlite"

    /// Codex's thread state databases; the turn history sits in the same folder.
    let stateDatabasePaths: () -> [String]

    func latestInterruptedTurns(threadIDs: Set<String>) -> [String: Date] {
        guard !threadIDs.isEmpty else { return [:] }
        var result: [String: Date] = [:]
        for statePath in stateDatabasePaths() {
            let path = ((statePath as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent(Self.databaseFilename)
            guard FileManager.default.fileExists(atPath: path) else { continue }
            result.merge(Self.latestInterruptedTurns(at: path, threadIDs: threadIDs)) { first, _ in first }
        }
        return result
    }

    static func latestInterruptedTurns(at path: String, threadIDs: Set<String>) -> [String: Date] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database else {
            if database != nil { sqlite3_close(database) }
            return [:]
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 50)

        let ids = threadIDs.sorted()
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
        let sql = """
            SELECT thread_id, completed_at FROM thread_turns AS turn
            WHERE thread_id IN (\(placeholders))
              AND status = 'interrupted' AND completed_at IS NOT NULL
              AND rollout_ordinal = (SELECT MAX(rollout_ordinal) FROM thread_turns WHERE thread_id = turn.thread_id)
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [:] }
        defer { sqlite3_finalize(statement) }
        guard CodexThreadArchiveLookup.bind(ids, to: statement) else { return [:] }

        var result: [String: Date] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0) else { continue }
            // Codex stores turn times in whole seconds.
            result[String(cString: text)] = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 1)))
        }
        return result
    }
}
