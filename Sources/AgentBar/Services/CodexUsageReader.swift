import Foundation

enum UsageReadError: Error {
    case invalidRegistry
}

struct CodexUsageReader {
    var homeDirectory: URL
    var fileManager: FileManager = .default
    static let maximumSessionFileBytes = 10 * 1024 * 1024
    static let maximumSessionFiles = 1_000
    private static let sessionMetricsCache = CodexSessionMetricsCache()

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    func read() -> UsageSnapshot {
        let now = Date()
        let registryURL = homeDirectory.appending(path: ".codex/accounts/registry.json")
        var accounts: [UsageAccount] = []
        var points: [UsagePoint] = []
        var activeAccountActivatedAt: Date?
        var notes = [
            "AgentBar reads the local Codex registry and usage JSONL; auth snapshots are read only for usage API refresh."
        ]

        if let data = try? Data(contentsOf: registryURL),
           let registryDetails = try? Self.parseRegistryDetails(data: data, now: now) {
            accounts = registryDetails.snapshot.accounts
            activeAccountActivatedAt = registryDetails.activeAccountActivatedAt
            notes.append(contentsOf: registryDetails.snapshot.securityNotes)
        } else {
            notes.append("Codex registry not found at ~/.codex/accounts/registry.json.")
        }

        let sessionRoot = homeDirectory.appending(path: ".codex/sessions")
        let metrics = readSessionMetrics(root: sessionRoot)
        points.append(contentsOf: metrics.points)

        if !accounts.isEmpty {
            accounts = accounts.map { account in
                var account = account
                let canUseSessionRateLimitsForActiveAccount = Self.canUseSessionRateLimits(
                    for: account,
                    activeAccountActivatedAt: activeAccountActivatedAt,
                    latestRateLimitAt: metrics.latestRateLimitAt
                )
                if account.fiveHourWindow == nil,
                   (canUseSessionRateLimitsForActiveAccount || !account.isActive),
                   let latestFiveHour = metrics.latestFiveHour {
                    account.fiveHourWindow = latestFiveHour
                }
                if account.weeklyWindow == nil,
                   (canUseSessionRateLimitsForActiveAccount || !account.isActive),
                   let latestWeekly = metrics.latestWeekly {
                    account.weeklyWindow = latestWeekly
                }
                if account.resetCredits == nil,
                   (canUseSessionRateLimitsForActiveAccount || !account.isActive) {
                    account.resetCredits = metrics.latestResetCredits
                }
                if account.tokens.total == 0 {
                    account.tokens = metrics.tokenTotals
                }
                account.lastUpdated = account.lastUpdated ?? metrics.latestRateLimitAt ?? now
                return account
            }
        }

        let status: DataSourceStatus = accounts.isEmpty && metrics.eventCount == 0 ? .unavailable : .live
        return UsageSnapshot(
            service: .codex,
            status: status,
            accounts: accounts,
            points: points,
            securityNotes: notes,
            refreshedAt: now,
            pricingFingerprint: Pricing.fingerprint
        )
    }

    static func parseRegistry(data: Data, now: Date) throws -> UsageSnapshot {
        try parseRegistryDetails(data: data, now: now).snapshot
    }

