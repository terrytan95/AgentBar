import Foundation

enum TokenEfficiencyConfidenceLevel: String, Sendable {
    case low
    case medium
    case high
}

struct TokenEfficiencyConfidence: Equatable, Sendable {
    var level: TokenEfficiencyConfidenceLevel
    var sampleSize: Int
    var minimumSampleSize: Int

    var meetsMinimum: Bool { sampleSize >= minimumSampleSize }
}

struct TokenEfficiencyScope: Equatable, Sendable {
    var service: UsageService
    var projectID: String?
    var projectName: String?
    var model: String?
    var reasoningEffort: String?
}

struct ContextBurnSession: Equatable, Identifiable, Sendable {
    var id: String
    var scope: TokenEfficiencyScope
    var sessionID: String
    var title: String?
    var latestInputTokens: Int
    var contextWindowTokens: Int
    var latestOccupancyRatio: Double
    var recentInputGrowthRatio: Double?
    var peakOccupancyRatio: Double
    var confidence: TokenEfficiencyConfidence
}

struct CacheHealthSession: Equatable, Identifiable, Sendable {
    var id: String
    var scope: TokenEfficiencyScope
    var sessionID: String
    var inputTokens: Int
    var cachedInputTokens: Int
    var uncachedInputTokens: Int
    var cacheRatio: Double
}

struct CacheHealthSummary: Equatable, Identifiable, Sendable {
    var id: String { service.id }
    var service: UsageService
    var inputTokens: Int?
    var cachedInputTokens: Int?
    var uncachedInputTokens: Int?
    var cacheRatio: Double?
    var personalBaselineRatio: Double?
    var sessions: [CacheHealthSession]
    var confidence: TokenEfficiencyConfidence
}

enum EfficiencyBaselineKind: String, Sendable {
    case personal
    case sameProject
}

struct SessionEfficiencyOutlier: Equatable, Identifiable, Sendable {
    var id: String
    var scope: TokenEfficiencyScope
    var sessionID: String
    var title: String?
    var uncachedInputTokens: Int
    var baselineUncachedInputTokens: Double
    var thresholdUncachedInputTokens: Double
    var baselineKind: EfficiencyBaselineKind
    var confidence: TokenEfficiencyConfidence
}

enum EfficiencyCoachInsightKind: String, Sendable {
    case contextPressure
    case cacheReuseExperiment
    case sessionOutlier
}

struct EfficiencyCoachInsight: Equatable, Identifiable, Sendable {
    var id: String
    var kind: EfficiencyCoachInsightKind
    var scope: TokenEfficiencyScope
    var sessionID: String?
    var measuredValue: Double
    var baselineValue: Double?
    var sampleSize: Int
    var confidence: TokenEfficiencyConfidence
}

struct TokenEfficiencyNudge: Equatable, Identifiable, Sendable {
    var id: String
    var sessionID: String
    var service: UsageService
    var contextOccupancyRatio: Double
    var thresholdBand: Int
    var confidence: TokenEfficiencyConfidence
}

enum TokenEfficiencyAnalytics {
    static let minimumCacheSessions = 6
    static let minimumOutlierBaseline = 8

