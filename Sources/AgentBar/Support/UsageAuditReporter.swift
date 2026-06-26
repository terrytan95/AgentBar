import Foundation

struct AuditReport: Equatable, Sendable {
    var title: String
    var body: String
}

struct AuditBreakdownRow: Equatable, Identifiable, Sendable {
    var id: String { title }
    var title: String
    var subtitle: String
    var tokens: Int
    var share: Double
    var cost: Decimal?
}

struct TokenComposition: Equatable, Sendable {
    var input: Int
    var cachedInput: Int
    var output: Int
    var reasoningOutput: Int
    var total: Int
}

struct AuditRangeComparison: Equatable, Sendable {
    var currentTokens: Int
    var previousTokens: Int
    var tokenPercentChange: Double?
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

    static func serviceRows(points: [UsagePoint]) -> [AuditBreakdownRow] {
        breakdownRows(points: points, key: { $0.service.rawValue }, subtitle: { serviceName in
            serviceName == UsageService.codex.rawValue ? "OpenAI" : "Anthropic"
        })
    }

    static func modelRows(points: [UsagePoint]) -> [AuditBreakdownRow] {
        breakdownRows(points: points, key: \.model, subtitle: { _ in "Model" })
    }

    static func makeReport(
        points: [UsagePoint],
        range: UsageRange,
        budgetStatus: BudgetStatus?,
        dataSourceHealth: DataSourceHealthSummary,
        language: AppLanguage = .english,
        now: Date = Date(),
        calendar: Calendar = .current,
        customStart: Date? = nil,
        customEnd: Date? = nil
    ) -> AuditReport {
        let filtered = filteredPoints(points: points, range: range, now: now, calendar: calendar, customStart: customStart, customEnd: customEnd)
        let composition = tokenComposition(points: filtered)
        let topService = serviceRows(points: filtered).first
        let topModel = modelRows(points: filtered).first
        let comparison = rangeComparison(points: points, range: range, now: now, calendar: calendar, customStart: customStart, customEnd: customEnd)
        let anomalies = UsageInsights.usageAnomalies(points: points, now: now, calendar: calendar)
        let title = "\(reportTitlePrefix(for: range, language: language)) \(language == .chinese ? "用量报告" : "Usage Report")"

        var lines: [String]
        switch language {
        case .english:
            lines = [
                "\(title)",
                "Total: \(DisplayFormatters.tokenString(composition.total)) tokens.",
                "Top service: \(topService?.title ?? "N/A").",
                "Top model: \(topModel?.title ?? "N/A")."
            ]

            if let comparison, let change = comparison.tokenPercentChange {
                lines.append("Comparable range: \(DisplayFormatters.changePercentString(change)) versus \(DisplayFormatters.tokenString(comparison.previousTokens)) tokens previously.")
            } else {
                lines.append("Comparable range: not enough previous usage data.")
            }

            if let anomaly = anomalies.first {
                lines.append("Largest spike: \(anomaly.label) spike at \(DisplayFormatters.tokenString(anomaly.tokens)) tokens, \(String(format: "%.1fx", anomaly.multiple)) over baseline.")
            } else {
                lines.append("Largest spike: no spike detected.")
            }

            if let budgetStatus {
                lines.append("Budget: \(budgetSummary(status: budgetStatus, language: language)).")
            } else {
                lines.append("Budget: not configured for this range.")
            }

            lines.append("Data sources: \(dataSourceHealth.liveCount) live, \(dataSourceHealth.issueCount) issue\(dataSourceHealth.issueCount == 1 ? "" : "s").")
            lines.append("Basis: local parsed session logs and available rate-limit data, not official billing records.")
        case .chinese:
            lines = [
                "\(title)",
                "总量：\(DisplayFormatters.tokenString(composition.total)) Token。",
                "最高服务：\(topService?.title ?? "无")。",
                "最高模型：\(topModel?.title ?? "无")。"
            ]

            if let comparison, let change = comparison.tokenPercentChange {
                lines.append("可比区间：较此前 \(DisplayFormatters.tokenString(comparison.previousTokens)) Token \(DisplayFormatters.changePercentString(change))。")
            } else {
                lines.append("可比区间：此前用量数据不足。")
            }

            if let anomaly = anomalies.first {
                lines.append("最大异常：\(anomaly.label) 达到 \(DisplayFormatters.tokenString(anomaly.tokens)) Token，是基线的 \(String(format: "%.1f", anomaly.multiple)) 倍。")
            } else {
                lines.append("最大异常：未检测到异常增长。")
            }

            if let budgetStatus {
                lines.append("预算：\(budgetSummary(status: budgetStatus, language: language))。")
            } else {
                lines.append("预算：此范围未配置预算。")
            }

            lines.append("数据源：\(dataSourceHealth.liveCount) 个正常，\(dataSourceHealth.issueCount) 个问题。")
            lines.append("依据：本地已解析 session logs 和可用限额数据，不是官方账单记录。")
        }

        return AuditReport(title: title, body: lines.joined(separator: "\n"))
    }

