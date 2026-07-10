import Foundation

struct ProjectBudget: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var dailyTokenLimit: Int = 0
    var weeklyTokenLimit: Int = 0
    var dailyCostLimitUSD: Double = 0
    var weeklyCostLimitUSD: Double = 0

    var isConfigured: Bool {
        dailyTokenLimit > 0 || weeklyTokenLimit > 0 || dailyCostLimitUSD > 0 || weeklyCostLimitUSD > 0
    }
}

struct ProjectModelUsage: Equatable, Identifiable, Sendable {
    var id: String { model }
    var model: String
    var tokens: Int
    var estimatedCostUSD: Decimal?
}

struct ProjectUsageSummary: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var path: String?
    var summary: UsageSummary
    var periodChange: UsagePeriodChange
    var models: [ProjectModelUsage]
    var budget: ProjectBudget
    var budgetStatus: BudgetStatus
}

enum ProjectUsageAnalytics {
    static func summaries(
        points: [UsagePoint],
        range: UsageRange,
        customStart: Date? = nil,
        customEnd: Date? = nil,
        budgets: [ProjectBudget] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ProjectUsageSummary] {
        let currentPoints = UsageRangeProjection.filteredPoints(
            points: points,
            range: range,
            now: now,
            calendar: calendar,
            customStart: customStart,
            customEnd: customEnd
        )
        let currentGroups = Dictionary(grouping: currentPoints, by: projectID)
        let allGroups = Dictionary(grouping: points, by: projectID)
        let budgetsByID = budgets.reduce(into: [String: ProjectBudget]()) { result, budget in
            result[budget.id] = budget
        }

        return currentGroups.compactMap { id, visiblePoints in
            guard id != unknownProjectID else { return nil }
            let allProjectPoints = allGroups[id, default: visiblePoints]
            let projection = UsageRangeProjection(
                points: allProjectPoints,
                range: range,
                now: now,
                calendar: calendar,
                customStart: customStart,
                customEnd: customEnd
            )
            let sample = visiblePoints.first
            let path = sample?.repositoryPath ?? sample?.cwd
            let name = sample?.projectName?.trimmedNonEmpty
                ?? path.map { URL(fileURLWithPath: $0).lastPathComponent }
                ?? id
            let budget = budgetsByID[id] ?? ProjectBudget(id: id)
            let budgetStatus = budgetStatus(
                summary: projection.summary,
                range: range,
                budget: budget
            )

            return ProjectUsageSummary(
                id: id,
                name: name,
                path: path,
                summary: projection.summary,
                periodChange: projection.periodChange,
                models: modelUsage(points: visiblePoints),
                budget: budget,
                budgetStatus: budgetStatus
            )
        }
        .sorted { lhs, rhs in
            if lhs.summary.totalTokens != rhs.summary.totalTokens {
                return lhs.summary.totalTokens > rhs.summary.totalTokens
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func projectID(for point: UsagePoint) -> String {
        if let path = point.repositoryPath?.trimmedNonEmpty {
            return URL(fileURLWithPath: path).standardizedFileURL.path
        }
        if point.cwd == nil,
           let name = point.projectName?.trimmedNonEmpty {
            return "project:\(name.lowercased())"
        }
        return unknownProjectID
    }

    private static let unknownProjectID = "project:unknown"

    private static func modelUsage(points: [UsagePoint]) -> [ProjectModelUsage] {
        Dictionary(grouping: points, by: \UsagePoint.model)
            .map { model, modelPoints in
                let costs = modelPoints.compactMap(\.estimatedCostUSD)
                return ProjectModelUsage(
                    model: model,
                    tokens: modelPoints.reduce(0) { $0 + $1.tokens.total },
                    estimatedCostUSD: costs.isEmpty ? nil : costs.reduce(Decimal(0), +)
                )
            }
            .sorted { lhs, rhs in
                if lhs.tokens != rhs.tokens { return lhs.tokens > rhs.tokens }
                return lhs.model < rhs.model
            }
    }

    private static func budgetStatus(
        summary: UsageSummary,
        range: UsageRange,
        budget: ProjectBudget
    ) -> BudgetStatus {
        switch range {
        case .today:
            UsageInsights.budgetStatus(
                summary: summary,
                dailyTokenBudget: budget.dailyTokenLimit,
                dailyCostBudgetUSD: budget.dailyCostLimitUSD > 0 ? Decimal(budget.dailyCostLimitUSD) : nil
            )
        case .thisWeek:
            UsageInsights.budgetStatus(
                summary: summary,
                dailyTokenBudget: budget.weeklyTokenLimit,
                dailyCostBudgetUSD: budget.weeklyCostLimitUSD > 0 ? Decimal(budget.weeklyCostLimitUSD) : nil
            )
        default:
            UsageInsights.budgetStatus(summary: summary, dailyTokenBudget: 0, dailyCostBudgetUSD: nil)
        }
    }
}
