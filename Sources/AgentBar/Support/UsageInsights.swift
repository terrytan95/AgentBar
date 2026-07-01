import Foundation

enum InsightSeverity: String, Equatable, Sendable {
    case ok
    case warning
    case critical
}

struct CurrentLimitSummary: Equatable, Sendable {
    var accountCount: Int
    var mostConstrainedAccount: UsageAccount?
    var lowestFiveHourRemaining: Double?
    var lowestWeeklyRemaining: Double?
}

struct QuotaPressureInsight: Equatable, Sendable {
    var severity: InsightSeverity
    var activeAccount: UsageAccount?
    var recommendedAccount: UsageAccount?
    var recommendationReason: String? = nil
    var projectedFiveHourExhaustion: Date?
    var projectedWeeklyExhaustion: Date?
    var shouldTriggerRotation: Bool
}

struct TopUsageBreakdown: Equatable, Sendable {
    var sessions: [TopUsageRow]
    var days: [TopUsageRow]
    var models: [TopUsageRow]
    var projects: [TopUsageRow]
}

struct TopUsageRow: Equatable, Identifiable, Sendable {
    var id: String { label }
    var label: String
    var tokens: Int
    var estimatedCostUSD: Decimal?
    var share: Double
    var lastUsedAt: Date?
}

struct RapidUsageAlert: Equatable, Sendable {
    var recentTokens: Int
    var todayTokens: Int
    var todayShare: Double
}

struct AccountHealthCenter: Equatable, Sendable {
    struct Row: Equatable, Identifiable, Sendable {
        enum Kind: Equatable, Sendable {
            case login
            case dataSource
        }

        var id: String
        var kind: Kind
        var title: String
        var detail: String
        var workspaceLines: [String] = []
        var accountID: String?
        var severity: InsightSeverity
    }

    var rows: [Row]
}

struct BudgetStatus: Equatable, Sendable {
    var tokenUsageFraction: Double?
    var costUsageFraction: Double?
    var tokenSeverity: InsightSeverity
    var costSeverity: InsightSeverity
}

struct DataSourceHealthSummary: Equatable, Sendable {
    struct Row: Equatable, Identifiable, Sendable {
        var id: UsageService { service }
        var service: UsageService
        var status: DataSourceStatus
        var note: String?
        var refreshedAt: Date
    }

    var rows: [Row]
    var liveCount: Int
    var issueCount: Int
}

enum UsageInsights {
    static func currentLimitSummary(accounts: [UsageAccount]) -> CurrentLimitSummary {
        let quotaAccounts = accounts.filter { $0.fiveHourWindow != nil || $0.weeklyWindow != nil }
        let constrained = quotaAccounts.min { lhs, rhs in
            (lhs.mostConstrainedRemainingPercent ?? .greatestFiniteMagnitude) <
                (rhs.mostConstrainedRemainingPercent ?? .greatestFiniteMagnitude)
        }

        return CurrentLimitSummary(
            accountCount: quotaAccounts.count,
            mostConstrainedAccount: constrained,
            lowestFiveHourRemaining: quotaAccounts.compactMap(\.fiveHourWindow?.remainingPercent).min(),
            lowestWeeklyRemaining: quotaAccounts.compactMap(\.weeklyWindow?.remainingPercent).min()
        )
    }

