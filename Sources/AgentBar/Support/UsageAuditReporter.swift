import Foundation

enum UsageExportFormat: String, Sendable {
    case csv
    case json
}

enum UsageAuditReporter {
    static func tokenComposition(points: [UsagePoint]) -> TokenTotals {
        points.reduce(TokenTotals.zero) { $0 + $1.tokens }
    }

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
