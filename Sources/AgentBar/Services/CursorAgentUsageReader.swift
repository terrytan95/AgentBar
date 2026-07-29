import Foundation

struct CursorSubscriptionUsage: Codable, Equatable, Sendable {
    var includedUsedPercent: Double
    var autoUsedPercent: Double
    var apiUsedPercent: Double
    var onDemandUsedUSD: Decimal?
    var onDemandLimitUSD: Decimal?
    var periodEndsAt: Date?

    func summaryLines(language: AppLanguage) -> [String] {
        var lines = [
            "\(L.text("included_usage", language)): \(DisplayFormatters.percentString(includedUsedPercent)) \(L.text("used", language))",
            "\(L.text("auto_usage", language)): \(DisplayFormatters.percentString(autoUsedPercent)) \(L.text("used", language))",
            "\(L.text("api_usage", language)): \(DisplayFormatters.percentString(apiUsedPercent)) \(L.text("used", language))"
        ]
        if let onDemandUsedUSD {
            let value = onDemandLimitUSD.map {
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

enum CursorAgentCredentialStore {
    static func accessToken() throws -> String? {
        let result = try AsyncProcessRunner.runBlocking(
            executableURL: URL(fileURLWithPath: "/usr/bin/security"),
            arguments: [
                "find-generic-password",
                "-a", "cursor-user",
                "-s", "cursor-access-token",
                "-w"
            ],
            maximumOutputBytes: 4_096,
            timeout: 5
        )
        guard !result.timedOut else {
            throw CursorAgentUsageError.credentialReadTimedOut
        }
        guard result.exitStatus == 0 else {
            if result.exitStatus == 44 { return nil }
            throw CursorAgentUsageError.credentialReadFailed(result.exitStatus)
        }
        return String(data: result.stdout, encoding: .utf8)?.trimmedNonEmpty
    }
}

enum CursorAgentSessionRefresher {
    static func refresh(homeDirectory: URL) -> Bool {
        guard let executable = executableURL(homeDirectory: homeDirectory) else { return false }
        guard let result = try? AsyncProcessRunner.runBlocking(
            executableURL: executable,
            arguments: ["status", "--format", "json"],
            maximumOutputBytes: 0,
            timeout: 10
        ) else { return false }
        return !result.timedOut && result.exitStatus == 0
    }

    private static func executableURL(homeDirectory: URL) -> URL? {
        [
            homeDirectory.appendingPathComponent(".local/bin/cursor-agent"),
            homeDirectory.appendingPathComponent(".local/bin/agent"),
            URL(fileURLWithPath: "/opt/homebrew/bin/cursor-agent"),
            URL(fileURLWithPath: "/usr/local/bin/cursor-agent")
        ].first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

struct CursorAgentUsageReader {
    typealias Client = @Sendable (URLRequest, TimeInterval) async throws -> (statusCode: Int, data: Data)
    typealias CredentialProvider = @Sendable () throws -> String?

    var homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    var now: @Sendable () -> Date = Date.init
    var client: Client = Self.defaultClient
    var credentialProvider: CredentialProvider = CursorAgentCredentialStore.accessToken
    var sessionRefresher: @Sendable (URL) -> Bool = CursorAgentSessionRefresher.refresh
    var timeout: TimeInterval = 15

    func read() async -> UsageSnapshot? {
        let refreshedAt = now()
        let accessToken: String
        do {
            guard let storedToken = try credentialProvider() else { return nil }
            accessToken = storedToken
        } catch {
            return issueSnapshot(
                status: .unavailable,
                refreshedAt: refreshedAt,
                note: "AgentBar could not read the Cursor Agent login from macOS Keychain: \(error.localizedDescription.redactedForCredentialWords)"
            )
        }

        do {
            var response = try await fetch(accessToken: accessToken)
            if response.usage.statusCode == 401 || response.usage.statusCode == 403,
               sessionRefresher(homeDirectory),
               let refreshedToken = try? credentialProvider()
            {
                response = try await fetch(accessToken: refreshedToken)
            }

            switch response.usage.statusCode {
            case 200:
                return try liveSnapshot(response: response, refreshedAt: refreshedAt)
            case 401, 403:
                return issueSnapshot(
                    status: .needsAuthorization,
                    refreshedAt: refreshedAt,
                    note: "The Cursor Agent session is no longer authorized (HTTP \(response.usage.statusCode)). Run `cursor-agent login`, then refresh AgentBar."
                )
            default:
                return issueSnapshot(
                    status: .unavailable,
                    refreshedAt: refreshedAt,
                    note: "Cursor Agent subscription usage is unavailable (HTTP \(response.usage.statusCode))."
                )
            }
        } catch {
            return issueSnapshot(
                status: .unavailable,
                refreshedAt: refreshedAt,
                note: "Cursor Agent subscription usage could not be refreshed: \(error.localizedDescription.redactedForCredentialWords)"
            )
        }
    }

    private func fetch(accessToken: String) async throws -> CursorAgentResponses {
        async let plan = try? client(request(method: "GetPlanInfo", accessToken: accessToken), timeout)
        async let hardLimit = try? client(request(method: "GetHardLimit", accessToken: accessToken), timeout)
        let usage = try await client(request(method: "GetCurrentPeriodUsage", accessToken: accessToken), timeout)
        return await CursorAgentResponses(usage: usage, plan: plan, hardLimit: hardLimit)
    }

    private func request(method: String, accessToken: String) -> URLRequest {
        var request = URLRequest(
            url: URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/\(method)")!
        )
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("agentbar", forHTTPHeaderField: "x-cursor-client-version")
        request.setValue("true", forHTTPHeaderField: "x-ghost-mode")
        return request
    }

    private func liveSnapshot(
        response: CursorAgentResponses,
        refreshedAt: Date
    ) throws -> UsageSnapshot {
        let usage = try JSONDecoder().decode(CursorCurrentPeriodUsageResponse.self, from: response.usage.data)
        guard let planUsage = usage.planUsage else {
            throw CursorAgentUsageError.usageDetailsUnavailable
        }
        let planResponse = response.plan
            .flatMap { $0.statusCode == 200 ? $0.data : nil }
            .flatMap { try? JSONDecoder().decode(CursorPlanInfoResponse.self, from: $0) }
        let planInfo = planResponse?.planInfo
        let hardLimit = response.hardLimit
            .flatMap { $0.statusCode == 200 ? $0.data : nil }
            .flatMap { try? JSONDecoder().decode(CursorHardLimitResponse.self, from: $0) }
        let includedPercent = planUsage.totalPercentUsed
            ?? Self.percent(used: planUsage.includedSpend, limit: planUsage.limit)
            ?? 0
        let onDemandUsed = usage.spendLimitUsage?.individualUsed.map(Self.dollarsFromCents)
        let personalHardLimit: Decimal? = hardLimit.flatMap {
            guard $0.noUsageBasedAllowed != true,
                  let value = $0.hardLimit,
                  value > 0,
                  value < Int(Int32.max)
            else { return nil }
            return Decimal(value)
        }
        let onDemandLimit = usage.spendLimitUsage?.individualLimit.map(Self.dollarsFromCents)
            ?? (usage.spendLimitUsage?.limitType == "team" ? nil : personalHardLimit)
        let subscription = CursorSubscriptionUsage(
            includedUsedPercent: includedPercent,
            autoUsedPercent: planUsage.autoPercentUsed ?? 0,
            apiUsedPercent: planUsage.apiPercentUsed ?? 0,
            onDemandUsedUSD: onDemandUsed,
            onDemandLimitUSD: onDemandLimit,
            periodEndsAt: Self.date(milliseconds: usage.billingCycleEnd ?? planInfo?.billingCycleEnd)
        )
        let account = UsageAccount(
            id: "cursor-agent",
            service: .cursorAgent,
            displayName: "Cursor Agent",
            username: nil,
            maskedEmail: nil,
            plan: planInfo?.planName.flatMap {
                let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            } ?? "Subscription",
            sourceDescription: "Cursor Agent CLI · subscription usage",
            status: .live,
            fiveHourWindow: nil,
            weeklyWindow: nil,
            tokens: .zero,
            estimatedCostUSD: nil,
            lastUpdated: refreshedAt,
            isActive: true,
            cursorSubscriptionUsage: subscription
        )
        return UsageSnapshot(
            service: .cursorAgent,
            status: .live,
            accounts: [account],
            points: [],
            securityNotes: [
                "Read-only Cursor Agent subscription usage. AgentBar reads the existing macOS Keychain login in memory and never stores or logs the access token."
            ],
            refreshedAt: refreshedAt,
            pricingFingerprint: "cursor-agent-subscription-v1"
        )
    }

    private func issueSnapshot(
        status: DataSourceStatus,
        refreshedAt: Date,
        note: String
    ) -> UsageSnapshot {
        UsageSnapshot(
            service: .cursorAgent,
            status: status,
            accounts: [
                UsageAccount(
                    id: "cursor-agent",
                    service: .cursorAgent,
                    displayName: "Cursor Agent",
                    username: nil,
                    maskedEmail: nil,
                    plan: nil,
                    sourceDescription: "Cursor Agent CLI · subscription usage",
                    status: status,
                    fiveHourWindow: nil,
                    weeklyWindow: nil,
                    tokens: .zero,
                    estimatedCostUSD: nil,
                    lastUpdated: nil,
                    isActive: true
                )
            ],
            points: [],
            securityNotes: [note],
            refreshedAt: refreshedAt,
            pricingFingerprint: "cursor-agent-subscription-v1"
        )
    }

    private static func percent(used: Double?, limit: Double?) -> Double? {
        guard let used, let limit, limit > 0 else { return nil }
        return used / limit * 100
    }

    private static func dollarsFromCents(_ cents: Int) -> Decimal {
        Decimal(cents) / 100
    }

    private static func date(milliseconds: String?) -> Date? {
        guard let milliseconds, let value = Double(milliseconds), value > 0 else { return nil }
        return Date(timeIntervalSince1970: value / 1_000)
    }

    private static func defaultClient(
        request: URLRequest,
        timeout: TimeInterval
    ) async throws -> (statusCode: Int, data: Data) {
        var request = request
        request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw CursorAgentUsageError.invalidResponse
        }
        return (response.statusCode, data)
    }
}

private struct CursorAgentResponses {
    var usage: (statusCode: Int, data: Data)
    var plan: (statusCode: Int, data: Data)?
    var hardLimit: (statusCode: Int, data: Data)?
}

private struct CursorCurrentPeriodUsageResponse: Decodable {
    var billingCycleEnd: String?
    var planUsage: CursorPlanUsage?
    var spendLimitUsage: CursorSpendLimitUsage?
}

private struct CursorPlanUsage: Decodable {
    var includedSpend: Double?
    var limit: Double?
    var totalPercentUsed: Double?
    var autoPercentUsed: Double?
    var apiPercentUsed: Double?
}

private struct CursorSpendLimitUsage: Decodable {
    var individualUsed: Int?
    var individualLimit: Int?
    var limitType: String?
}

private struct CursorPlanInfoResponse: Decodable {
    var planInfo: CursorPlanInfo?
}

private struct CursorPlanInfo: Decodable {
    var planName: String?
    var billingCycleEnd: String?
}

private struct CursorHardLimitResponse: Decodable {
    var hardLimit: Int?
    var noUsageBasedAllowed: Bool?
}

private enum CursorAgentUsageError: LocalizedError {
    case credentialReadTimedOut
    case credentialReadFailed(Int32)
    case invalidResponse
    case usageDetailsUnavailable

    var errorDescription: String? {
        switch self {
        case .credentialReadTimedOut:
            "Cursor Agent credential lookup timed out."
        case let .credentialReadFailed(status):
            "Cursor Agent credential lookup failed with status \(status)."
        case .invalidResponse:
            "Cursor Agent returned an invalid response."
        case .usageDetailsUnavailable:
            "Usage details are not available for this Cursor plan."
        }
    }
}