    static func rangeComparison(
        points: [UsagePoint],
        range: UsageRange,
        now: Date = Date(),
        calendar: Calendar = .current,
        customStart: Date? = nil,
        customEnd: Date? = nil
    ) -> AuditRangeComparison? {
        guard
            let current = range.dateInterval(now: now, calendar: calendar, customStart: customStart, customEnd: customEnd),
            let previous = range.previousDateInterval(currentInterval: current, calendar: calendar)
        else { return nil }

        let currentTokens = points
            .filter { current.contains($0.date) }
            .reduce(0) { $0 + $1.tokens.total }
        let previousTokens = points
            .filter { previous.contains($0.date) }
            .reduce(0) { $0 + $1.tokens.total }
        return AuditRangeComparison(
            currentTokens: currentTokens,
            previousTokens: previousTokens,
            tokenPercentChange: percentChange(current: currentTokens, previous: previousTokens)
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
        guard let interval = range.dateInterval(now: now, calendar: calendar, customStart: customStart, customEnd: customEnd) else {
            return points
        }
        return points.filter { interval.contains($0.date) }
    }

    private static func breakdownRows(
        points: [UsagePoint],
        key: (UsagePoint) -> String,
        subtitle: (String) -> String
    ) -> [AuditBreakdownRow] {
        let total = max(1, points.reduce(0) { $0 + $1.tokens.total })
        return Dictionary(grouping: points, by: key)
            .map { title, points in
                let tokens = points.reduce(TokenTotals.zero) { $0 + $1.tokens }
                let costs = points.compactMap(\.estimatedCostUSD)
                return AuditBreakdownRow(
                    title: title,
                    subtitle: subtitle(title),
                    tokens: tokens.total,
                    share: Double(tokens.total) / Double(total),
                    cost: costs.isEmpty ? nil : costs.reduce(Decimal(0), +)
                )
            }
            .sorted { lhs, rhs in
                if lhs.tokens != rhs.tokens { return lhs.tokens > rhs.tokens }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
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

    private static func budgetSummary(status: BudgetStatus, language: AppLanguage) -> String {
        let severity: InsightSeverity
        if status.tokenSeverity == .critical || status.costSeverity == .critical {
            severity = .critical
        } else if status.tokenSeverity == .warning || status.costSeverity == .warning {
            severity = .warning
        } else {
            severity = .ok
        }
        return switch (severity, language) {
        case (.critical, .chinese): "超出预算"
        case (.warning, .chinese): "接近预算"
        case (.ok, .chinese): "正常"
        case (_, .english): severity.rawValue
        }
    }

    private static func reportTitlePrefix(for range: UsageRange, language: AppLanguage) -> String {
        guard language == .chinese else {
            switch range {
            case .today: return "Daily"
            case .thisWeek, .last7Days: return "Weekly"
            case .yesterday, .thisMonth, .thisYear, .last30Days, .all, .custom: return "Range"
            }
        }
        return switch range {
        case .today: "每日"
        case .thisWeek, .last7Days: "每周"
        case .yesterday, .thisMonth, .thisYear, .last30Days, .all, .custom: "区间"
        }
    }

    private static func percentChange(current: Int, previous: Int) -> Double? {
        guard previous > 0 else { return nil }
        return (Double(current - previous) / Double(previous)) * 100
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
