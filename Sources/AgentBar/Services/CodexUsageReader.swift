import Foundation

struct CodexUsageReader {
    var homeDirectory: URL
    var fileManager: FileManager = .default
    static let maximumSessionFileBytes = 10 * 1024 * 1024
    static let maximumSessionFiles = 1_000

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    func read() -> UsageSnapshot {
        let now = Date()
        let storage = CodexAccountStorage(homeDirectory: homeDirectory, fileManager: fileManager)
        let registryURL = storage.registryURL
        var accounts: [UsageAccount] = []
        var points: [UsagePoint] = []
        var activeAccountActivatedAt: Date?
        var notes = [
            "AgentBar reads the local Codex registry and usage JSONL; auth snapshots are read only for usage API refresh."
        ]

        if let data = try? Data(contentsOf: registryURL),
           let registryDetails = try? Self.parseRegistryDetails(
            data: data,
            now: now,
            authSnapshotModifiedAt: { accountKey in
                let authURL = storage.accountAuthURL(for: accountKey)
                guard let attributes = try? fileManager.attributesOfItem(atPath: authURL.path) else { return nil }
                return attributes[.modificationDate] as? Date
            }
           ) {
            accounts = registryDetails.snapshot.accounts
            activeAccountActivatedAt = registryDetails.activeAccountActivatedAt
            notes.append(contentsOf: registryDetails.snapshot.securityNotes)
        } else {
            notes.append("Codex registry not found at ~/.codex/accounts/registry.json.")
        }

        let sessionRoot = homeDirectory.appending(path: ".codex/sessions")
        let metrics = CodexSessionMetricsReader(fileManager: fileManager).read(
            root: sessionRoot,
            maximumSessionFileBytes: Self.maximumSessionFileBytes,
            maximumSessionFiles: Self.maximumSessionFiles
        )
        if let sessionScanNote = Self.sessionScanNote(metrics) {
            notes.insert(sessionScanNote, at: 0)
        }
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
                   canUseSessionRateLimitsForActiveAccount,
                   let latestFiveHour = metrics.latestFiveHour {
                    account.fiveHourWindow = latestFiveHour
                }
                if account.weeklyWindow == nil,
                   canUseSessionRateLimitsForActiveAccount,
                   let latestWeekly = metrics.latestWeekly {
                    account.weeklyWindow = latestWeekly
                }
                if account.resetCredits == nil,
                   canUseSessionRateLimitsForActiveAccount {
                    account.resetCredits = metrics.latestResetCredits
                }
                if account.tokens.total == 0 {
                    account.tokens = metrics.tokenTotals
                }
                account.lastUpdated = account.lastUpdated ?? (canUseSessionRateLimitsForActiveAccount ? metrics.latestRateLimitAt : nil)
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

    private static func parseRegistryDetails(
        data: Data,
        now: Date,
        authSnapshotModifiedAt: ((String) -> Date?)? = nil
    ) throws -> (snapshot: UsageSnapshot, activeAccountActivatedAt: Date?) {
        let registry = try JSONDecoder().decode(CodexRegistry.self, from: data)
        let accounts = registry.accounts.map { raw in
            let username = firstNonEmptyOptional([raw.email, raw.accountName, raw.alias])
            let displayName = username ?? "Codex Account"
            let workspaces = raw.usageWorkspaces
            let workspaceName = workspaces.first?.name
            let workspaceID = workspaces.first?.workspaceID
            let primary = raw.lastUsage?.primary.map {
                UsageWindow(kind: .fiveHour, usedPercent: $0.usedPercent, windowMinutes: $0.windowMinutes, resetsAt: epochDate($0.resetsAt))
            }
            let secondary = raw.lastUsage?.secondary.map {
                UsageWindow(kind: .weekly, usedPercent: $0.usedPercent, windowMinutes: $0.windowMinutes, resetsAt: epochDate($0.resetsAt))
            }
            let resetCredits = raw.lastUsage?.resetCredits?.toUsageResetCredits()
            let loginWarning: UsageAccountLoginWarning? =
                raw.hasForcedLogoutWarning(authModifiedAt: authSnapshotModifiedAt?(raw.accountKey)) ? .forcedLogout :
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
                lastUpdated: epochDate(raw.lastUsageAt),
                isActive: raw.accountKey == registry.activeAccountKey,
                loginWarning: loginWarning,
                workspaceName: workspaceName,
                workspaceID: workspaceID,
                workspaces: workspaces
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

    static func parseSessionJsonl(
        data: Data,
        sessionID fallbackSessionID: String? = nil,
        projectName fallbackProjectName: String? = nil,
        sourceFile: String? = nil
    ) throws -> CodexSessionMetrics {
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
        var currentSessionTitle: String?
        var currentModel: String?
        var currentCwd: String?
        var currentReasoningEffort: String?
        let decoder = JSONDecoder()
        let dateParser = CodexTimestampParser()

        for (lineOffset, line) in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true).enumerated() {
            guard let event = try? decoder.decode(CodexSessionEvent.self, from: Data(line))
            else { continue }

            guard let payload = event.payload else { continue }
            let parsedEventDate = event.parsedDate(using: dateParser)
            let eventDate = parsedEventDate ?? .distantPast
            let sessionID = event.sessionID ?? fallbackSessionID
            currentSessionTitle = currentSessionTitle ?? payload.sessionTitleCandidate
            currentModel = payload.model ?? currentModel
            currentCwd = payload.cwd ?? currentCwd
            currentReasoningEffort = payload.reasoningEffort ?? currentReasoningEffort
            let projectName = payload.projectName ?? currentCwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? fallbackProjectName
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
                let model = Pricing.normalize(model: firstNonEmptyOptional([info.model, currentModel]) ?? "Codex local")
                points.append(
                    UsagePoint(
                        service: .codex,
                        model: model,
                        date: eventDate,
                        tokens: pointUsage,
                        estimatedCostUSD: Pricing.cost(model: model, tokens: pointUsage),
                        sessionID: sessionID,
                        sessionTitle: currentSessionTitle,
                        projectName: projectName,
                        cwd: currentCwd,
                        sourceFile: sourceFile,
                        sourceLine: lineOffset + 1,
                        reasoningEffort: currentReasoningEffort,
                        initiator: payload.callInitiator,
                        modelContextWindow: info.modelContextWindow
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

    static func resetSessionMetricsCacheForTesting() {
        CodexSessionMetricsReader.resetCacheForTesting()
    }

    private static func sessionScanNote(_ metrics: CodexSessionMetrics) -> String? {
        let skipped = metrics.skippedOversizedSessionFileCount + metrics.skippedSessionFileCapCount
        guard skipped > 0 else { return nil }

        var reasons: [String] = []
        if metrics.skippedOversizedSessionFileCount > 0 {
            reasons.append("\(metrics.skippedOversizedSessionFileCount) over the \(maximumSessionFileBytes / 1024 / 1024) MB file limit")
        }
        if metrics.skippedSessionFileCapCount > 0 {
            reasons.append("\(metrics.skippedSessionFileCapCount) beyond the \(maximumSessionFiles) file scan cap")
        }
        return "Codex session scan skipped \(skipped) JSONL file\(skipped == 1 ? "" : "s"): \(reasons.joined(separator: ", ")). Usage may be undercounted."
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

    fileprivate static func sessionTitle(from message: String?) -> String? {
        let lines = message?
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        guard !lines.isEmpty else { return nil }
        if let requestIndex = lines.firstIndex(where: { $0.localizedCaseInsensitiveContains("My request for Codex") }) {
            return lines.dropFirst(requestIndex + 1).first(where: isSessionTitleLine)
        }
        return lines.first(where: isSessionTitleLine)
    }

    private static func isSessionTitleLine(_ line: String) -> Bool {
        !line.hasPrefix("#") && !line.hasPrefix("<image") && !line.hasPrefix("!")
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
    var chatGPTAccountID: String?
    var workspaceID: String?
    var workspaceName: String?
    var organizationName: String?
    var workspaceNames: [String]
    var workspaceIDs: [String]
    var organizationNames: [String]
    var workspaces: [CodexWorkspaceCandidate]
    var organizations: [CodexWorkspaceCandidate]
    var invites: [CodexWorkspaceCandidate]
    var chatGPTAccounts: [CodexWorkspaceCandidate]
    var plan: String?
    var lastUsage: CodexLastUsage?
    var lastUsageAt: Double?
    var authError: CodexAuthError?

    enum CodingKeys: String, CodingKey {
        case accountKey = "account_key"
        case accountName = "account_name"
        case alias
        case email
        case chatGPTAccountID = "chatgpt_account_id"
        case workspaceID = "workspace_id"
        case workspaceName = "workspace_name"
        case workspaceIDs = "workspace_ids"
        case workspaceNames = "workspace_names"
        case organizationName = "organization_name"
        case organizationNames = "organization_names"
        case workspaces
        case organizations
        case invites
        case chatGPTAccounts = "chatgpt_accounts"
        case plan
        case lastUsage = "last_usage"
        case lastUsageAt = "last_usage_at"
        case authError = "agentbar_auth_error"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountKey = try container.decode(String.self, forKey: .accountKey)
        accountName = try container.decodeIfPresent(String.self, forKey: .accountName)
        alias = try container.decodeIfPresent(String.self, forKey: .alias)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        chatGPTAccountID = try container.decodeIfPresent(String.self, forKey: .chatGPTAccountID)
        workspaceID = try container.decodeIfPresent(String.self, forKey: .workspaceID)
        workspaceName = try container.decodeIfPresent(String.self, forKey: .workspaceName)
        organizationName = try container.decodeIfPresent(String.self, forKey: .organizationName)
        workspaceNames = (try? container.decodeIfPresent([String].self, forKey: .workspaceNames)) ?? []
        workspaceIDs = (try? container.decodeIfPresent([String].self, forKey: .workspaceIDs)) ?? []
        organizationNames = (try? container.decodeIfPresent([String].self, forKey: .organizationNames)) ?? []
        workspaces = (try? container.decodeIfPresent([CodexWorkspaceCandidate].self, forKey: .workspaces)) ?? []
        organizations = (try? container.decodeIfPresent([CodexWorkspaceCandidate].self, forKey: .organizations)) ?? []
        invites = (try? container.decodeIfPresent([CodexWorkspaceCandidate].self, forKey: .invites)) ?? []
        chatGPTAccounts = (try? container.decodeIfPresent([CodexWorkspaceCandidate].self, forKey: .chatGPTAccounts)) ?? []
        plan = try container.decodeIfPresent(String.self, forKey: .plan)
        lastUsage = try container.decodeIfPresent(CodexLastUsage.self, forKey: .lastUsage)
        lastUsageAt = try container.decodeIfPresent(Double.self, forKey: .lastUsageAt)
        authError = try container.decodeIfPresent(CodexAuthError.self, forKey: .authError)
    }

    func hasForcedLogoutWarning(authModifiedAt: Date? = nil) -> Bool {
        if let authError, authError.statusCode == 401 {
            if let detectedAt = authError.detectedAt,
               let authModifiedAt,
               authModifiedAt.timeIntervalSince1970 > detectedAt {
                return false
            }
            return true
        }
        return plan == "401" || lastUsage?.planType == "401"
    }

    var usageWorkspaces: [UsageWorkspace] {
        let scalar = UsageWorkspace(
            name: firstNonEmptyOptional([workspaceName, accountName, organizationName]),
            workspaceID: firstNonEmptyOptional([workspaceID, chatGPTAccountID, accountKey.codexWorkspaceID])
        )
        let named = workspaceNames.map { UsageWorkspace(name: $0, workspaceID: nil) }
        let identified = workspaceIDs.map { UsageWorkspace(name: nil, workspaceID: $0) }
        let organizationNamed = organizationNames.map { UsageWorkspace(name: $0, workspaceID: nil) }
        let candidates = workspaces + organizations + invites + chatGPTAccounts
        return ([scalar] + named + identified + organizationNamed + candidates.map(\.usageWorkspace)).dedupedWorkspaces()
    }
}

private struct CodexWorkspaceCandidate: Decodable {
    var name: String?
    var workspaceID: String?

    enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
        case title
        case workspaceName = "workspace_name"
        case organizationName = "organization_name"
        case id
        case workspaceID = "workspace_id"
        case accountID = "account_id"
        case chatGPTAccountID = "chatgpt_account_id"
    }

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            name = value
            workspaceID = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = firstNonEmptyOptional([
            try container.decodeIfPresent(String.self, forKey: .name),
            try container.decodeIfPresent(String.self, forKey: .displayName),
            try container.decodeIfPresent(String.self, forKey: .title),
            try container.decodeIfPresent(String.self, forKey: .workspaceName),
            try container.decodeIfPresent(String.self, forKey: .organizationName)
        ])
        workspaceID = firstNonEmptyOptional([
            try container.decodeIfPresent(String.self, forKey: .workspaceID),
            try container.decodeIfPresent(String.self, forKey: .accountID),
            try container.decodeIfPresent(String.self, forKey: .chatGPTAccountID),
            try container.decodeIfPresent(String.self, forKey: .id)
        ])
    }

    var usageWorkspace: UsageWorkspace {
        UsageWorkspace(name: name, workspaceID: workspaceID)
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
    var detectedAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case detectedAt = "detected_at"
    }
}

private extension String {
    var codexWorkspaceID: String? {
        guard let delimiter = range(of: "::") else { return nil }
        let value = self[delimiter.upperBound...]
        return value.isEmpty ? nil : String(value)
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
    var sessionID: String?
    var payload: CodexSessionPayload?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case sessionID = "session_id"
        case payload
    }

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

private struct CodexSessionPayload: Decodable {
    var type: String?
    var info: CodexInfo?
    var rateLimits: CodexRateLimits?
    var resetCredits: CodexResetCredits?
    var cwd: String?
    var message: String?
    var title: String?
    var model: String?
    var reasoningEffort: String?

    enum CodingKeys: String, CodingKey {
        case type
        case info
        case rateLimits = "rate_limits"
        case resetCredits = "rate_limit_reset_credits"
        case cwd
        case message
        case title
        case model
        case reasoningEffort = "reasoning_effort"
        case effort
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        info = try container.decodeIfPresent(CodexInfo.self, forKey: .info)
        rateLimits = try container.decodeIfPresent(CodexRateLimits.self, forKey: .rateLimits)
        resetCredits = try container.decodeIfPresent(CodexResetCredits.self, forKey: .resetCredits)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        reasoningEffort = try container.decodeIfPresent(String.self, forKey: .reasoningEffort)
            ?? container.decodeIfPresent(String.self, forKey: .effort)
    }

    var projectName: String? {
        let value = cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return URL(fileURLWithPath: value).lastPathComponent
    }

    var sessionTitleCandidate: String? {
        firstNonEmptyOptional([title, CodexUsageReader.sessionTitle(from: message)])
    }

    var callInitiator: String? {
        switch type {
        case "user_message": return "User"
        case "agent_message", "token_count", "mcp_tool_call_begin", "mcp_tool_call_end": return "Codex"
        default: return nil
        }
    }
}

private struct CodexInfo: Decodable {
    var model: String?
    var lastTokenUsage: CodexTokenUsage?
    var totalTokenUsage: CodexTokenUsage?
    var modelContextWindow: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case lastTokenUsage = "last_token_usage"
        case totalTokenUsage = "total_token_usage"
        case modelContextWindow = "model_context_window"
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

private extension Array where Element == UsageWorkspace {
    func dedupedWorkspaces() -> [UsageWorkspace] {
        var seen = Set<String>()
        return compactMap { workspace in
            let name = workspace.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let workspaceID = workspace.workspaceID?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name?.isEmpty == false || workspaceID?.isEmpty == false else { return nil }
            let key = "\(name?.lowercased() ?? "")|\(workspaceID?.lowercased() ?? "")"
            guard seen.insert(key).inserted else { return nil }
            return UsageWorkspace(name: name, workspaceID: workspaceID)
        }
    }
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
