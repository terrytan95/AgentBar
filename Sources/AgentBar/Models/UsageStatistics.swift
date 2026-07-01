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
        UsageRangeProjection(
            points: points,
            range: range,
            now: now,
            calendar: calendar,
            customStart: customStart,
            customEnd: customEnd
        ).summary
    }

    static func periodChange(
        points: [UsagePoint],
        range: UsageRange,
        now: Date = Date(),
        calendar: Calendar = .current,
        customStart: Date? = nil,
        customEnd: Date? = nil
    ) -> UsagePeriodChange {
        UsageRangeProjection(
            points: points,
            range: range,
            now: now,
            calendar: calendar,
            customStart: customStart,
            customEnd: customEnd
        ).periodChange
    }

    static func yearActivityBars(
        points: [UsagePoint],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DailyUsageBar] {
        let endDay = calendar.startOfDay(for: now)
        guard
            let startDay = calendar.date(byAdding: .day, value: -364, to: endDay),
            let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay)
        else { return [] }

        let interval = DateInterval(start: startDay, end: endExclusive)
        let barsByDay = Dictionary(uniqueKeysWithValues: makeDailyBars(points: points.filter { interval.contains($0.date) }, calendar: calendar).map { ($0.day, $0) })

        return (0..<365).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else { return nil }
            return barsByDay[day] ?? DailyUsageBar(day: day, codexTokens: 0, claudeTokens: 0)
        }
    }

    static func summarizeFiltered(points filtered: [UsagePoint], calendar: Calendar) -> UsageSummary {
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

    static func percentChange(current: Int, previous: Int) -> Double? {
        guard previous > 0 else { return nil }
        return (Double(current - previous) / Double(previous)) * 100
    }

    static func percentChange(current: Decimal?, previous: Decimal?) -> Double? {
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
            let codexPoints = points.filter { $0.service == .codex }
            let claudePoints = points.filter { $0.service == .claudeCode }
            return DailyUsageBar(
                day: day,
                codexTokens: codexPoints.reduce(0) { $0 + $1.tokens.total },
                claudeTokens: claudePoints.reduce(0) { $0 + $1.tokens.total },
                codexCostUSD: codexPoints.compactMap(\.estimatedCostUSD).reduce(Decimal(0), +),
                claudeCostUSD: claudePoints.compactMap(\.estimatedCostUSD).reduce(Decimal(0), +)
            )
        }
    }
}
