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

    static func hourlyBars(points: [UsagePoint], range: UsageRange, now: Date = Date(), calendar: Calendar = .current) -> [DailyUsageBar] {
        guard range == .today || range == .yesterday,
              let interval = range.dateInterval(now: now, calendar: calendar)
        else { return [] }

        let grouped = Dictionary(grouping: points.filter { interval.contains($0.date) }) { point in
            calendar.dateInterval(of: .hour, for: point.date)?.start ?? point.date
        }

        let hourCount: Int
        if range == .today {
            let elapsedHours = calendar.dateComponents([.hour], from: interval.start, to: now).hour ?? 0
            hourCount = min(24, max(1, elapsedHours + 1))
        } else {
            hourCount = 24
        }

        return (0..<hourCount).compactMap { offset in
            guard let hour = calendar.date(byAdding: .hour, value: offset, to: interval.start) else { return nil }
            return makeBar(date: hour, points: grouped[hour, default: []])
        }
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
            makeBar(date: day, points: grouped[day, default: []])
        }
    }

    private static func makeBar(date: Date, points: [UsagePoint]) -> DailyUsageBar {
        let codexPoints = points.filter { $0.service == .codex }
        let claudePoints = points.filter { $0.service == .claudeCode }
        let xaiPoints = points.filter { $0.service == .xaiAPI }
        return DailyUsageBar(
            day: date,
            codexTokens: codexPoints.reduce(0) { $0 + $1.tokens.total },
            claudeTokens: claudePoints.reduce(0) { $0 + $1.tokens.total },
            xaiTokens: xaiPoints.reduce(0) { $0 + $1.tokens.total },
            codexCostUSD: codexPoints.compactMap(\.estimatedCostUSD).reduce(Decimal(0), +),
            claudeCostUSD: claudePoints.compactMap(\.estimatedCostUSD).reduce(Decimal(0), +),
            xaiCostUSD: xaiPoints.compactMap(\.estimatedCostUSD).reduce(Decimal(0), +)
        )
    }
}