    static func contextBurn(
        points: [UsagePoint],
        range: UsageRange = .all,
        customStart: Date? = nil,
        customEnd: Date? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ContextBurnSession] {
        let visible = UsageRangeProjection.filteredPoints(
            points: points,
            range: range,
            now: now,
            calendar: calendar,
            customStart: customStart,
            customEnd: customEnd
        )

        return groupedSessions(visible).compactMap { key, sessionPoints in
            let ordered = sessionPoints.sorted { $0.date < $1.date }
            guard let latest = ordered.last,
                  let window = latest.modelContextWindow,
                  window > 0
            else { return nil }

            let occupancy = ordered.compactMap { point -> Double? in
                guard let pointWindow = point.modelContextWindow, pointWindow > 0 else { return nil }
                return Double(point.tokens.input) / Double(pointWindow)
            }
            let recent = Array(ordered.suffix(4))
            let growth: Double? = if let first = recent.first, let last = recent.last, first.tokens.input > 0 {
                Double(last.tokens.input - first.tokens.input) / Double(first.tokens.input)
            } else {
                nil
            }

            return ContextBurnSession(
                id: key,
                scope: scope(for: latest),
                sessionID: latest.sessionID ?? key,
                title: ordered.reversed().compactMap { $0.sessionTitle?.trimmedNonEmpty }.first,
                latestInputTokens: latest.tokens.input,
                contextWindowTokens: window,
                latestOccupancyRatio: Double(latest.tokens.input) / Double(window),
                recentInputGrowthRatio: growth,
                peakOccupancyRatio: occupancy.max() ?? 0,
                confidence: confidence(sampleSize: ordered.count, minimum: 4)
            )
        }
        .sorted { $0.latestOccupancyRatio > $1.latestOccupancyRatio }
    }

