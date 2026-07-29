import Foundation

struct GrokSubscriptionUsage: Codable, Equatable, Sendable {
    var prepaidBalanceUSD: Decimal?
    var onDemandUsedUSD: Decimal?
    var onDemandCapUSD: Decimal?
    var periodEndsAt: Date?

    func summaryLines(language: AppLanguage) -> [String] {
        var lines: [String] = []
        if let prepaidBalanceUSD {
            lines.append(
                "\(L.text("extra_usage_credits", language)): \(DisplayFormatters.costString(prepaidBalanceUSD))"
            )
        }
        if let onDemandUsedUSD {
            let value = onDemandCapUSD.map {
                "\(DisplayFormatters.costString(onDemandUsedUSD)) / \(DisplayFormatters.costString($0))"
            } ?? DisplayFormatters.costString(onDemandUsedUSD)
            lines.append("\(L.text("on_demand_usage", language)): \(value)")
        }
        if let periodEndsAt {
            let timestamp = DisplayFormatters.shortDateTimeString(for: periodEndsAt, language: language)
            let relative = DisplayFormatters.relativeString(for: periodEndsAt, language: language)
            lines.append("\(L.text("reset", language)): \(timestamp) (\(relative))")
        }
        return lines
    }
}

struct GrokCLICredential: Sendable {
    var token: String
    var userID: String
    var teamID: String?
    var expiresAt: Date?
    var email: String?
    var username: String?
}

enum GrokCLIAuthStore {
    private static let maximumAuthFileBytes = 1_000_000

    static func credential(homeDirectory: URL) throws -> GrokCLICredential? {
        let authFile = homeDirectory.appendingPathComponent(".grok/auth.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: authFile.path)
        if let size = attributes[.size] as? NSNumber, size.intValue > maximumAuthFileBytes {
            throw GrokCLIUsageError.authFileTooLarge
        }

        let data = try Data(contentsOf: authFile)
        let records = try JSONDecoder().decode([String: GrokCLIAuthRecord].self, from: data)
        return records
            .filter { $0.key.hasPrefix("https://auth.x.ai::") }
            .sorted { $0.key < $1.key }
            .compactMap { _, record in record.credential }
            .first
    }
}

private struct GrokCLIAuthRecord: Decodable {
    var key: String?
    var userID: String?
    var teamID: String?
    var expiresAt: String?
    var email: String?
    var firstName: String?

    enum CodingKeys: String, CodingKey {
        case key
        case userID = "user_id"
        case teamID = "team_id"
        case expiresAt = "expires_at"
        case email
        case firstName = "first_name"
    }

    var credential: GrokCLICredential? {
        guard let token = key?.trimmedNonEmpty,
              let userID = userID?.trimmedNonEmpty
        else { return nil }
        return GrokCLICredential(
            token: token,
            userID: userID,
            teamID: teamID?.trimmedNonEmpty,
            expiresAt: expiresAt.flatMap(XAIUsageReader.apiDate),
            email: email?.trimmedNonEmpty,
            username: firstName?.trimmedNonEmpty
        )
    }
}

enum GrokCLISessionRefresher {
    static func refresh(homeDirectory: URL) -> Bool {
        guard let executable = executableURL(homeDirectory: homeDirectory) else { return false }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["models"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return false
        }
        guard finished.wait(timeout: .now() + 10) == .success else {
            process.terminate()
            return false
        }
        return process.terminationStatus == 0
    }

