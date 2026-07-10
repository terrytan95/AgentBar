import Foundation

enum UsageExportFormat: String, Sendable {
    case csv
    case json
}

struct UsageAuditPerformanceExportRow {
    var kind: String
    var date: Date
    var sessionID: String
    var sessionTitle: String
    var taskID: String?
    var taskTitle: String?
    var projectName: String?
    var models: String
    var reasoningEffort: String?
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var reasoningOutputTokens: Int
    var totalTokens: Int
    var durationMilliseconds: Double?
    var timeToFirstTokenMilliseconds: Double?
    var tokensPerSecond: Double?
    var estimatedCostUSD: Decimal?
}

enum UsageAuditReporter {
    static func exportRows(
        points: [UsagePoint],
        range: UsageRange,
        now: Date = Date(),
        calendar: Calendar = .current,
        customStart: Date? = nil,
        customEnd: Date? = nil
    ) -> [UsagePoint] {
        UsageRangeProjection.filteredPoints(points: points, range: range, now: now, calendar: calendar, customStart: customStart, customEnd: customEnd)
            .sorted { $0.date < $1.date }
    }

    static func serialize(rows: [UsagePoint], format: UsageExportFormat) -> String {
        switch format {
        case .csv:
            return serializeCSV(rows: rows)
        case .json:
            return serializeJSON(rows: rows)
        }
    }

    static func serialize(rows: [UsageAuditPerformanceExportRow], format: UsageExportFormat) -> String {
        switch format {
        case .csv:
            serializePerformanceCSV(rows: rows)
        case .json:
            serializePerformanceJSON(rows: rows)
        }
    }

    private static func serializeCSV(rows: [UsagePoint]) -> String {
        let header = "date,service,model,input_tokens,cached_input_tokens,output_tokens,reasoning_output_tokens,total_tokens,estimated_cost_usd"
        let body = rows.map { row in
            [
                iso8601String(from: row.date),
                row.service.rawValue,
                row.model,
                "\(row.tokens.input)",
                "\(row.tokens.cachedInput)",
                "\(row.tokens.output)",
                "\(row.tokens.reasoningOutput)",
                "\(row.tokens.total)",
                decimalString(row.estimatedCostUSD)
            ].map(csvEscape).joined(separator: ",")
        }
        return ([header] + body).joined(separator: "\n")
    }

    private static func serializeJSON(rows: [UsagePoint]) -> String {
        let payload = rows.map { row -> [String: Any] in
            [
                "date": iso8601String(from: row.date),
                "service": row.service.rawValue,
                "model": row.model,
                "input_tokens": row.tokens.input,
                "cached_input_tokens": row.tokens.cachedInput,
                "output_tokens": row.tokens.output,
                "reasoning_output_tokens": row.tokens.reasoningOutput,
                "total_tokens": row.tokens.total,
                "estimated_cost_usd": row.estimatedCostUSD.map(decimalString) as Any? ?? NSNull()
            ]
        }
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return text
    }

    private static func serializePerformanceCSV(rows: [UsageAuditPerformanceExportRow]) -> String {
        let header = "kind,date,session_id,session_title,task_id,task_title,project,models,reasoning_effort,input_tokens,cached_input_tokens,output_tokens,reasoning_output_tokens,total_tokens,duration_ms,time_to_first_token_ms,tps,estimated_cost_usd"
        let body = rows.map { row in
            [
                row.kind,
                iso8601String(from: row.date),
                row.sessionID,
                row.sessionTitle,
                row.taskID ?? "",
                row.taskTitle ?? "",
                row.projectName ?? "",
                row.models,
                row.reasoningEffort ?? "",
                "\(row.inputTokens)",
                "\(row.cachedInputTokens)",
                "\(row.outputTokens)",
                "\(row.reasoningOutputTokens)",
                "\(row.totalTokens)",
                doubleString(row.durationMilliseconds),
                doubleString(row.timeToFirstTokenMilliseconds),
                doubleString(row.tokensPerSecond),
                decimalString(row.estimatedCostUSD)
            ].map(csvEscape).joined(separator: ",")
        }
        return ([header] + body).joined(separator: "\n")
    }

    private static func serializePerformanceJSON(rows: [UsageAuditPerformanceExportRow]) -> String {
        let payload = rows.map { row -> [String: Any] in
            [
                "kind": row.kind,
                "date": iso8601String(from: row.date),
                "session_id": row.sessionID,
                "session_title": row.sessionTitle,
                "task_id": row.taskID as Any? ?? NSNull(),
                "task_title": row.taskTitle as Any? ?? NSNull(),
                "project": row.projectName as Any? ?? NSNull(),
                "models": row.models,
                "reasoning_effort": row.reasoningEffort as Any? ?? NSNull(),
                "input_tokens": row.inputTokens,
                "cached_input_tokens": row.cachedInputTokens,
                "output_tokens": row.outputTokens,
                "reasoning_output_tokens": row.reasoningOutputTokens,
                "total_tokens": row.totalTokens,
                "duration_ms": jsonDouble(row.durationMilliseconds),
                "time_to_first_token_ms": jsonDouble(row.timeToFirstTokenMilliseconds),
                "tps": jsonDouble(row.tokensPerSecond),
                "estimated_cost_usd": row.estimatedCostUSD.map(decimalString) as Any? ?? NSNull()
            ]
        }
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return text
    }

    private static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func decimalString(_ value: Decimal?) -> String {
        guard let value else { return "" }
        return String(format: "%.2f", NSDecimalNumber(decimal: value).doubleValue)
    }

    private static func doubleString(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func jsonDouble(_ value: Double?) -> Any {
        guard let value, value.isFinite else { return NSNull() }
        return value
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
