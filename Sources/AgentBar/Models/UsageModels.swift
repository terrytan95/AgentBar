import Foundation

enum UsageService: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case codex = "Codex"
    case claudeCode = "Claude Code"

    var id: String { rawValue }
}

enum DataSourceStatus: String, Codable, Equatable, Sendable {
    case live
    case unavailable
    case needsAuthorization
    case error

    var label: String {
        label(language: .english)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .live: language == .chinese ? "正常" : "Live"
        case .unavailable: language == .chinese ? "不可用" : "Unavailable"
        case .needsAuthorization: language == .chinese ? "需授权" : "Needs auth"
        case .error: language == .chinese ? "错误" : "Error"
        }
    }
}

struct TokenTotals: Codable, Equatable, Sendable {
    var input: Int
    var cachedInput: Int
    var output: Int
    var reasoningOutput: Int
    var total: Int

    static let zero = TokenTotals(input: 0, cachedInput: 0, output: 0, reasoningOutput: 0, total: 0)

    static func + (lhs: TokenTotals, rhs: TokenTotals) -> TokenTotals {
        TokenTotals(
            input: lhs.input + rhs.input,
            cachedInput: lhs.cachedInput + rhs.cachedInput,
            output: lhs.output + rhs.output,
            reasoningOutput: lhs.reasoningOutput + rhs.reasoningOutput,
            total: lhs.total + rhs.total
        )
    }
}

struct UsageWindow: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case fiveHour
        case weekly
    }

    var id: Kind { kind }
    var kind: Kind
    var usedPercent: Double
    var windowMinutes: Int
    var resetsAt: Date?

    var remainingPercent: Double {
        max(0, 100 - usedPercent)
    }

    func resetLine(language: AppLanguage) -> String {
        guard let resetsAt else { return L.text("reset_time_unknown", language) }
        let timestamp = DisplayFormatters.shortDateTimeString(for: resetsAt, language: language)
        let relative = DisplayFormatters.relativeString(for: resetsAt, language: language)
        return "\(L.text("reset", language)): \(timestamp) (\(relative))"
    }
}

struct UsageResetCredit: Codable, Equatable, Sendable {
    var expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case expiresAt = "expires_at"
    }
}

struct UsageResetCredits: Codable, Equatable, Sendable {
    var availableCount: Int
    var resets: [UsageResetCredit] = []

    enum CodingKeys: String, CodingKey {
        case availableCount = "available_count"
        case resets
    }

    var visibleCount: Int {
        max(availableCount, resets.count)
    }

    var hasAvailableCredits: Bool {
        visibleCount > 0
    }

    func summaryLine(language: AppLanguage) -> String {
        let key = visibleCount == 1 ? "reset_available" : "resets_available"
        return "\(visibleCount) \(L.text(key, language))"
    }

    func expirationLines(language: AppLanguage) -> [String] {
        resets.enumerated().compactMap { index, reset in
            guard let expiresAt = reset.expiresAt else { return nil }
            let timestamp = DisplayFormatters.shortDateTimeString(for: expiresAt, language: language)
            let relative = DisplayFormatters.relativeString(for: expiresAt, language: language)
            return "\(L.text("reset", language)) \(index + 1) \(L.text("expires", language)): \(timestamp) (\(relative))"
        }
    }
}

enum UsageAccountLoginWarning: String, Codable, Equatable, Sendable {
    case forcedLogout
    case unreadableReset
}

struct UsageWorkspace: Codable, Equatable, Sendable {
    var name: String?
    var workspaceID: String?

    var displayValue: String? {
        let name = name.trimmedNonEmpty
        let id = workspaceID.trimmedNonEmpty.map(Self.shortWorkspaceID)
        let value = [name, id].compactMap { $0 }.joined(separator: " · ")
        return value.isEmpty ? nil : value
    }

    private static func shortWorkspaceID(_ id: String) -> String {
        id.count > 12 ? String(id.prefix(8)) : id
    }
}

