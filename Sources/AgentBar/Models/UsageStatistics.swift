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
        let interval = range.dateInterval(now: now, calendar: calendar, customStart: customStart, customEnd: customEnd)
        let filtered = points.filter { point in
            guard let interval else { return true }
            return interval.contains(point.date)
        }
        return summarize(points: filtered, calendar: calendar)
    }

    static func periodChange(
        points: [UsagePoint],
        range: UsageRange,
        now: Date = Date(),
        calendar: Calendar = .current,
        customStart: Date? = nil,
        customEnd: Date? = nil
    ) -> UsagePeriodChange {
        guard
            let currentInterval = range.dateInterval(now: now, calendar: calendar, customStart: customStart, customEnd: customEnd),
            let previousInterval = range.previousDateInterval(currentInterval: currentInterval, calendar: calendar)
        else {
            return UsagePeriodChange(tokenPercent: nil, costPercent: nil)
        }

        let current = summarize(points: points.filter { currentInterval.contains($0.date) }, calendar: calendar)
        let previous = summarize(points: points.filter { previousInterval.contains($0.date) }, calendar: calendar)
        return UsagePeriodChange(
            tokenPercent: percentChange(current: current.totalTokens, previous: previous.totalTokens),
            costPercent: percentChange(current: current.estimatedCostUSD, previous: previous.estimatedCostUSD)
        )
    }

    private static func summarize(points filtered: [UsagePoint], calendar: Calendar) -> UsageSummary {
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

    private static func percentChange(current: Int, previous: Int) -> Double? {
        guard previous > 0 else { return nil }
        return (Double(current - previous) / Double(previous)) * 100
    }

    private static func percentChange(current: Decimal?, previous: Decimal?) -> Double? {
        guard let current, let previous else { return nil }
        let currentValue = NSDecimalNumber(decimal: current).doubleValue
        let previousValue = NSDecimalNumber(decimal: previous).doubleValue
        guard previousValue > 0 else { return nil }
        return ((currentValue - previousValue) / previousValue) * 100
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