    private static func parseRegistryDetails(data: Data, now: Date) throws -> (snapshot: UsageSnapshot, activeAccountActivatedAt: Date?) {
        let registry = try JSONDecoder().decode(CodexRegistry.self, from: data)
        let accounts = registry.accounts.map { raw in
            let username = firstNonEmptyOptional([raw.email, raw.accountName, raw.alias])
            let displayName = username ?? "Codex Account"
            let primary = raw.lastUsage?.primary.map {
                UsageWindow(kind: .fiveHour, usedPercent: $0.usedPercent, windowMinutes: $0.windowMinutes, resetsAt: epochDate($0.resetsAt))
            }
            let secondary = raw.lastUsage?.secondary.map {
                UsageWindow(kind: .weekly, usedPercent: $0.usedPercent, windowMinutes: $0.windowMinutes, resetsAt: epochDate($0.resetsAt))
            }
            let resetCredits = raw.lastUsage?.resetCredits?.toUsageResetCredits()
            let loginWarning: UsageAccountLoginWarning? =
                raw.hasForcedLogoutWarning ? .forcedLogout :
                raw.lastUsage?.hasUnreadableResetWarning == true ? .unreadableReset :
                nil

            return UsageAccount(
                id: raw.accountKey,
                service: .codex,
                displayName: displayName,
                username: username,
                maskedEmail: maskEmail(raw.email),
                plan: raw.plan ?? raw.lastUsage?.planType,
                sourceDescription: "Local Codex account registry",
                status: .live,
                fiveHourWindow: primary,
                weeklyWindow: secondary,
                resetCredits: resetCredits,
                tokens: .zero,
                estimatedCostUSD: nil,
                lastUpdated: epochDate(raw.lastUsageAt) ?? now,
                isActive: raw.accountKey == registry.activeAccountKey,
                loginWarning: loginWarning
            )
        }

        let snapshot = UsageSnapshot(
            service: .codex,
            status: accounts.isEmpty ? .unavailable : .live,
            accounts: accounts,
            points: [],
            securityNotes: ["Parsed account metadata only; credential auth files are excluded."],
            refreshedAt: now,
            pricingFingerprint: Pricing.fingerprint
        )
        return (snapshot, epochMillisecondsDate(registry.activeAccountActivatedAtMs))
    }

    static func parseSessionJsonl(data: Data) throws -> CodexSessionMetrics {
        var eventCount = 0
        var latestTotal = TokenTotals.zero
        var points: [UsagePoint] = []
        var fiveHour: UsageWindow?
        var weekly: UsageWindow?
        var resetCredits: UsageResetCredits?
        var latestRateLimitAt: Date?
        var currentCumulativeResetAt: Date?
        var previousCumulativeUsage: TokenTotals?
        var previousCumulativeResetAt: Date?
        let decoder = JSONDecoder()
        let dateParser = CodexTimestampParser()

        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            guard let event = try? decoder.decode(CodexSessionEvent.self, from: Data(line))
            else { continue }

            guard let payload = event.payload else { continue }
            let parsedEventDate = event.parsedDate(using: dateParser)
            let eventDate = parsedEventDate ?? .distantPast
            if let resetAt = payload.rateLimits?.primary?.resetDate ?? payload.rateLimits?.secondary?.resetDate {
                currentCumulativeResetAt = resetAt
            }
            if let info = payload.info,
               let pointUsage = Self.pointUsage(
                from: info,
                previousCumulativeUsage: previousCumulativeResetAt == currentCumulativeResetAt ? previousCumulativeUsage : nil
               ) {
                let cumulativeTotals = info.totalTokenUsage?.toTotals()
                latestTotal = cumulativeTotals ?? pointUsage
                if let cumulativeTotals {
                    previousCumulativeUsage = cumulativeTotals
                    previousCumulativeResetAt = currentCumulativeResetAt
                }
                eventCount += 1
                let model = info.model ?? "Codex local"
                points.append(
                    UsagePoint(
                        service: .codex,
                        model: model,
                        date: eventDate,
                        tokens: pointUsage,
                        estimatedCostUSD: Pricing.cost(model: model, tokens: pointUsage)
                    )
                )
            }

            if let parsedEventDate,
               payload.rateLimits != nil || payload.resetCredits != nil,
               latestRateLimitAt == nil || parsedEventDate >= (latestRateLimitAt ?? .distantPast) {
                if let primary = payload.rateLimits?.primary {
                    fiveHour = UsageWindow(kind: .fiveHour, usedPercent: primary.usedPercent, windowMinutes: primary.windowMinutes, resetsAt: epochDate(primary.resetsAt))
                }
                if let secondary = payload.rateLimits?.secondary {
                    weekly = UsageWindow(kind: .weekly, usedPercent: secondary.usedPercent, windowMinutes: secondary.windowMinutes, resetsAt: epochDate(secondary.resetsAt))
                }
                if let sessionResetCredits = payload.resetCredits {
                    resetCredits = sessionResetCredits.toUsageResetCredits()
                }
                latestRateLimitAt = parsedEventDate
            }
        }