struct UsageAccount: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var service: UsageService
    var displayName: String
    var username: String?
    var maskedEmail: String?
    var plan: String?
    var sourceDescription: String
    var status: DataSourceStatus
    var fiveHourWindow: UsageWindow?
    var weeklyWindow: UsageWindow?
    var resetCredits: UsageResetCredits? = nil
    var tokens: TokenTotals
    var estimatedCostUSD: Decimal?
    var lastUpdated: Date?
    var isActive: Bool
    var loginWarning: UsageAccountLoginWarning? = nil
    var workspaceName: String? = nil
    var workspaceID: String? = nil
    var workspaces: [UsageWorkspace] = []

    var mostConstrainedRemainingPercent: Double? {
        [fiveHourWindow?.remainingPercent, weeklyWindow?.remainingPercent]
            .compactMap { $0 }
            .min()
    }

    func accountTypeLine(language: AppLanguage) -> String {
        "\(L.text("account_type", language)): \(accountTypeValue(language: language))"
    }

    func lastActivityLine(language: AppLanguage) -> String {
        guard let lastUpdated else { return "\(L.text("last_activity", language)): --" }
        let timestamp = DisplayFormatters.shortDateTimeString(for: lastUpdated, language: language)
        let relative = DisplayFormatters.relativeString(for: lastUpdated, language: language)
        return "\(L.text("last_activity", language)): \(timestamp) (\(relative))"
    }

    var workspaceDisplayValue: String? {
        workspaceDisplayValues.first
    }

    var workspaceDisplayValues: [String] {
        let values = visibleWorkspaces.compactMap(\.displayValue)
        return values.isEmpty ? [] : values
    }

    func workspaceLine(language: AppLanguage) -> String? {
        workspaceLines(language: language).first
    }

    func workspaceLines(language: AppLanguage, limit: Int = 3) -> [String] {
        let values = Array(workspaceDisplayValues.prefix(limit))
        guard !values.isEmpty else { return [] }
        let label = workspaceDisplayValues.count > 1 ? L.text("workspaces", language) : L.text("workspace", language)
        var lines = values.enumerated().map { index, value in
            index == 0 ? "\(label): \(value)" : value
        }
        let hidden = workspaceDisplayValues.count - values.count
        if hidden > 0 {
            lines.append("+\(hidden) \(L.text("more", language))")
        }
        return lines
    }

    func displayNameWithWorkspace(language: AppLanguage) -> String {
        guard let workspaceDisplayValue, workspaceDisplayValue != displayName else { return displayName }
        return "\(displayName) · \(workspaceDisplayValue)"
    }

    var accountTypeValue: String {
        accountTypeValue(language: .english)
    }

    func accountTypeValue(language: AppLanguage) -> String {
        if let plan, !plan.isEmpty {
            return plan.uppercased()
        }
        let label = status.label(language: language)
        return language == .chinese ? label : label.uppercased()
    }

    var needsLogin: Bool {
        loginWarning != nil
    }

    func loginWarningLine(language: AppLanguage) -> String? {
        switch loginWarning {
        case .forcedLogout:
            L.text("account_forced_logout_warning", language)
        case .unreadableReset:
            L.text("account_unreadable_reset_warning", language)
        case nil:
            nil
        }
    }

    private var visibleWorkspaces: [UsageWorkspace] {
        if !workspaces.isEmpty { return workspaces }
        let legacy = UsageWorkspace(name: workspaceName, workspaceID: workspaceID)
        return legacy.displayValue == nil ? [] : [legacy]
    }
}

struct UsageAccountDisplayGroup: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var accounts: [UsageAccount]

    var isGrouped: Bool {
        accounts.count > 1
    }
}

private extension Optional where Wrapped == String {
    var trimmedNonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

extension Array where Element == UsageAccount {
    func sortedByActiveThenName() -> [UsageAccount] {
        sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive && !rhs.isActive
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    func sorted(using mode: AccountSortMode) -> [UsageAccount] {
        sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive && !rhs.isActive
            }
            switch mode {
            case .quotaPressure:
                if lhs.needsLogin != rhs.needsLogin { return !lhs.needsLogin }
                let lhsResetCredits = lhs.resetCredits?.visibleCount ?? 0
                let rhsResetCredits = rhs.resetCredits?.visibleCount ?? 0
                if lhsResetCredits != rhsResetCredits { return lhsResetCredits > rhsResetCredits }
                let lhsFive = lhs.fiveHourWindow?.remainingPercent ?? Double.greatestFiniteMagnitude
                let rhsFive = rhs.fiveHourWindow?.remainingPercent ?? Double.greatestFiniteMagnitude
                if lhsFive != rhsFive { return lhsFive < rhsFive }
                let lhsWeekly = lhs.weeklyWindow?.remainingPercent ?? Double.greatestFiniteMagnitude
                let rhsWeekly = rhs.weeklyWindow?.remainingPercent ?? Double.greatestFiniteMagnitude
                if lhsWeekly != rhsWeekly { return lhsWeekly < rhsWeekly }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            case .activeFirst:
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            case .alphabetical:
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        }
    }

