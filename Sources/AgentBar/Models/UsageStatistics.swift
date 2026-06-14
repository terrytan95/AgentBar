import Foundation

enum UsageStatistics {
    static func summarize(
        points: [UsagePoint],
        range: UsageRange,
        now: Date = Date(),
        calendar: Calendar = .current,
        customStart: Date? = nil,
        customEnd: Date? = nil
    ) -> UsageSummary {
        let interval = dateInterval(for: range, now: now, calendar: calendar, customStart: customStart, customEnd: customEnd)
        let filtered = points.filter { point in
            guard let interval else { return true }
            return interval.contains(point.date)
        }

        let total = filtered.reduce(TokenTotals.zero) { $0 + $1.tokens }
        let costValues = filtered.compactMap(\.estimatedCostUSD)
        let cost = costValues.isEmpty ? nil : costValues.reduce(Decimal(0), +)
        let serviceBreakdown = Dictionary(grouping: filtered, by: \.service)
            .mapValues { $0.reduce(0) { $0 + $1.tokens.total } }
        let modelBreakdown = Dictionary(grouping: filtered, by: \.model)
            .mapValues { $0.reduce(0) { $0 + $1.tokens.total } }
        let dailyBars = makeDailyBars(points: filtered, calendar: calendar)

        return UsageSummary(
            totalTokens: total.total,
            inputTokens: total.input,
            outputTokens: total.output,
            reasoningTokens: total.reasoningOutput,
            estimatedCostUSD: cost,
            serviceBreakdown: serviceBreakdown,
            modelBreakdown: modelBreakdown,
            dailyBars: dailyBars,
            pricingFingerprint: Pricing.fingerprint
        )
    }

    private static func dateInterval(
        for range: UsageRange,
        now: Date,
        calendar: Calendar,
        customStart: Date?,
        customEnd: Date?
    ) -> DateInterval? {
        switch range {
        case .today:
            return calendar.dateInterval(of: .day, for: now)
        case .yesterday:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
            return calendar.dateInterval(of: .day, for: yesterday)
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)
        case .thisYear:
            return calendar.dateInterval(of: .year, for: now)
        case .last7Days:
            guard let start = calendar.date(byAdding: .day, value: -7, to: now) else { return nil }
            return DateInterval(start: start, end: now.addingTimeInterval(1))
        case .last30Days:
            guard let start = calendar.date(byAdding: .day, value: -30, to: now) else { return nil }
            return DateInterval(start: start, end: now.addingTimeInterval(1))
        case .all:
            return nil
        case .custom:
            guard let customStart, let customEnd else { return nil }
            return DateInterval(start: customStart, end: customEnd)
        }
    }

    private static func makeDailyBars(points: [UsagePoint], calendar: Calendar) -> [DailyUsageBar] {
        let grouped = Dictionary(grouping: points) { point in
            calendar.startOfDay(for: point.date)
        }

        return grouped.keys.sorted().map { day in
            let points = grouped[day, default: []]
            let codex = points.filter { $0.service == .codex }.reduce(0) { $0 + $1.tokens.total }
            let claude = points.filter { $0.service == .claudeCode }.reduce(0) { $0 + $1.tokens.total }
            return DailyUsageBar(day: day, codexTokens: codex, claudeTokens: claude)
        }
    }
}