        return CodexSessionMetrics(eventCount: eventCount, tokenTotals: latestTotal, points: points, latestFiveHour: fiveHour, latestWeekly: weekly, latestResetCredits: resetCredits, latestRateLimitAt: latestRateLimitAt)
    }

    private static func pointUsage(
        from info: CodexInfo,
        previousCumulativeUsage: TokenTotals?
    ) -> TokenTotals? {
        if let lastTokenUsage = info.lastTokenUsage {
            return lastTokenUsage.toTotals()
        }
        guard let cumulativeUsage = info.totalTokenUsage?.toTotals() else { return nil }
        return cumulativeDelta(from: cumulativeUsage, previous: previousCumulativeUsage)
    }

    private static func cumulativeDelta(from current: TokenTotals, previous: TokenTotals?) -> TokenTotals {
        guard let previous, current.total >= previous.total else { return current }
        return TokenTotals(
            input: max(0, current.input - previous.input),
            cachedInput: max(0, current.cachedInput - previous.cachedInput),
            output: max(0, current.output - previous.output),
            reasoningOutput: max(0, current.reasoningOutput - previous.reasoningOutput),
            total: current.total - previous.total
        )
    }

    private func readSessionMetrics(root: URL) -> CodexSessionMetrics {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return CodexSessionMetrics(eventCount: 0, tokenTotals: .zero, points: [], latestFiveHour: nil, latestWeekly: nil, latestRateLimitAt: nil)
        }

        var aggregate = CodexSessionMetrics(eventCount: 0, tokenTotals: .zero, points: [], latestFiveHour: nil, latestWeekly: nil, latestRateLimitAt: nil)
        var livePaths = Set<String>()
        var reviewedFileCount = 0

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            guard let signature = CodexSessionFileSignature(fileURL: fileURL) else { continue }
            guard signature.size <= Self.maximumSessionFileBytes else { continue }
            guard reviewedFileCount < Self.maximumSessionFiles else { break }
            reviewedFileCount += 1
            let path = fileURL.path
            livePaths.insert(path)
            let metrics: CodexSessionMetrics
            if let cachedMetrics = Self.sessionMetricsCache.metrics(for: path, signature: signature) {
                metrics = cachedMetrics
            } else {
                guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
                      let parsedMetrics = try? Self.parseSessionJsonl(data: data)
                else { continue }
                metrics = parsedMetrics
                Self.sessionMetricsCache.store(metrics, for: path, signature: signature)
            }

            aggregate.merge(metrics)
        }
        Self.sessionMetricsCache.retain(paths: livePaths)

        return aggregate
    }

    static func resetSessionMetricsCacheForTesting() {
        sessionMetricsCache.removeAll()
    }

    private static func canUseSessionRateLimits(
        for account: UsageAccount,
        activeAccountActivatedAt: Date?,
        latestRateLimitAt: Date?
    ) -> Bool {
        guard account.isActive else { return false }
        guard let activeAccountActivatedAt else { return true }
        guard let latestRateLimitAt else { return false }
        return latestRateLimitAt >= activeAccountActivatedAt
    }
}

private struct CodexRegistry: Decodable {
    var activeAccountKey: String?
    var activeAccountActivatedAtMs: Double?
    var accounts: [CodexRegistryAccount]

    enum CodingKeys: String, CodingKey {
        case activeAccountKey = "active_account_key"
        case activeAccountActivatedAtMs = "active_account_activated_at_ms"
        case accounts
    }
}

