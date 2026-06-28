import Foundation
import SQLite3

struct CodexUsageIndexStore {
    var databaseURL: URL
    var fileManager: FileManager = .default

    static func defaultStore(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> CodexUsageIndexStore {
        CodexUsageIndexStore(databaseURL: homeDirectory.appending(path: ".agentbar/codex-usage.sqlite3"))
    }

    func replaceAll(points: [UsagePoint]) throws {
        try fileManager.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try withDatabase { db in
            try exec(db, Self.schemaSQL)
            try exec(db, "BEGIN IMMEDIATE")
            do {
                try exec(db, "DELETE FROM usage_events")
                let sql = """
                INSERT INTO usage_events (
                    record_id, session_id, thread_name, event_timestamp, source_file, source_line,
                    cwd, project_name, model, effort, initiator, input_tokens, cached_input_tokens,
                    uncached_input_tokens, output_tokens, reasoning_output_tokens, total_tokens,
                    estimated_cost_usd, model_context_window
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    throw error(db)
                }
                defer { sqlite3_finalize(statement) }
                for point in points where point.service == .codex {
                    bind(statement, 1, point.callID)
                    bind(statement, 2, point.sessionID)
                    bind(statement, 3, point.sessionTitle)
                    bind(statement, 4, Self.iso8601String(from: point.date))
                    bind(statement, 5, point.sourceFile)
                    bind(statement, 6, point.sourceLine)
                    bind(statement, 7, point.cwd)
                    bind(statement, 8, point.projectName)
                    bind(statement, 9, point.model)
                    bind(statement, 10, point.reasoningEffort)
                    bind(statement, 11, point.initiator)
                    bind(statement, 12, point.tokens.input)
                    bind(statement, 13, point.tokens.cachedInput)
                    bind(statement, 14, point.uncachedInputTokens)
                    bind(statement, 15, point.tokens.output)
                    bind(statement, 16, point.tokens.reasoningOutput)
                    bind(statement, 17, point.tokens.total)
                    bind(statement, 18, point.estimatedCostUSD.map { NSDecimalNumber(decimal: $0).doubleValue })
                    bind(statement, 19, point.modelContextWindow)
                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        throw error(db)
                    }
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                }
                try exec(db, "COMMIT")
            } catch {
                try? exec(db, "ROLLBACK")
                throw error
            }
        }
    }

    func summaryPayload(limit: Int = 20) throws -> [String: Any] {
        try withDatabase { db in
            try exec(db, Self.schemaSQL)
            let totals = try rows(
                db,
                """
                SELECT COUNT(*) AS calls,
                       COALESCE(SUM(total_tokens), 0) AS total_tokens,
                       COALESCE(SUM(cached_input_tokens), 0) AS cached_input_tokens,
                       COALESCE(SUM(uncached_input_tokens), 0) AS uncached_input_tokens,
                       COALESCE(SUM(output_tokens), 0) AS output_tokens,
                       COALESCE(SUM(reasoning_output_tokens), 0) AS reasoning_output_tokens,
                       COALESCE(SUM(estimated_cost_usd), 0) AS estimated_cost_usd
                FROM usage_events
                """
            ).first ?? [:]
            let threads = try rows(
                db,
                """
                SELECT COALESCE(thread_name, session_id, 'Unknown') AS thread,
                       COUNT(*) AS calls,
                       COALESCE(SUM(total_tokens), 0) AS total_tokens,
                       COALESCE(SUM(estimated_cost_usd), 0) AS estimated_cost_usd
                FROM usage_events
                GROUP BY COALESCE(thread_name, session_id, 'Unknown')
                ORDER BY total_tokens DESC
                LIMIT \(max(1, min(limit, 100)))
                """
            )
            return ["database": databaseURL.path, "totals": totals, "threads": threads]
        }
    }

    func sessionPayload(sessionID: String? = nil, limit: Int = 100) throws -> [[String: Any]] {
        try withDatabase { db in
            try exec(db, Self.schemaSQL)
            let normalizedLimit = max(1, min(limit, 500))
            if let sessionID, !sessionID.isEmpty {
                return try rows(
                    db,
                    """
                    SELECT * FROM usage_events
                    WHERE session_id = ?
                    ORDER BY event_timestamp DESC
                    LIMIT \(normalizedLimit)
                    """,
                    [sessionID]
                )
            }
            return try rows(
                db,
                """
                SELECT * FROM usage_events
                ORDER BY event_timestamp DESC
                LIMIT \(normalizedLimit)
                """
            )
        }
    }

    private static let schemaSQL = """
    CREATE TABLE IF NOT EXISTS usage_events (
        record_id TEXT PRIMARY KEY,
        session_id TEXT,
        thread_name TEXT,
        event_timestamp TEXT NOT NULL,
        source_file TEXT,
        source_line INTEGER,
        cwd TEXT,
        project_name TEXT,
        model TEXT NOT NULL,
        effort TEXT,
        initiator TEXT,
        input_tokens INTEGER NOT NULL,
        cached_input_tokens INTEGER NOT NULL,
        uncached_input_tokens INTEGER NOT NULL,
        output_tokens INTEGER NOT NULL,
        reasoning_output_tokens INTEGER NOT NULL,
        total_tokens INTEGER NOT NULL,
        estimated_cost_usd REAL,
        model_context_window INTEGER
    );
    CREATE INDEX IF NOT EXISTS idx_agentbar_usage_time ON usage_events(event_timestamp);
    CREATE INDEX IF NOT EXISTS idx_agentbar_usage_thread ON usage_events(thread_name);
    CREATE INDEX IF NOT EXISTS idx_agentbar_usage_session ON usage_events(session_id);
    CREATE INDEX IF NOT EXISTS idx_agentbar_usage_total ON usage_events(total_tokens);
    """

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let db else {
            throw CodexUsageIndexError.openFailed(databaseURL.path)
        }
        defer { sqlite3_close(db) }
        return try body(db)
    }

    private func exec(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw error(db)
        }
    }

    private func rows(_ db: OpaquePointer, _ sql: String, _ parameters: [String] = []) throws -> [[String: Any]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw error(db)
        }
        defer { sqlite3_finalize(statement) }
        for (index, parameter) in parameters.enumerated() {
            bind(statement, Int32(index + 1), parameter)
        }
        var output: [[String: Any]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    row[name] = Int(sqlite3_column_int64(statement, index))
                case SQLITE_FLOAT:
                    row[name] = sqlite3_column_double(statement, index)
                case SQLITE_TEXT:
                    row[name] = String(cString: sqlite3_column_text(statement, index))
                case SQLITE_NULL:
                    row[name] = NSNull()
                default:
                    row[name] = NSNull()
                }
            }
            output.append(row)
        }
        return output
    }

    private func error(_ db: OpaquePointer) -> Error {
        CodexUsageIndexError.sqlite(String(cString: sqlite3_errmsg(db)))
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: Int?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_int64(statement, index, sqlite3_int64(value))
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: Double?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_double(statement, index, value)
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private enum CodexUsageIndexError: LocalizedError {
    case openFailed(String)
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case let .openFailed(path): "Could not open usage index at \(path)."
        case let .sqlite(message): message
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