    func displayGroupsByIdentity(sortMode: AccountSortMode) -> [UsageAccountDisplayGroup] {
        var groups: [String: [UsageAccount]] = [:]
        var orderedKeys: [String] = []
        for account in sorted(using: sortMode) {
            let key = account.identityGroupKey
            if groups[key] == nil {
                orderedKeys.append(key)
                groups[key] = []
            }
            groups[key]?.append(account)
        }

        return orderedKeys.compactMap { key in
            guard let accounts = groups[key], let first = accounts.first else { return nil }
            return UsageAccountDisplayGroup(id: key, title: first.displayName, accounts: accounts)
        }
    }
}

private extension UsageAccount {
    var identityGroupKey: String {
        let displayNameValue = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            service.rawValue,
            username.trimmedNonEmpty ?? maskedEmail.trimmedNonEmpty ?? (displayNameValue.isEmpty ? id : displayNameValue)
        ]
        .joined(separator: "|")
        .lowercased()
    }
}

struct UsageSnapshot: Codable, Equatable, Sendable {
    var service: UsageService
    var status: DataSourceStatus
    var accounts: [UsageAccount]
    var points: [UsagePoint]
    var securityNotes: [String]
    var refreshedAt: Date
    var pricingFingerprint: String

    static func empty(service: UsageService, status: DataSourceStatus, note: String) -> UsageSnapshot {
        UsageSnapshot(service: service, status: status, accounts: [], points: [], securityNotes: [note], refreshedAt: Date(), pricingFingerprint: Pricing.fingerprint)
    }
}

struct UsagePoint: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var service: UsageService
    var model: String
    var date: Date
    var tokens: TokenTotals
    var estimatedCostUSD: Decimal?
    var sessionID: String? = nil
    var sessionTitle: String? = nil
    var projectName: String? = nil
}

enum UsageRange: String, CaseIterable, Identifiable, Sendable {
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case thisYear
    case last7Days
    case last30Days
    case all
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: String(localized: "Today")
        case .yesterday: String(localized: "Yesterday")
        case .thisWeek: String(localized: "This Week")
        case .thisMonth: String(localized: "This Month")
        case .thisYear: String(localized: "This Year")
        case .last7Days: String(localized: "7 Days")
        case .last30Days: String(localized: "30 Days")
        case .all: String(localized: "All")
        case .custom: String(localized: "Custom")
        }
    }
}

extension UsageRange {
    func dateInterval(
        now: Date,
        calendar: Calendar,
        customStart: Date? = nil,
        customEnd: Date? = nil
    ) -> DateInterval? {
        switch self {
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

    func previousDateInterval(currentInterval: DateInterval, calendar: Calendar) -> DateInterval? {
        switch self {
        case .all:
            return nil
        case .thisWeek:
            guard let start = calendar.date(byAdding: .weekOfYear, value: -1, to: currentInterval.start) else { return nil }
            return DateInterval(start: start, end: currentInterval.start)
        case .thisMonth:
            guard let start = calendar.date(byAdding: .month, value: -1, to: currentInterval.start) else { return nil }
            return DateInterval(start: start, end: currentInterval.start)
        case .thisYear:
            guard let start = calendar.date(byAdding: .year, value: -1, to: currentInterval.start) else { return nil }
            return DateInterval(start: start, end: currentInterval.start)
        case .today, .yesterday, .last7Days, .last30Days, .custom:
            let duration = currentInterval.duration
            guard duration > 0 else { return nil }
            return DateInterval(start: currentInterval.start.addingTimeInterval(-duration), end: currentInterval.start)
        }
    }
}

struct UsageSummary: Equatable, Sendable {
    var totalTokens: Int
    var inputTokens: Int
    var outputTokens: Int
    var reasoningTokens: Int
    var estimatedCostUSD: Decimal?
    var serviceBreakdown: [UsageService: Int]
    var modelBreakdown: [String: Int]
    var dailyBars: [DailyUsageBar]
    var pricingFingerprint: String
}

struct UsagePeriodChange: Equatable, Sendable {
    var tokenPercent: Double?
    var costPercent: Double?
}

struct DailyUsageBar: Equatable, Identifiable, Sendable {
    var id: Date { day }
    var day: Date
    var codexTokens: Int
    var claudeTokens: Int

    func tooltipText(language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = language == .chinese ? Locale(identifier: "zh_Hans") : Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")

        let tokensLabel = L.text("tokens", language)
        let total = codexTokens + claudeTokens
        return [
            formatter.string(from: day),
            "Codex: \(DisplayFormatters.compactTokenString(codexTokens, language: language)) \(tokensLabel)",
            "Claude: \(DisplayFormatters.compactTokenString(claudeTokens, language: language)) \(tokensLabel)",
            "Total: \(DisplayFormatters.compactTokenString(total, language: language)) \(tokensLabel)"
        ].joined(separator: "\n")
    }
}

struct CodexSessionMetrics: Equatable, Sendable {
    var eventCount: Int
    var tokenTotals: TokenTotals
    var points: [UsagePoint]
    var latestFiveHour: UsageWindow?
    var latestWeekly: UsageWindow?
    var latestResetCredits: UsageResetCredits? = nil
    var latestRateLimitAt: Date?
}