private struct CodexRegistryAccount: Decodable {
    var accountKey: String
    var accountName: String?
    var alias: String?
    var email: String?
    var plan: String?
    var lastUsage: CodexLastUsage?
    var lastUsageAt: Double?
    var authError: CodexAuthError?

    enum CodingKeys: String, CodingKey {
        case accountKey = "account_key"
        case accountName = "account_name"
        case alias
        case email
        case plan
        case lastUsage = "last_usage"
        case lastUsageAt = "last_usage_at"
        case authError = "agentbar_auth_error"
    }

    var hasForcedLogoutWarning: Bool {
        authError?.statusCode == 401 || plan == "401" || lastUsage?.planType == "401"
    }
}

private struct CodexLastUsage: Decodable {
    var planType: String?
    var primary: CodexRateWindow?
    var secondary: CodexRateWindow?
    var resetCredits: CodexResetCredits?
    var hasUnreadableResetWarning: Bool

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case primary
        case secondary
        case resetCredits = "reset_credits"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planType = try container.decodeIfPresent(String.self, forKey: .planType)
        primary = try? container.decodeIfPresent(CodexRateWindow.self, forKey: .primary)
        secondary = try? container.decodeIfPresent(CodexRateWindow.self, forKey: .secondary)
        resetCredits = try container.decodeIfPresent(CodexResetCredits.self, forKey: .resetCredits)

        hasUnreadableResetWarning =
            (container.contains(.primary) && (primary == nil || primary?.resetsAt == nil)) ||
            (container.contains(.secondary) && (secondary == nil || secondary?.resetsAt == nil))
    }
}

private struct CodexAuthError: Decodable {
    var statusCode: Int?

    enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
    }
}

private struct CodexResetCredits: Decodable {
    var availableCount: Int
    var resets: [CodexResetCredit]

    enum CodingKeys: String, CodingKey {
        case availableCount = "available_count"
        case resets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        availableCount = try container.decodeIfPresent(Int.self, forKey: .availableCount) ?? 0
        resets = try container.decodeIfPresent([CodexResetCredit].self, forKey: .resets) ?? []
    }

    func toUsageResetCredits() -> UsageResetCredits? {
        let credits = UsageResetCredits(
            availableCount: availableCount,
            resets: resets.map { UsageResetCredit(expiresAt: epochDate($0.expiresAt)) }
        )
        return credits.hasAvailableCredits ? credits : nil
    }
}

private struct CodexResetCredit: Decodable {
    var expiresAt: Double?

    enum CodingKeys: String, CodingKey {
        case expiresAt = "expires_at"
    }
}

private struct CodexRateWindow: Decodable {
    var usedPercent: Double
    var windowMinutes: Int
    var resetsAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let usedPercent = try container.decode(Double.self, forKey: .usedPercent)
        guard 0...100 ~= usedPercent else {
            throw DecodingError.dataCorruptedError(forKey: .usedPercent, in: container, debugDescription: "Quota percent must be between 0 and 100.")
        }
        self.usedPercent = usedPercent
        windowMinutes = try container.decode(Int.self, forKey: .windowMinutes)
        resetsAt = try container.decodeIfPresent(Double.self, forKey: .resetsAt)
    }

    var resetDate: Date? {
        epochDate(resetsAt)
    }
}

private struct CodexSessionEvent: Decodable {
    var timestamp: String?
    var payload: CodexSessionPayload?

    func parsedDate(using parser: CodexTimestampParser) -> Date? {
        guard let timestamp else { return nil }
        return parser.date(from: timestamp)
    }
}

private struct CodexTimestampParser {
    private let fractionalFormatter: ISO8601DateFormatter
    private let wholeSecondFormatter: ISO8601DateFormatter

    init() {
        fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        wholeSecondFormatter = ISO8601DateFormatter()
        wholeSecondFormatter.formatOptions = [.withInternetDateTime]
    }

