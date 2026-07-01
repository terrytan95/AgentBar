import Foundation

struct TokenComposition: Equatable, Sendable {
    var input: Int
    var cachedInput: Int
    var output: Int
    var reasoningOutput: Int
    var total: Int
}

struct UsageRecordExportRow: Equatable, Sendable {
    var date: Date
    var service: UsageService
    var model: String
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var reasoningOutputTokens: Int
    var totalTokens: Int
    var estimatedCostUSD: Decimal?
}

enum UsageExportFormat: String, CaseIterable, Sendable {
    case csv
    case json

    var fileExtension: String { rawValue }
}

enum UsageAuditReporter {
    static func tokenComposition(points: [UsagePoint]) -> TokenComposition {
        let totals = points.reduce(TokenTotals.zero) { $0 + $1.tokens }
        return TokenComposition(
            input: totals.input,
            cachedInput: totals.cachedInput,
            output: totals.output,
            reasoningOutput: totals.reasoningOutput,
            total: totals.total
        )
    }

    static func exportRows(
        points: [UsagePoint],
        range: UsageRange,
        now: Date = Date(),
        calendar: Calendar = .current,
        customStart: Date? = nil,
        customEnd: Date? = nil
    ) -> [UsageRecordExportRow] {
        filteredPoints(points: points, range: range, now: now, calendar: calendar, customStart: customStart, customEnd: customEnd)
            .sorted { $0.date < $1.date }
            .map { point in
                UsageRecordExportRow(
                    date: point.date,
                    service: point.service,
                    model: point.model,
                    inputTokens: point.tokens.input,
                    cachedInputTokens: point.tokens.cachedInput,
                    outputTokens: point.tokens.output,
                    reasoningOutputTokens: point.tokens.reasoningOutput,
                    totalTokens: point.tokens.total,
                    estimatedCostUSD: point.estimatedCostUSD
                )
            }
    }

    static func serialize(rows: [UsageRecordExportRow], format: UsageExportFormat) -> String {
        switch format {
        case .csv:
            return serializeCSV(rows: rows)
        case .json:
            return serializeJSON(rows: rows)
        }
    }

    static func filteredPoints(
        points: [UsagePoint],
        range: UsageRange,
        now: Date = Date(),
        calendar: Calendar = .current,
        customStart: Date? = nil,
        customEnd: Date? = nil
    ) -> [UsagePoint] {
        UsageRangeProjection.filteredPoints(
            points: points,
            range: range,
            now: now,
            calendar: calendar,
            customStart: customStart,
            customEnd: customEnd
        )
    }

    private static func serializeCSV(rows: [UsageRecordExportRow]) -> String {
        let header = "date,service,model,input_tokens,cached_input_tokens,output_tokens,reasoning_output_tokens,total_tokens,estimated_cost_usd"
        let body = rows.map { row in
            [
                iso8601String(from: row.date),
                row.service.rawValue,
                row.model,
                "\(row.inputTokens)",
                "\(row.cachedInputTokens)",
                "\(row.outputTokens)",
                "\(row.reasoningOutputTokens)",
                "\(row.totalTokens)",
                decimalString(row.estimatedCostUSD)
            ].map(csvEscape).joined(separator: ",")
        }
        return ([header] + body).joined(separator: "\n")
    }

    private static func serializeJSON(rows: [UsageRecordExportRow]) -> String {
        let payload = rows.map { row -> [String: Any] in
            [
                "date": iso8601String(from: row.date),
                "service": row.service.rawValue,
                "model": row.model,
                "input_tokens": row.inputTokens,
                "cached_input_tokens": row.cachedInputTokens,
                "output_tokens": row.outputTokens,
                "reasoning_output_tokens": row.reasoningOutputTokens,
                "total_tokens": row.totalTokens,
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
        return NSDecimalNumber(decimal: value).stringValue
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
