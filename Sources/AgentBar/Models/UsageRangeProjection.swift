import Foundation

struct UsageRangeProjection {
    let points: [UsagePoint]
    let range: UsageRange
    let now: Date
    let calendar: Calendar
    let customStart: Date?
    let customEnd: Date?
    let rangePoints: [UsagePoint]

    init(
        points: [UsagePoint],
        range: UsageRange,
        now: Date = Date(),
        calendar: Calendar = .current,
        customStart: Date? = nil,
        customEnd: Date? = nil
    ) {
        self.points = points
        self.range = range
        self.now = now
        self.calendar = calendar
        self.customStart = customStart
        self.customEnd = customEnd
        self.rangePoints = Self.filteredPoints(
            points: points,
            range: range,
            now: now,
            calendar: calendar,
            customStart: customStart,
            customEnd: customEnd
        )
    }

    var summary: UsageSummary {
        UsageStatistics.summarizeFiltered(points: rangePoints, calendar: calendar)
    }

    var periodChange: UsagePeriodChange {
        guard
            let currentInterval = range.dateInterval(now: now, calendar: calendar, customStart: customStart, customEnd: customEnd),
            let previousInterval = range.previousDateInterval(currentInterval: currentInterval, calendar: calendar)
        else {
            return UsagePeriodChange(tokenPercent: nil, costPercent: nil)
        }

        let current = UsageStatistics.summarizeFiltered(points: points.filter { currentInterval.contains($0.date) }, calendar: calendar)
        let previous = UsageStatistics.summarizeFiltered(points: points.filter { previousInterval.contains($0.date) }, calendar: calendar)
        return UsagePeriodChange(
            tokenPercent: UsageStatistics.percentChange(current: current.totalTokens, previous: previous.totalTokens),
            costPercent: UsageStatistics.percentChange(current: current.estimatedCostUSD, previous: previous.estimatedCostUSD)
        )
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

    static func displayPoints(
        _ points: [UsagePoint],
        showAggregatedAccountData: Bool,
        activeService: UsageService?
    ) -> [UsagePoint] {
        guard !showAggregatedAccountData, let activeService else {
            return points
        }
        return points.filter { $0.service == activeService }
    }
}