    func date(from timestamp: String) -> Date? {
        fractionalFormatter.date(from: timestamp) ?? wholeSecondFormatter.date(from: timestamp)
    }
}

private struct CodexSessionFileSignature: Equatable {
    var size: Int
    var modifiedAt: Date?

    init?(fileURL: URL) {
        guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
              values.isRegularFile == true,
              let size = values.fileSize
        else { return nil }
        self.size = size
        self.modifiedAt = values.contentModificationDate
    }
}

private final class CodexSessionMetricsCache: @unchecked Sendable {
    private struct Entry {
        var signature: CodexSessionFileSignature
        var metrics: CodexSessionMetrics
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func metrics(for path: String, signature: CodexSessionFileSignature) -> CodexSessionMetrics? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[path], entry.signature == signature else { return nil }
        return entry.metrics
    }

    func store(_ metrics: CodexSessionMetrics, for path: String, signature: CodexSessionFileSignature) {
        lock.lock()
        entries[path] = Entry(signature: signature, metrics: metrics)
        lock.unlock()
    }

    func retain(paths: Set<String>) {
        lock.lock()
        entries = entries.filter { paths.contains($0.key) }
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}

private extension CodexSessionMetrics {
    mutating func merge(_ metrics: CodexSessionMetrics) {
        eventCount += metrics.eventCount
        if metrics.tokenTotals.total > 0 {
            tokenTotals = tokenTotals + metrics.tokenTotals
        }
        points.append(contentsOf: metrics.points)
        if let latestRateLimitAt = metrics.latestRateLimitAt,
           self.latestRateLimitAt == nil || latestRateLimitAt >= (self.latestRateLimitAt ?? .distantPast) {
            latestFiveHour = metrics.latestFiveHour
            latestWeekly = metrics.latestWeekly
            latestResetCredits = metrics.latestResetCredits
            self.latestRateLimitAt = latestRateLimitAt
        }
    }
}

private struct CodexSessionPayload: Decodable {
    var info: CodexInfo?
    var rateLimits: CodexRateLimits?
    var resetCredits: CodexResetCredits?

    enum CodingKeys: String, CodingKey {
        case info
        case rateLimits = "rate_limits"
        case resetCredits = "rate_limit_reset_credits"
    }
}

private struct CodexInfo: Decodable {
    var model: String?
    var lastTokenUsage: CodexTokenUsage?
    var totalTokenUsage: CodexTokenUsage?

    enum CodingKeys: String, CodingKey {
        case model
        case lastTokenUsage = "last_token_usage"
        case totalTokenUsage = "total_token_usage"
    }
}

private struct CodexRateLimits: Decodable {
    var primary: CodexRateWindow?
    var secondary: CodexRateWindow?
}

private struct CodexTokenUsage: Decodable {
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var reasoningOutputTokens: Int
    var totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
        case totalTokens = "total_tokens"
    }

    func toTotals() -> TokenTotals {
        TokenTotals(input: inputTokens, cachedInput: cachedInputTokens, output: outputTokens, reasoningOutput: reasoningOutputTokens, total: totalTokens)
    }
}

private func firstNonEmptyOptional(_ values: [String?]) -> String? {
    values.compactMap { value -> String? in
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }.first
}

private func maskEmail(_ email: String?) -> String? {
    guard let email, let atIndex = email.firstIndex(of: "@") else { return email }
    let local = String(email[..<atIndex])
    let domain = String(email[email.index(after: atIndex)...])
    let first = local.first.map(String.init) ?? "*"
    return "\(first)***@\(domain)"
}

private func epochDate(_ value: Double?) -> Date? {
    guard let value else { return nil }
    return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1_000 : value)
}

private func epochMillisecondsDate(_ value: Double?) -> Date? {
    guard let value else { return nil }
    return Date(timeIntervalSince1970: value / 1000)
}