    static func quotaPressure(
        accounts: [UsageAccount],
        points: [UsagePoint],
        rotationThresholdRemainingPercent: Double,
        autoRotationEnabled: Bool,
        now: Date = Date()
    ) -> QuotaPressureInsight {
        let active = accounts.first(where: { $0.service == .codex && $0.isActive })
            ?? accounts.first(where: { $0.service == .codex })
        let bestAlternative = accounts
            .filter { $0.service == .codex && $0.id != active?.id }
            .filter { !$0.needsLogin }
            .max { lhs, rhs in
                let lhsResetCredits = lhs.resetCredits?.visibleCount ?? 0
                let rhsResetCredits = rhs.resetCredits?.visibleCount ?? 0
                if lhsResetCredits != rhsResetCredits {
                    return lhsResetCredits < rhsResetCredits
                }
                return (lhs.mostConstrainedRemainingPercent ?? -1) < (rhs.mostConstrainedRemainingPercent ?? -1)
            }

        let fiveHourRemaining = active?.fiveHourWindow?.remainingPercent
        let weeklyRemaining = active?.weeklyWindow?.remainingPercent
        let severity = severity(for: [fiveHourRemaining, weeklyRemaining].compactMap { $0 }.min())
        let recentTokens = points
            .filter { $0.service == .codex && now.timeIntervalSince($0.date) <= 60 * 60 }
            .reduce(0) { $0 + $1.tokens.total }
        let shouldProject = recentTokens > 0

        return QuotaPressureInsight(
            severity: severity,
            activeAccount: active,
            recommendedAccount: bestAlternative,
            recommendationReason: switchReason(active: active, recommended: bestAlternative),
            projectedFiveHourExhaustion: shouldProject ? projectedExhaustion(window: active?.fiveHourWindow, now: now) : nil,
            projectedWeeklyExhaustion: shouldProject ? projectedExhaustion(window: active?.weeklyWindow, now: now) : nil,
            shouldTriggerRotation: autoRotationEnabled && (fiveHourRemaining ?? 100) <= rotationThresholdRemainingPercent
        )
    }

    static func topUsage(
        points: [UsagePoint],
        now: Date = Date(),
        calendar: Calendar = .current,
        limit: Int = 3
    ) -> TopUsageBreakdown {
        let usable = points.filter { $0.date <= now }
        return TopUsageBreakdown(
            sessions: topRows(grouped: usable, limit: limit) { $0.sessionTitle ?? $0.sessionID ?? "Unknown session" },
            days: topRows(grouped: usable, limit: limit) { DisplayFormatters.shortDayString(for: calendar.startOfDay(for: $0.date)) },
            models: topRows(grouped: usable, limit: limit) { $0.model },
            projects: topRows(grouped: usable, limit: limit) { $0.projectName ?? "Other" }
        )
    }

