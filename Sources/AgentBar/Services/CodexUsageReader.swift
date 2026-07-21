import Foundation

struct CodexUsageReader {
    var homeDirectory: URL
    var fileManager: FileManager = .default
    var now: @Sendable () -> Date = Date.init
    static let maximumSessionFileBytes = 10 * 1024 * 1024
    static let maximumSessionFiles = 1_000
    static let sessionMetricsCacheDirectoryName = "AgentBar/CodexSessionMetrics-v6"

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser, now: @escaping @Sendable () -> Date = Date.init) {
        self.homeDirectory = homeDirectory
        self.now = now
    }

    func read() -> UsageSnapshot {
        let now = now()
        let storage = CodexAccountStorage(homeDirectory: homeDirectory, fileManager: fileManager)
        let registryURL = storage.registryURL
        var accounts: [UsageAccount] = []
        var points: [UsagePoint] = []
        var activeAccountActivatedAt: Date?
        var accessIssueNote: String?
        var notes = [
            "AgentBar reads the local Codex registry and usage JSONL; auth snapshots are read only for usage API refresh."
        ]
        let activeAuthData = try? Data(contentsOf: storage.activeAuthURL)
        let activeAuthInfo = CodexAuthSnapshotInfo(
            modifiedAt: (try? fileManager.attributesOfItem(atPath: storage.activeAuthURL.path))?[.modificationDate] as? Date,
            identity: activeAuthData.flatMap(CodexAccountStorage.chatGPTAuthIdentity),
            accessTokenExpiresAt: activeAuthData.flatMap(CodexAccountStorage.accessTokenExpiration)
        )

        do {
            let data = try Data(contentsOf: registryURL)
            if let registryDetails = try? Self.parseRegistryDetails(
                data: data,
                now: now,
                activeAuthInfo: activeAuthInfo,
                authSnapshotInfo: { accountKey in
                    let authURL = storage.accountAuthURL(for: accountKey)
                    guard let attributes = try? fileManager.attributesOfItem(atPath: authURL.path) else { return nil }
                    let authData = try? Data(contentsOf: authURL)
                    return CodexAuthSnapshotInfo(
                        modifiedAt: attributes[.modificationDate] as? Date,
                        identity: authData.flatMap(CodexAccountStorage.chatGPTAuthIdentity),
                        accessTokenExpiresAt: authData.flatMap(CodexAccountStorage.accessTokenExpiration)
                    )
                }
            ) {
                accounts = registryDetails.snapshot.accounts
                activeAccountActivatedAt = registryDetails.activeAccountActivatedAt
                notes.append(contentsOf: registryDetails.snapshot.securityNotes)
            } else {
                notes.append("Codex registry not found at ~/.codex/accounts/registry.json.")
            }
        } catch {
            if let note = LocalFileAccessWarning.codexNote(for: error, path: registryURL.path) {
                accessIssueNote = note
            } else {
                notes.append("Codex registry not found at ~/.codex/accounts/registry.json.")
            }
        }

        let sessionRoot = homeDirectory.appending(path: ".codex/sessions")
        let sessionCacheDirectory = homeDirectory.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
            ? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appending(path: Self.sessionMetricsCacheDirectoryName, directoryHint: .isDirectory)
            : nil
        let metrics = CodexSessionMetricsReader(fileManager: fileManager).read(
            root: sessionRoot,
            maximumSessionFileBytes: Self.maximumSessionFileBytes,
            maximumSessionFiles: Self.maximumSessionFiles,
            cacheDirectory: sessionCacheDirectory
        )
        if let sessionScanNote = Self.sessionScanNote(metrics) {
            notes.insert(sessionScanNote, at: 0)
        }
        if let note = metrics.accessIssueNote ?? accessIssueNote {
            notes.insert(note, at: 0)
            accessIssueNote = note
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
                let canUseSessionQuotaWindows = canUseSessionRateLimitsForActiveAccount &&
                    account.fiveHourWindow == nil && account.weeklyWindow == nil
                if account.fiveHourWindow == nil,
                   canUseSessionQuotaWindows,
                   let latestFiveHour = metrics.latestFiveHour {
                    account.fiveHourWindow = latestFiveHour
                }
                if account.weeklyWindow == nil,
                   canUseSessionQuotaWindows,
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
                return account.restoringExpiredQuotaWindows(now: now)
            }
        }

        let status: DataSourceStatus = accessIssueNote == nil
            ? (accounts.isEmpty && metrics.eventCount == 0 ? .unavailable : .live)
            : .needsAuthorization
        return UsageSnapshot(
            service: .codex,
            status: status,
            accounts: accounts,
            points: points,
            tasks: metrics.tasks,
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
        activeAuthInfo: CodexAuthSnapshotInfo? = nil,
        authSnapshotInfo: ((String) -> CodexAuthSnapshotInfo?)? = nil
    ) throws -> (snapshot: UsageSnapshot, activeAccountActivatedAt: Date?) {
        let registry = try JSONDecoder().decode(CodexRegistry.self, from: data)
        let activeAccountKey = registry.accounts.accountKey(matching: activeAuthInfo?.identity) ?? registry.activeAccountKey
        let workspaceNamesByID = registry.accounts.workspaceNamesByID
        let accounts = registry.accounts.map { raw in
            let savedAuthInfo = authSnapshotInfo?(raw.accountKey)
            let activeAccessTokenExpiresAt = raw.accountKey == activeAccountKey && raw.matchesAuthIdentity(activeAuthInfo?.identity)
                ? activeAuthInfo?.accessTokenExpiresAt
                : nil
            let accessTokenExpiresAt = activeAccessTokenExpiresAt ?? savedAuthInfo?.accessTokenExpiresAt
            let username = firstNonEmptyOptional([raw.email, raw.accountName, raw.alias])
            let displayName = username ?? "Codex Account"
            let workspaces = raw.usageWorkspaces.resolvingNames(with: workspaceNamesByID)
            let workspaceName = workspaces.first?.name
            let workspaceID = workspaces.first?.workspaceID
            let quotaWindows = CodexRateWindow.usageWindows(
                primary: raw.lastUsage?.primary,
                secondary: raw.lastUsage?.secondary
            )
            let resetCredits = raw.lastUsage?.resetCredits?.toUsageResetCredits()
            let loginWarning: UsageAccountLoginWarning? =
                raw.hasTokenBackedQuotaWarning ? .quotaUnavailable :
                raw.hasForcedLogoutWarning(authSnapshotInfo: savedAuthInfo, activeAuthInfo: activeAuthInfo) ? .forcedLogout :
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
                fiveHourWindow: quotaWindows.fiveHour,
                weeklyWindow: quotaWindows.weekly,
                resetCredits: resetCredits,
                tokens: .zero,
                estimatedCostUSD: nil,
                lastUpdated: epochDate(raw.lastUsageAt),
                isActive: raw.accountKey == activeAccountKey,
                loginWarning: loginWarning,
                workspaceName: workspaceName,
                workspaceID: workspaceID,
                workspaces: workspaces,
                accessTokenExpiresAt: accessTokenExpiresAt
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
        let activatedAt = activeAccountKey == registry.activeAccountKey ? epochMillisecondsDate(registry.activeAccountActivatedAtMs) : nil
        return (snapshot, activatedAt)
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
        var taskBuilders: [String: CodexTaskBuilder] = [:]
        var taskOrder: [String] = []
        var activeTaskID: String?
        var seenTaskUsageSequences = Set<CodexTaskUsageSequence>()
        let decoder = JSONDecoder()
        let dateParser = CodexTimestampParser()
        let compactResponseItemMarker = Data(#""type":"response_item""#.utf8)
        let spacedResponseItemMarker = Data(#""type": "response_item""#.utf8)
        let meaningfulPayloadMarkers = [
            "last_token_usage",
            "total_token_usage",
            "rate_limits",
            "rate_limit_reset_credits",
            "turn_context",
            "session_meta",
            "user_message",
            "task_started",
            "task_complete",
            "turn_aborted",
            "agent_message",
            "agent_reasoning",
            "mcp_tool_call_begin",
            "mcp_tool_call_end",
            "web_search_begin",
            "web_search_end",
            "patch_apply_begin",
            "patch_apply_end",
            "exec_command_begin",
            "exec_command_end",
            #""cwd":"#,
            #""model":"#,
            #""reasoning_effort":"#,
            #""title":"#
        ].map { Data($0.utf8) }

        for (lineOffset, line) in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true).enumerated() {
            if line.range(of: compactResponseItemMarker) != nil || line.range(of: spacedResponseItemMarker) != nil {
                continue
            }
            guard meaningfulPayloadMarkers.contains(where: { line.range(of: $0) != nil }) else {
                continue
            }
            guard let event = try? decoder.decode(CodexSessionEvent.self, from: Data(line))
            else { continue }

            guard let payload = event.payload else { continue }
            let parsedEventDate = event.parsedDate(using: dateParser)
            let eventDate = parsedEventDate ?? .distantPast
            let sessionID = event.sessionID ?? fallbackSessionID
            let taskTitleCandidate = payload.type == "user_message" ? payload.sessionTitleCandidate : nil
            currentSessionTitle = currentSessionTitle ?? taskTitleCandidate
            currentModel = payload.model ?? currentModel
            currentCwd = payload.cwd ?? currentCwd
            currentReasoningEffort = payload.reasoningEffort ?? currentReasoningEffort
            let projectName = payload.projectName ?? currentCwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? fallbackProjectName

            if payload.type == "task_started", let turnID = payload.turnID {
                let startedAt = epochDate(payload.startedAt) ?? parsedEventDate ?? .distantPast
                if let previousTaskID = activeTaskID,
                   previousTaskID != turnID,
                   var previousBuilder = taskBuilders[previousTaskID],
                   previousBuilder.terminalState == nil {
                    let interruptedAt = max(previousBuilder.lastActivityAt, startedAt)
                    previousBuilder.completedAt = interruptedAt
                    previousBuilder.lastActivityAt = interruptedAt
                    previousBuilder.terminalState = .interrupted
                    taskBuilders[previousTaskID] = previousBuilder
                }
                if taskBuilders[turnID] == nil {
                    taskOrder.append(turnID)
                }
                taskBuilders[turnID] = CodexTaskBuilder(
                    id: turnID,
                    sessionID: sessionID ?? fallbackSessionID ?? turnID,
                    title: currentSessionTitle,
                    projectName: projectName,
                    cwd: currentCwd,
                    sourceFile: sourceFile,
                    startedAt: startedAt,
                    completedAt: nil,
                    lastActivityAt: startedAt,
                    tokens: .zero,
                    estimatedCostUSD: nil,
                    models: [],
                    reasoningEffort: currentReasoningEffort,
                    terminalState: nil
                )
                activeTaskID = turnID
            }

            if let activeTaskID, var builder = taskBuilders[activeTaskID] {
                builder.title = taskTitleCandidate ?? builder.title ?? currentSessionTitle
                builder.cwd = currentCwd ?? builder.cwd
                builder.projectName = projectName ?? builder.projectName
                builder.reasoningEffort = currentReasoningEffort ?? builder.reasoningEffort
                if let parsedEventDate {
                    builder.lastActivityAt = max(builder.lastActivityAt, parsedEventDate)
                }
                taskBuilders[activeTaskID] = builder
            }
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
                let model = Pricing.normalize(model: firstNonEmptyOptional([info.model, currentModel]) ?? "Codex local")
                let pointCost = Pricing.cost(model: model, tokens: pointUsage)
                let usageSequence = activeTaskID.flatMap { taskID in
                    cumulativeTotals.map { CodexTaskUsageSequence(taskID: taskID, cumulativeTokens: $0) }
                }
                let shouldRecordUsage = usageSequence.map { seenTaskUsageSequences.insert($0).inserted } ?? true
                if shouldRecordUsage {
                    eventCount += 1
                    points.append(
                        UsagePoint(
                            service: .codex,
                            model: model,
                            date: eventDate,
                            tokens: pointUsage,
                            cumulativeTokens: cumulativeTotals,
                            estimatedCostUSD: pointCost,
                            sessionID: sessionID,
                            sessionTitle: currentSessionTitle,
                            projectName: projectName,
                            cwd: currentCwd,
                            taskID: activeTaskID,
                            sourceFile: sourceFile,
                            sourceLine: lineOffset + 1,
                            reasoningEffort: currentReasoningEffort,
                            initiator: payload.callInitiator,
                            modelContextWindow: info.modelContextWindow
                        )
                    )
                    if let activeTaskID, var builder = taskBuilders[activeTaskID] {
                        builder.tokens = builder.tokens + pointUsage
                        builder.estimatedCostUSD = (builder.estimatedCostUSD ?? 0) + pointCost
                        if !builder.models.contains(model) {
                            builder.models.append(model)
                        }
                        taskBuilders[activeTaskID] = builder
                    }
                }
            }

            if (payload.type == "task_complete" || payload.type == "turn_aborted"),
               let turnID = payload.turnID ?? activeTaskID,
               var builder = taskBuilders[turnID] {
                let completedAt = epochDate(payload.completedAt) ?? parsedEventDate ?? builder.lastActivityAt
                builder.completedAt = completedAt
                builder.lastActivityAt = max(builder.lastActivityAt, completedAt)
                builder.terminalState = payload.type == "turn_aborted" ? .interrupted : .completed
                builder.reportedDurationMilliseconds = payload.durationMilliseconds ?? builder.reportedDurationMilliseconds
                builder.timeToFirstTokenMilliseconds = payload.timeToFirstTokenMilliseconds ?? builder.timeToFirstTokenMilliseconds
                taskBuilders[turnID] = builder
                if activeTaskID == turnID {
                    activeTaskID = nil
                }
            }

            if let parsedEventDate,
               payload.rateLimits != nil || payload.resetCredits != nil,
               latestRateLimitAt == nil || parsedEventDate >= (latestRateLimitAt ?? .distantPast) {
                if let rateLimits = payload.rateLimits {
                    let quotaWindows = CodexRateWindow.usageWindows(
                        primary: rateLimits.primary,
                        secondary: rateLimits.secondary
                    )
                    fiveHour = quotaWindows.fiveHour
                    weekly = quotaWindows.weekly
                }
                if let sessionResetCredits = payload.resetCredits {
                    resetCredits = sessionResetCredits.toUsageResetCredits()
                }
                latestRateLimitAt = parsedEventDate
            }
        }

        let tasks = taskOrder.compactMap { taskBuilders[$0]?.task }
        return CodexSessionMetrics(eventCount: eventCount, tokenTotals: latestTotal, points: points, tasks: tasks, latestFiveHour: fiveHour, latestWeekly: weekly, latestResetCredits: resetCredits, latestRateLimitAt: latestRateLimitAt)
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
    var tokenBacked: Bool

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
        case tokenBacked = "agentbar_token_backed"
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
        tokenBacked = (try? container.decodeIfPresent(Bool.self, forKey: .tokenBacked)) ?? false
    }

    var hasTokenBackedQuotaWarning: Bool {
        tokenBacked && (authError?.statusCode == 401 || plan == "401" || lastUsage?.planType == "401")
    }

    func hasForcedLogoutWarning(authSnapshotInfo: CodexAuthSnapshotInfo? = nil, activeAuthInfo: CodexAuthSnapshotInfo? = nil) -> Bool {
        if let authError, authError.statusCode == 401 {
            if let detectedAt = authError.detectedAt,
               [activeAuthInfo, authSnapshotInfo].contains(where: { info in
                   guard let info,
                         let authModifiedAt = info.modifiedAt,
                         authModifiedAt.timeIntervalSince1970 > detectedAt
                   else { return false }
                   return matchesAuthIdentity(info.identity)
               }) {
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

    func matchesAuthIdentity(_ identity: CodexAuthIdentity?) -> Bool {
        guard let accountID = identity?.accountID?.trimmingCharacters(in: .whitespacesAndNewlines), !accountID.isEmpty else {
            return false
        }
        return identity?.matches(
            accountKey: accountKey,
            email: email,
            chatGPTAccountID: chatGPTAccountID,
            workspaceID: workspaceID
        ) == true
    }
}

private struct CodexAuthSnapshotInfo {
    var modifiedAt: Date?
    var identity: CodexAuthIdentity?
    var accessTokenExpiresAt: Date?
}

private extension Array where Element == CodexRegistryAccount {
    func accountKey(matching identity: CodexAuthIdentity?) -> String? {
        first { $0.matchesAuthIdentity(identity) }?.accountKey
    }

    var workspaceNamesByID: [String: String] {
        flatMap(\.usageWorkspaces).reduce(into: [:]) { names, workspace in
            guard let workspaceID = firstNonEmptyOptional([workspace.workspaceID]),
                  let name = firstNonEmptyOptional([workspace.name]),
                  names[workspaceID] == nil
            else { return }
            names[workspaceID] = name
        }
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

    static func usageWindows(
        primary: CodexRateWindow?,
        secondary: CodexRateWindow?
    ) -> (fiveHour: UsageWindow?, weekly: UsageWindow?) {
        let windows = [primary, secondary].compactMap { $0 }
        return (
            windows.first { $0.windowMinutes < 24 * 60 }?.usageWindow(kind: .fiveHour),
            windows.first { $0.windowMinutes >= 24 * 60 }?.usageWindow(kind: .weekly)
        )
    }

    private func usageWindow(kind: UsageWindow.Kind) -> UsageWindow {
        UsageWindow(
            kind: kind,
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetsAt: resetDate
        )
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
    var turnID: String?
    var startedAt: Double?
    var completedAt: Double?
    var durationMilliseconds: Double?
    var timeToFirstTokenMilliseconds: Double?

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
        case turnID = "turn_id"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case durationMilliseconds = "duration_ms"
        case timeToFirstTokenMilliseconds = "time_to_first_token_ms"
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
        turnID = try container.decodeIfPresent(String.self, forKey: .turnID)
        startedAt = try container.decodeIfPresent(Double.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Double.self, forKey: .completedAt)
        durationMilliseconds = try? container.decode(Double.self, forKey: .durationMilliseconds)
        timeToFirstTokenMilliseconds = try? container.decode(Double.self, forKey: .timeToFirstTokenMilliseconds)
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

private struct CodexTaskBuilder {
    var id: String
    var sessionID: String
    var title: String?
    var projectName: String?
    var cwd: String?
    var sourceFile: String? = nil
    var startedAt: Date
    var completedAt: Date?
    var lastActivityAt: Date
    var tokens: TokenTotals
    var estimatedCostUSD: Decimal?
    var models: [String]
    var reasoningEffort: String? = nil
    var terminalState: AgentTaskState?
    var reportedDurationMilliseconds: Double? = nil
    var timeToFirstTokenMilliseconds: Double? = nil

    var task: AgentTask {
        AgentTask(
            id: id,
            sessionID: sessionID,
            title: title,
            projectName: projectName,
            cwd: cwd,
            sourceFile: sourceFile,
            startedAt: startedAt,
            completedAt: completedAt,
            lastActivityAt: lastActivityAt,
            tokens: tokens,
            estimatedCostUSD: estimatedCostUSD,
            models: models,
            reasoningEffort: reasoningEffort,
            terminalState: terminalState,
            reportedDurationMilliseconds: reportedDurationMilliseconds,
            timeToFirstTokenMilliseconds: timeToFirstTokenMilliseconds
        )
    }
}

private struct CodexTaskUsageSequence: Hashable {
    var taskID: String
    var cumulativeTokens: TokenTotals
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
    func resolvingNames(with namesByID: [String: String]) -> [UsageWorkspace] {
        map { workspace in
            guard firstNonEmptyOptional([workspace.name]) == nil,
                  let workspaceID = firstNonEmptyOptional([workspace.workspaceID]),
                  let name = namesByID[workspaceID]
            else { return workspace }
            return UsageWorkspace(name: name, workspaceID: workspaceID)
        }.dedupedWorkspaces()
    }

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

enum LocalFileAccessWarning {
    static func codexNote(for error: Error, path: String) -> String? {
        guard isAccessDenied(error as NSError) else { return nil }
        return "AgentBar cannot read local Codex data at \(displayPath(path)). Grant AgentBar Files and Folders or Full Disk Access in System Settings, then refresh."
    }

    private static func isAccessDenied(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
            return true
        }
        if error.domain == NSPOSIXErrorDomain && (error.code == Int(EACCES) || error.code == Int(EPERM)) {
            return true
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isAccessDenied(underlying)
        }
        return false
    }

    private static func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