    private static func executableURL(homeDirectory: URL) -> URL? {
        let candidates = [
            homeDirectory.appendingPathComponent(".local/bin/grok"),
            URL(fileURLWithPath: "/opt/homebrew/bin/grok"),
            URL(fileURLWithPath: "/usr/local/bin/grok")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

struct XAIUsageReader {
    typealias Client = @Sendable (URLRequest, TimeInterval) async throws -> (statusCode: Int, data: Data)

    // ponytail: whole-file parsing stays bounded; stream if Grok session logs routinely exceed 20 MB.
    private static let maximumSessionFileBytes = 20 * 1024 * 1024
    var homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    var now: @Sendable () -> Date = Date.init
    var client: Client = Self.defaultClient
    var sessionRefresher: @Sendable (URL) -> Bool = GrokCLISessionRefresher.refresh
    var timeout: TimeInterval = 15

    func read() async -> UsageSnapshot? {
        let refreshedAt = now()
        let localPoints = readLocalUsage()
        var credential: GrokCLICredential

        do {
            guard let storedCredential = try GrokCLIAuthStore.credential(homeDirectory: homeDirectory) else {
                return nil
            }
            credential = storedCredential
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return nil
        } catch {
            return issueSnapshot(
                status: .unavailable,
                credential: nil,
                refreshedAt: refreshedAt,
                localPoints: localPoints,
                note: "AgentBar could not read the Grok CLI login at ~/.grok/auth.json: \(error.localizedDescription.redactedForCredentialWords)"
            )
        }

        do {
            var response = try await client(makeRequest(path: "/billing?format=credits", credential: credential), timeout)
            if response.statusCode == 401 || response.statusCode == 403,
               sessionRefresher(homeDirectory),
               let refreshedCredential = try? GrokCLIAuthStore.credential(homeDirectory: homeDirectory)
            {
                credential = refreshedCredential
                response = try await client(makeRequest(path: "/billing?format=credits", credential: credential), timeout)
            }

            switch response.statusCode {
            case 200:
                let settings = try? await readSettings(credential: credential)
                return try liveSnapshot(
                    data: response.data,
                    settings: settings,
                    credential: credential,
                    refreshedAt: refreshedAt,
                    localPoints: localPoints
                )
            case 401, 403:
                return issueSnapshot(
                    status: .needsAuthorization,
                    credential: credential,
                    refreshedAt: refreshedAt,
                    localPoints: localPoints,
                    note: "The Grok CLI session is no longer authorized (HTTP \(response.statusCode)). Run `grok login`, then refresh AgentBar."
                )
            default:
                return issueSnapshot(
                    status: .unavailable,
                    credential: credential,
                    refreshedAt: refreshedAt,
                    localPoints: localPoints,
                    note: "Grok subscription usage is unavailable (HTTP \(response.statusCode))."
                )
            }
        } catch {
            return issueSnapshot(
                status: .unavailable,
                credential: credential,
                refreshedAt: refreshedAt,
                localPoints: localPoints,
                note: "Grok subscription usage could not be refreshed: \(error.localizedDescription.redactedForCredentialWords)"
            )
        }
    }

    private func readSettings(credential: GrokCLICredential) async throws -> GrokRemoteSettings? {
        let response = try await client(makeRequest(path: "/settings", credential: credential), timeout)
        guard response.statusCode == 200 else { return nil }
        return try JSONDecoder().decode(GrokRemoteSettings.self, from: response.data)
    }

    private func makeRequest(path: String, credential: GrokCLICredential) throws -> URLRequest {
        guard let url = URL(string: "https://cli-chat-proxy.grok.com/v1\(path)") else {
            throw GrokCLIUsageError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        request.setValue(credential.userID, forHTTPHeaderField: "x-userid")
        return request
    }

    private func liveSnapshot(
        data: Data,
        settings: GrokRemoteSettings?,
        credential: GrokCLICredential,
        refreshedAt: Date,
        localPoints: [UsagePoint]
    ) throws -> UsageSnapshot {
        let response = try JSONDecoder().decode(GrokBillingResponse.self, from: data)
        let config = response.config
        let periodStart = Self.apiDate(config?.currentPeriod?.start ?? config?.billingPeriodStart)
        let periodEnd = Self.apiDate(config?.currentPeriod?.end ?? config?.billingPeriodEnd)
        let usedPercent = Self.usedPercent(config)
        let weeklyWindow = usedPercent.map {
            UsageWindow(
                kind: .weekly,
                usedPercent: $0,
                windowMinutes: Self.windowMinutes(start: periodStart, end: periodEnd),
                resetsAt: periodEnd
            )
        }
        let subscription = GrokSubscriptionUsage(
            prepaidBalanceUSD: config?.prepaidBalance?.usd,
            onDemandUsedUSD: config?.onDemandUsed?.usd,
            onDemandCapUSD: config?.onDemandCap?.usd,
            periodEndsAt: periodEnd
        )
        let account = account(
            credential: credential,
            plan: settings?.subscriptionTierDisplay,
            status: .live,
            weeklyWindow: weeklyWindow,
            subscription: subscription,
            tokens: Self.totalTokens(localPoints),
            estimatedCostUSD: Self.totalCost(localPoints),
            lastUpdated: localPoints.map(\.date).max() ?? refreshedAt
        )
        return UsageSnapshot(
            service: .xaiAPI,
            status: .live,
            accounts: [account],
            points: localPoints,
            securityNotes: [
                "Read-only Grok subscription usage and local session token totals. AgentBar never stores or logs the OAuth token or conversation content."
            ],
            refreshedAt: refreshedAt,
            pricingFingerprint: "grok-cli-subscription-v1"
        )
    }

    private func issueSnapshot(
        status: DataSourceStatus,
        credential: GrokCLICredential?,
        refreshedAt: Date,
        localPoints: [UsagePoint] = [],
        note: String
    ) -> UsageSnapshot {
        UsageSnapshot(
            service: .xaiAPI,
            status: status,
            accounts: [
                account(
                    credential: credential,
                    plan: nil,
                    status: status,
                    weeklyWindow: nil,
                    subscription: nil,
                    tokens: Self.totalTokens(localPoints),
                    estimatedCostUSD: Self.totalCost(localPoints),
                    lastUpdated: localPoints.map(\.date).max()
                )
            ],
            points: localPoints,
            securityNotes: [note],
            refreshedAt: refreshedAt,
            pricingFingerprint: "grok-cli-subscription-v1"
        )
    }

    private func account(
        credential: GrokCLICredential?,
        plan: String?,
        status: DataSourceStatus,
        weeklyWindow: UsageWindow?,
        subscription: GrokSubscriptionUsage?,
        tokens: TokenTotals,
        estimatedCostUSD: Decimal?,
        lastUpdated: Date?
    ) -> UsageAccount {
        UsageAccount(
            id: "grok-\(credential?.userID ?? "cli")",
            service: .xaiAPI,
            displayName: "Grok",
            username: credential?.email ?? credential?.username ?? credential?.userID,
            maskedEmail: nil,
            plan: plan?.trimmedNonEmpty ?? "Subscription",
            sourceDescription: "Grok CLI · subscription and local sessions",
            status: status,
            fiveHourWindow: nil,
            weeklyWindow: weeklyWindow,
            tokens: tokens,
            estimatedCostUSD: estimatedCostUSD,
            lastUpdated: lastUpdated,
            isActive: true,
            workspaceName: nil,
            workspaceID: credential?.teamID,
            accessTokenExpiresAt: credential?.expiresAt,
            grokSubscriptionUsage: subscription
        )
    }

    private func readLocalUsage() -> [UsagePoint] {
        let root = homeDirectory.appendingPathComponent(".grok/sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var points: [UsagePoint] = []
        for case let file as URL in enumerator where file.lastPathComponent == "updates.jsonl" {
            guard !Task.isCancelled,
                  let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  (values.fileSize ?? 0) <= Self.maximumSessionFileBytes,
                  let data = try? Data(contentsOf: file, options: .mappedIfSafe)
            else { continue }

            let summary = file
                .deletingLastPathComponent()
                .appendingPathComponent("summary.json")
            let metadata = (try? Data(contentsOf: summary))
                .flatMap { try? JSONDecoder().decode(GrokSessionSummary.self, from: $0) }
            let sessionID = metadata?.info?.id?.trimmedNonEmpty
                ?? file.deletingLastPathComponent().lastPathComponent

            for (index, line) in data.split(separator: UInt8(ascii: "\n")).enumerated() {
                guard let event = try? JSONDecoder().decode(GrokSessionEvent.self, from: Data(line)),
                      let timestamp = event.timestamp,
                      let update = event.params?.update,
                      update.sessionUpdate == "turn_completed",
                      let usage = update.usage
                else { continue }

                let modelUsage = usage.modelUsage?.sorted { $0.key < $1.key } ?? []
                if modelUsage.isEmpty {
                    points.append(Self.point(
                        usage: usage,
                        model: metadata?.currentModelID ?? "Grok",
                        timestamp: timestamp,
                        metadata: metadata,
                        sessionID: sessionID,
                        sourceFile: file.path,
                        sourceLine: index + 1,
                        trustsCost: usage.usageIsIncomplete != true
                    ))
                } else {
                    points.append(contentsOf: modelUsage.map { model, usage in
                        Self.point(
                            usage: usage,
                            model: model,
                            timestamp: timestamp,
                            metadata: metadata,
                            sessionID: sessionID,
                            sourceFile: file.path,
                            sourceLine: index + 1,
                            trustsCost: usage.usageIsIncomplete != true
                        )
                    })
                }
            }
        }
        return points.sorted { $0.date < $1.date }
    }

    private static func point(
        usage: GrokSessionUsage,
        model: String,
        timestamp: Double,
        metadata: GrokSessionSummary?,
        sessionID: String,
        sourceFile: String,
        sourceLine: Int,
        trustsCost: Bool
    ) -> UsagePoint {
        let cwd = metadata?.info?.cwd?.trimmedNonEmpty
        return UsagePoint(
            service: .xaiAPI,
            model: model,
            date: Date(timeIntervalSince1970: timestamp),
            tokens: usage.tokens,
            estimatedCostUSD: trustsCost ? usage.costUSD : nil,
            sessionID: sessionID,
            sessionTitle: metadata?.generatedTitle?.trimmedNonEmpty,
            projectName: cwd.map { URL(fileURLWithPath: $0).lastPathComponent },
            cwd: cwd,
            repositoryPath: metadata?.gitRootDirectory?.trimmedNonEmpty,
            sourceFile: sourceFile,
            sourceLine: sourceLine,
            reasoningEffort: metadata?.reasoningEffort?.trimmedNonEmpty
        )
    }

    private static func totalTokens(_ points: [UsagePoint]) -> TokenTotals {
        points.reduce(.zero) { $0 + $1.tokens }
    }

    private static func totalCost(_ points: [UsagePoint]) -> Decimal? {
        let costs = points.compactMap(\.estimatedCostUSD)
        return costs.isEmpty ? nil : costs.reduce(0, +)
    }

    fileprivate static func apiDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func usedPercent(_ config: GrokBillingConfig?) -> Double? {
        if let value = config?.creditUsagePercent {
            return min(100, max(0, value))
        }
        guard let used = config?.used?.val,
              let limit = config?.monthlyLimit?.val,
              limit > 0
        else { return nil }
        let percent = NSDecimalNumber(decimal: used / limit * 100).doubleValue
        return min(100, max(0, percent))
    }

    private static func windowMinutes(start: Date?, end: Date?) -> Int {
        guard let start, let end, end > start else { return 7 * 24 * 60 }
        return max(1, Int(end.timeIntervalSince(start) / 60))
    }

    private static func defaultClient(
        request: URLRequest,
        timeout: TimeInterval
    ) async throws -> (statusCode: Int, data: Data) {
        var request = request
        request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw GrokCLIUsageError.invalidResponse
        }
        return (response.statusCode, data)
    }
}

private struct GrokSessionSummary: Decodable {
    var currentModelID: String?
    var generatedTitle: String?
    var reasoningEffort: String?
    var gitRootDirectory: String?
    var info: GrokSessionInfo?

    enum CodingKeys: String, CodingKey {
        case currentModelID = "current_model_id"
        case generatedTitle = "generated_title"
        case reasoningEffort = "reasoning_effort"
        case gitRootDirectory = "git_root_dir"
        case info
    }
}

private struct GrokSessionInfo: Decodable {
    var id: String?
    var cwd: String?
}

private struct GrokSessionEvent: Decodable {
    var timestamp: Double?
    var params: GrokSessionEventParams?
}

private struct GrokSessionEventParams: Decodable {
    var update: GrokSessionUpdate?
}

private struct GrokSessionUpdate: Decodable {
    var sessionUpdate: String?
    var usage: GrokSessionUsage?
}

private struct GrokSessionUsage: Decodable {
    var inputTokens: Int?
    var cachedReadTokens: Int?
    var outputTokens: Int?
    var reasoningTokens: Int?
    var totalTokens: Int?
    var costUsdTicks: Int64?
    var costIsPartial: Bool?
    var usageIsIncomplete: Bool?
    var modelUsage: [String: GrokSessionUsage]?

    var tokens: TokenTotals {
        let input = max(0, inputTokens ?? 0)
        let output = max(0, outputTokens ?? 0)
        return TokenTotals(
            input: input,
            cachedInput: min(input, max(0, cachedReadTokens ?? 0)),
            output: output,
            reasoningOutput: min(output, max(0, reasoningTokens ?? 0)),
            total: max(0, totalTokens ?? input + output)
        )
    }

    var costUSD: Decimal? {
        guard costIsPartial != true,
              let costUsdTicks, costUsdTicks >= 0,
              let ticks = Decimal(string: String(costUsdTicks))
        else { return nil }
        return ticks / 10_000_000_000
    }
}

private enum GrokCLIUsageError: LocalizedError {
    case authFileTooLarge
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .authFileTooLarge:
            "The Grok CLI authentication file is unexpectedly large."
        case .invalidResponse:
            "Grok returned an invalid response."
        }
    }
}

private struct GrokBillingResponse: Decodable {
    var config: GrokBillingConfig?
}

private struct GrokBillingConfig: Decodable {
    var creditUsagePercent: Double?
    var currentPeriod: GrokUsagePeriod?
    var monthlyLimit: GrokCent?
    var used: GrokCent?
    var onDemandCap: GrokCent?
    var onDemandUsed: GrokCent?
    var prepaidBalance: GrokCent?
    var billingPeriodStart: String?
    var billingPeriodEnd: String?
}

private struct GrokUsagePeriod: Decodable {
    var type: String?
    var start: String?
    var end: String?
}

private struct GrokCent: Decodable {
    var val: Decimal

    enum CodingKeys: String, CodingKey {
        case val
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        val = try container.decodeIfPresent(Decimal.self, forKey: .val) ?? 0
    }

    var usd: Decimal {
        val / 100
    }
}

private struct GrokRemoteSettings: Decodable {
    var subscriptionTierDisplay: String?

    enum CodingKeys: String, CodingKey {
        case subscriptionTierDisplay = "subscription_tier_display"
    }
}