    static func cacheHealth(
        points: [UsagePoint],
        range: UsageRange = .all,
        customStart: Date? = nil,
        customEnd: Date? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [CacheHealthSummary] {
        let visible = UsageRangeProjection.filteredPoints(
            points: points,
            range: range,
            now: now,
            calendar: calendar,
            customStart: customStart,
            customEnd: customEnd
        )
        let allSessions = cacheSessions(points)

        return Dictionary(grouping: visible, by: \.service).map { service, servicePoints in
            let usable = servicePoints.filter { $0.tokens.input > 0 }
            let input = usable.reduce(0) { $0 + $1.tokens.input }
            let cached = usable.reduce(0) { $0 + min($1.tokens.cachedInput, $1.tokens.input) }
            let sessions = cacheSessions(usable)
            let baseline = median(
                allSessions
                    .filter { $0.scope.service == service }
                    .map(\.cacheRatio)
            )
            return CacheHealthSummary(
                service: service,
                inputTokens: usable.isEmpty ? nil : input,
                cachedInputTokens: usable.isEmpty ? nil : cached,
                uncachedInputTokens: usable.isEmpty ? nil : max(0, input - cached),
                cacheRatio: input > 0 ? Double(cached) / Double(input) : nil,
                personalBaselineRatio: baseline,
                sessions: sessions.sorted { $0.cacheRatio < $1.cacheRatio },
                confidence: confidence(sampleSize: sessions.count, minimum: minimumCacheSessions)
            )
        }
        .sorted { $0.service.rawValue < $1.service.rawValue }
    }

    static func sessionOutliers(
        points: [UsagePoint],
        tasks: [AgentTask],
        range: UsageRange = .all,
        customStart: Date? = nil,
        customEnd: Date? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [SessionEfficiencyOutlier] {
        let visibleTasks = filteredTasks(
            tasks,
            range: range,
            customStart: customStart,
            customEnd: customEnd,
            now: now,
            calendar: calendar
        )
        let pointGroups = Dictionary(grouping: points.filter { $0.sessionID != nil }, by: { $0.sessionID! })
        let taskGroups = Dictionary(grouping: visibleTasks, by: \.sessionID)
        let samples = taskGroups.compactMap { sessionID, sessionTasks -> TaskSample? in
            guard sessionTasks.allSatisfy({ $0.state(at: now) == .completed }),
                  let sessionPoints = pointGroups[sessionID],
                  Set(sessionPoints.map(\.service)).count == 1,
                  let point = sessionPoints.first,
                  let task = sessionTasks.max(by: { $0.auditDate < $1.auditDate })
            else { return nil }
            let model = Set(sessionTasks.flatMap(\.models)).sorted().joined(separator: "+")
            let input = sessionPoints.reduce(0) { $0 + $1.tokens.input }
            let cached = sessionPoints.reduce(0) { $0 + min($1.tokens.cachedInput, $1.tokens.input) }
            return TaskSample(
                task: task,
                scope: scope(for: point, task: task),
                projectID: ProjectUsageAnalytics.projectID(for: point),
                model: model,
                uncachedInputTokens: max(0, input - cached)
            )
        }

        return samples.compactMap { sample in
            let cohort = samples.filter {
                $0.task.id != sample.task.id
                    && $0.scope.service == sample.scope.service
                    && $0.projectID == sample.projectID
                    && $0.model == sample.model
            }
            guard cohort.count >= minimumOutlierBaseline else { return nil }
            let values = cohort.map { Double($0.uncachedInputTokens) }
            let baseline = median(values) ?? 0
            let threshold = percentile(values, percentile: 0.95) ?? 0
            guard Double(sample.uncachedInputTokens) > threshold else { return nil }

            return SessionEfficiencyOutlier(
                id: sample.task.id,
                scope: sample.scope,
                sessionID: sample.task.sessionID,
                title: sample.task.title,
                uncachedInputTokens: sample.uncachedInputTokens,
                baselineUncachedInputTokens: baseline,
                thresholdUncachedInputTokens: threshold,
                baselineKind: .sameProject,
                confidence: confidence(sampleSize: cohort.count, minimum: minimumOutlierBaseline)
            )
        }
        .sorted { $0.uncachedInputTokens > $1.uncachedInputTokens }
    }

    static func coachInsights(
        points: [UsagePoint],
        tasks: [AgentTask],
        range: UsageRange = .all,
        customStart: Date? = nil,
        customEnd: Date? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [EfficiencyCoachInsight] {
        var insights = contextBurn(
            points: points,
            range: range,
            customStart: customStart,
            customEnd: customEnd,
            now: now,
            calendar: calendar
        ).filter {
            $0.confidence.meetsMinimum
                && $0.latestOccupancyRatio >= 0.70
                && ($0.recentInputGrowthRatio ?? 0) > 0
        }.map {
            EfficiencyCoachInsight(
                id: "context|\($0.id)",
                kind: .contextPressure,
                scope: $0.scope,
                sessionID: $0.sessionID,
                measuredValue: $0.latestOccupancyRatio,
                baselineValue: $0.recentInputGrowthRatio,
                sampleSize: $0.confidence.sampleSize,
                confidence: $0.confidence
            )
        }

        insights += cacheHealth(
            points: points,
            range: range,
            customStart: customStart,
            customEnd: customEnd,
            now: now,
            calendar: calendar
        ).compactMap { health in
            guard health.confidence.meetsMinimum,
                  let ratio = health.cacheRatio,
                  let baseline = health.personalBaselineRatio,
                  ratio + 0.10 < baseline
            else { return nil }
            return EfficiencyCoachInsight(
                id: "cache|\(health.service.id)",
                kind: .cacheReuseExperiment,
                scope: TokenEfficiencyScope(service: health.service),
                sessionID: nil,
                measuredValue: ratio,
                baselineValue: baseline,
                sampleSize: health.confidence.sampleSize,
                confidence: health.confidence
            )
        }

        insights += sessionOutliers(
            points: points,
            tasks: tasks,
            range: range,
            customStart: customStart,
            customEnd: customEnd,
            now: now,
            calendar: calendar
        ).map {
            EfficiencyCoachInsight(
                id: "outlier|\($0.id)",
                kind: .sessionOutlier,
                scope: $0.scope,
                sessionID: $0.sessionID,
                measuredValue: Double($0.uncachedInputTokens),
                baselineValue: $0.baselineUncachedInputTokens,
                sampleSize: $0.confidence.sampleSize,
                confidence: $0.confidence
            )
        }

        return insights.sorted {
            if $0.confidence.level != $1.confidence.level {
                return confidenceRank($0.confidence.level) > confidenceRank($1.confidence.level)
            }
            return $0.measuredValue > $1.measuredValue
        }
    }

    static func smartNudge(
        points: [UsagePoint],
        suppressedSessionIDs: Set<String> = [],
        deliveredBands: [String: Set<Int>] = [:]
    ) -> TokenEfficiencyNudge? {
        contextBurn(points: points)
            .filter {
                !suppressedSessionIDs.contains($0.sessionID)
                    && $0.confidence.meetsMinimum
                    && $0.latestOccupancyRatio >= 0.70
                    && ($0.recentInputGrowthRatio ?? 0) > 0
            }
            .compactMap { burn in
                let band = min(9, Int(burn.latestOccupancyRatio * 10))
                guard deliveredBands[burn.sessionID]?.contains(band) != true else { return nil }
                return TokenEfficiencyNudge(
                    id: "\(burn.sessionID)|\(band)",
                    sessionID: burn.sessionID,
                    service: burn.scope.service,
                    contextOccupancyRatio: burn.latestOccupancyRatio,
                    thresholdBand: band,
                    confidence: burn.confidence
                )
            }
            .max { $0.contextOccupancyRatio < $1.contextOccupancyRatio }
    }

    private struct TaskSample {
        var task: AgentTask
        var scope: TokenEfficiencyScope
        var projectID: String
        var model: String
        var uncachedInputTokens: Int
    }

    private static func groupedSessions(_ points: [UsagePoint]) -> [String: [UsagePoint]] {
        Dictionary(grouping: points.filter { $0.sessionID != nil }) {
            "\($0.service.rawValue)|\($0.sessionID!)"
        }
    }

    private static func cacheSessions(_ points: [UsagePoint]) -> [CacheHealthSession] {
        groupedSessions(points).compactMap { key, sessionPoints in
            guard let sample = sessionPoints.first else { return nil }
            let input = sessionPoints.reduce(0) { $0 + $1.tokens.input }
            guard input > 0 else { return nil }
            let cached = sessionPoints.reduce(0) { $0 + min($1.tokens.cachedInput, $1.tokens.input) }
            return CacheHealthSession(
                id: key,
                scope: scope(for: sample),
                sessionID: sample.sessionID ?? key,
                inputTokens: input,
                cachedInputTokens: cached,
                uncachedInputTokens: max(0, input - cached),
                cacheRatio: Double(cached) / Double(input)
            )
        }
    }

    private static func scope(for point: UsagePoint, task: AgentTask? = nil) -> TokenEfficiencyScope {
        let path = point.repositoryPath ?? point.cwd
        return TokenEfficiencyScope(
            service: point.service,
            projectID: ProjectUsageAnalytics.projectID(for: point),
            projectName: point.projectName?.trimmedNonEmpty
                ?? path.map { URL(fileURLWithPath: $0).lastPathComponent },
            model: task.map { $0.models.sorted().joined(separator: "+") } ?? point.model,
            reasoningEffort: task?.reasoningEffort ?? point.reasoningEffort
        )
    }

    private static func filteredTasks(
        _ tasks: [AgentTask],
        range: UsageRange,
        customStart: Date?,
        customEnd: Date?,
        now: Date,
        calendar: Calendar
    ) -> [AgentTask] {
        guard let interval = range.dateInterval(
            now: now,
            calendar: calendar,
            customStart: customStart,
            customEnd: customEnd
        ) else { return tasks }
        return tasks.filter { interval.contains($0.auditDate) }
    }

    private static func confidence(sampleSize: Int, minimum: Int) -> TokenEfficiencyConfidence {
        TokenEfficiencyConfidence(
            level: sampleSize >= minimum * 2 ? .high : sampleSize >= minimum ? .medium : .low,
            sampleSize: sampleSize,
            minimumSampleSize: minimum
        )
    }

    private static func median(_ values: [Double]) -> Double? {
        percentile(values, percentile: 0.5)
    }

    private static func percentile(_ values: [Double], percentile: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = max(0, min(sorted.count - 1, Int(ceil(Double(sorted.count) * percentile)) - 1))
        return sorted[index]
    }

    private static func confidenceRank(_ level: TokenEfficiencyConfidenceLevel) -> Int {
        switch level {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }
}
