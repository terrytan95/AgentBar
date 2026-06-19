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
        switch self {
        case .live: "Live"
        case .unavailable: "Unavailable"
        case .needsAuthorization: "Needs auth"
        case .error: "Error"
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
        let relative = DisplayFormatters.relativeString(for: resetsAt)
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
            let relative = DisplayFormatters.relativeString(for: expiresAt)
            return "\(L.text("reset", language)) \(index + 1) \(L.text("expires", language)): \(timestamp) (\(relative))"
        }
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

    var mostConstrainedRemainingPercent: Double? {
        [fiveHourWindow?.remainingPercent, weeklyWindow?.remainingPercent]
            .compactMap { $0 }
            .min()
    }

    func accountTypeLine(language: AppLanguage) -> String {
        "\(L.text("account_type", language)): \(accountTypeValue)"
    }

    func lastActivityLine(language: AppLanguage) -> String {
        guard let lastUpdated else { return "\(L.text("last_activity", language)): --" }
        let timestamp = DisplayFormatters.shortDateTimeString(for: lastUpdated, language: language)
        let relative = DisplayFormatters.relativeString(for: lastUpdated)
        return "\(L.text("last_activity", language)): \(timestamp) (\(relative))"
    }

    var accountTypeValue: String {
        if let plan, !plan.isEmpty {
            return plan.uppercased()
        }
        return status.label.uppercased()
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