    static func rapidUsageAlert(
        points: [UsagePoint],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> RapidUsageAlert? {
        let todayPoints = points.filter { calendar.isDate($0.date, inSameDayAs: now) }
        let todayTokens = todayPoints.reduce(0) { $0 + $1.tokens.total }
        let recentTokens = todayPoints
            .filter { now.timeIntervalSince($0.date) <= 10 * 60 }
            .reduce(0) { $0 + $1.tokens.total }
        guard todayTokens > 0 else { return nil }
        let share = Double(recentTokens) / Double(todayTokens)
        guard recentTokens >= 2_000, share >= 0.4 else { return nil }
        return RapidUsageAlert(recentTokens: recentTokens, todayTokens: todayTokens, todayShare: share)
    }

    static func budgetStatus(
        summary: UsageSummary,
        dailyTokenBudget: Int,
        dailyCostBudgetUSD: Decimal?
    ) -> BudgetStatus {
        let tokenFraction = dailyTokenBudget > 0 ? Double(summary.totalTokens) / Double(dailyTokenBudget) : nil
        let costFraction: Double?
        if let cost = summary.estimatedCostUSD,
           let dailyCostBudgetUSD,
           dailyCostBudgetUSD > 0 {
            costFraction = (cost as NSDecimalNumber).doubleValue / (dailyCostBudgetUSD as NSDecimalNumber).doubleValue
        } else {
            costFraction = nil
        }

        return BudgetStatus(
            tokenUsageFraction: tokenFraction,
            costUsageFraction: costFraction,
            tokenSeverity: severity(forUsageFraction: tokenFraction),
            costSeverity: severity(forUsageFraction: costFraction)
        )
    }

    static func dataSourceHealth(snapshots: [UsageService: UsageSnapshot]) -> DataSourceHealthSummary {
        let rows = snapshots.values.map { snapshot in
            DataSourceHealthSummary.Row(
                service: snapshot.service,
                status: snapshot.status,
                note: snapshot.securityNotes.first,
                refreshedAt: snapshot.refreshedAt
            )
        }
        .sorted { lhs, rhs in
            if lhs.status == rhs.status {
                return lhs.service.rawValue < rhs.service.rawValue
            }
            return lhs.status != .live && rhs.status == .live
        }

        return DataSourceHealthSummary(
            rows: rows,
            liveCount: rows.filter { $0.status == .live }.count,
            issueCount: rows.filter { $0.status != .live }.count
        )
    }

    static func accountHealthCenter(
        accounts: [UsageAccount],
        dataSourceHealth: DataSourceHealthSummary,
        language: AppLanguage
    ) -> AccountHealthCenter {
        let loginRows = accounts
            .filter(\.needsLogin)
            .map { account in
                AccountHealthCenter.Row(
                    id: "login-\(account.id)",
                    kind: .login,
                    title: account.displayName,
                    detail: account.loginWarningLine(language: language) ?? "",
                    workspaceLines: account.workspaceLines(language: language),
                    accountID: account.id,
                    severity: .warning
                )
            }
        let sourceRows = dataSourceHealth.rows
            .filter { $0.status != .live }
            .map { row in
                AccountHealthCenter.Row(
                    id: "source-\(row.service.rawValue)",
                    kind: .dataSource,
                    title: row.service.rawValue,
                    detail: row.note?.redactedForCredentialWords ?? row.status.label(language: language),
                    workspaceLines: [],
                    accountID: nil,
                    severity: .warning
                )
            }
        return AccountHealthCenter(rows: loginRows + sourceRows)
    }

    private static func severity(for remaining: Double?) -> InsightSeverity {
        guard let remaining else { return .ok }
        if remaining < 15 { return .critical }
        if remaining < 35 { return .warning }
        return .ok
    }

    private static func severity(forUsageFraction fraction: Double?) -> InsightSeverity {
        guard let fraction else { return .ok }
        if fraction >= 1 { return .critical }
        if fraction >= 0.8 { return .warning }
        return .ok
    }

    private static func projectedExhaustion(window: UsageWindow?, now: Date) -> Date? {
        guard let window,
              window.usedPercent > 0,
              window.remainingPercent < 35
        else { return nil }
        let remainingSeconds = Double(window.windowMinutes) * 60 * window.remainingPercent / max(1, window.usedPercent)
        let projected = now.addingTimeInterval(max(60, remainingSeconds))
        if let resetsAt = window.resetsAt {
            return min(projected, resetsAt)
        }
        return projected
    }

    private static func switchReason(active: UsageAccount?, recommended: UsageAccount?) -> String? {
        guard let active, let recommended else { return nil }
        let activeFive = DisplayFormatters.percentString(active.fiveHourWindow?.remainingPercent)
        let recommendedFive = DisplayFormatters.percentString(recommended.fiveHourWindow?.remainingPercent)
        let activeWeekly = DisplayFormatters.percentString(active.weeklyWindow?.remainingPercent)
        let recommendedWeekly = DisplayFormatters.percentString(recommended.weeklyWindow?.remainingPercent)
        let reset = recommended.fiveHourWindow?.resetsAt.map { ", resets \(DisplayFormatters.relativeString(for: $0, language: .english))" } ?? ""
        return "active 5H \(activeFive), weekly \(activeWeekly); \(recommended.displayName) 5H \(recommendedFive), weekly \(recommendedWeekly)\(reset)"
    }

    private static func topRows(
        grouped points: [UsagePoint],
        limit: Int,
        key: (UsagePoint) -> String
    ) -> [TopUsageRow] {
        let total = max(1, points.reduce(0) { $0 + $1.tokens.total })
        return Dictionary(grouping: points, by: key)
            .map { label, points in
                let tokens = points.reduce(0) { $0 + $1.tokens.total }
                return TopUsageRow(
                    label: label,
                    tokens: tokens,
                    estimatedCostUSD: totalCost(points),
                    share: Double(tokens) / Double(total),
                    lastUsedAt: points.map(\.date).max()
                )
            }
            .sorted {
                if $0.tokens != $1.tokens { return $0.tokens > $1.tokens }
                return $0.label < $1.label
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func totalCost(_ points: [UsagePoint]) -> Decimal? {
        let costs = points.compactMap(\.estimatedCostUSD)
        return costs.isEmpty ? nil : costs.reduce(Decimal(0), +)
    }
}
