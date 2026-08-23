import Foundation

struct AntigravityUsageReader {
    typealias Client = @Sendable (URLRequest, TimeInterval) async throws -> (statusCode: Int, data: Data)
    typealias TokenRefresher = @Sendable (URL, String) async throws -> String

    private struct AuthRoot: Decodable {
        var googleAntigravity: AuthSet?
        enum CodingKeys: String, CodingKey { case googleAntigravity = "google-antigravity" }
    }

    private struct AuthSet: Decodable {
        var activeAccountId: String?
        var accounts: [AuthAccount]
    }

    private struct AuthAccount: Decodable, Sendable {
        struct Credential: Decodable, Sendable {
            var access: String
            var refresh: String
            var expires: Double
            var email: String?
            var projectId: String
        }
        var id: String
        var credential: Credential
    }

    private struct GoogleQuota: Decodable {
        struct Group: Decodable {
            struct Bucket: Decodable {
                var window: String
                var remainingFraction: Double
                var resetTime: String?
                var disabled: Bool?
            }
            var displayName: String
            var buckets: [Bucket]
        }
        var groups: [Group]
    }

    private struct AgyEnvelope: Decodable {
        struct Command: Decodable {
            struct DataPayload: Decodable { var groups: [Group] }
            var data: DataPayload
        }
        var command: Command
    }

    private struct Group: Decodable {
        struct Bucket: Decodable {
            var window: String
            var remainingFraction: Double
            var resetTime: String?
            enum CodingKeys: String, CodingKey {
                case window
                case remainingFraction = "remaining_fraction"
                case resetTime = "reset_time"
            }
        }
        var name: String
        var buckets: [Bucket]
    }

    private struct Window {
        var kind: String
        var usedPercent: Double
        var resetsAt: Date?
    }

    var homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    var now: @Sendable () -> Date = Date.init
    var client: Client = Self.defaultClient
    var tokenRefresher: TokenRefresher = Self.refreshWithInstalledOpenCodex

    func read() async -> UsageSnapshot? {
        let refreshedAt = now()
        if let set = openCodexAccounts(), !set.accounts.isEmpty {
            let rows = await withTaskGroup(of: (Int, [UsageAccount]).self) { group in
                for (index, account) in set.accounts.enumerated() {
                    group.addTask {
                        do {
                            let accessToken = try await accessToken(account: account, refreshedAt: refreshedAt)
                            let data = try await fetchQuota(account: account, accessToken: accessToken)
                            return (index, Self.googleAccounts(
                                data: data,
                                accountID: account.id,
                                identity: Self.maskedEmail(account.credential.email),
                                active: account.id == set.activeAccountId,
                                refreshedAt: refreshedAt
                            ) ?? [Self.unavailableAccount(account, activeID: set.activeAccountId, refreshedAt: refreshedAt)])
                        } catch {
                            return (index, [Self.unavailableAccount(account, activeID: set.activeAccountId, refreshedAt: refreshedAt)])
                        }
                    }
                }
                var results: [(Int, [UsageAccount])] = []
                for await result in group { results.append(result) }
                return results.sorted { $0.0 < $1.0 }.flatMap(\.1)
            }
            return Self.snapshot(
                accounts: rows,
                refreshedAt: refreshedAt,
                source: "Read-only Google quota using OpenCodex account credentials in memory; AgentBar never stores or logs them."
            )
        }

        guard let executable = executable(named: "agy") else { return nil }
        guard let result = try? await AsyncProcessRunner.run(
            executableURL: executable,
            arguments: ["-p", "/usage", "--output-format", "json"],
            maximumOutputBytes: 1_048_576,
            timeout: 30
        ), result.exitStatus == 0, !result.timedOut,
              let snapshot = Self.agySnapshot(data: result.stdout, refreshedAt: refreshedAt)
        else { return Self.unavailableSnapshot(refreshedAt: refreshedAt) }
        return snapshot
    }

    static func googleAccounts(
        data: Data,
        accountID: String,
        identity: String?,
        active: Bool,
        refreshedAt: Date
    ) -> [UsageAccount]? {
        guard let quota = try? JSONDecoder().decode(GoogleQuota.self, from: data), !quota.groups.isEmpty else { return nil }
        return quota.groups.map { group in
            let windows = group.buckets.compactMap { bucket -> Window? in
                guard bucket.disabled != true else { return nil }
                return Window(
                    kind: bucket.window,
                    usedPercent: (1 - bucket.remainingFraction) * 100,
                    resetsAt: iso8601Date(bucket.resetTime)
                )
            }
            return usageAccount(
                id: accountID,
                name: group.displayName,
                identity: identity,
                windows: windows,
                active: active,
                unavailable: false,
                source: "OpenCodex login · Google Antigravity",
                refreshedAt: refreshedAt
            )
        }
    }

    static func agySnapshot(data: Data, refreshedAt: Date) -> UsageSnapshot? {
        guard let envelope = try? JSONDecoder().decode(AgyEnvelope.self, from: data),
              !envelope.command.data.groups.isEmpty
        else { return nil }
        let accounts = envelope.command.data.groups.map { group in
            usageAccount(
                id: "agy",
                name: group.name,
                identity: nil,
                windows: group.buckets.map {
                    Window(
                        kind: $0.window,
                        usedPercent: (1 - $0.remainingFraction) * 100,
                        resetsAt: iso8601Date($0.resetTime)
                    )
                },
                active: true,
                unavailable: false,
                source: "Antigravity CLI · /usage",
                refreshedAt: refreshedAt
            )
        }
        return snapshot(
            accounts: accounts,
            refreshedAt: refreshedAt,
            source: "Read-only quota from the installed Antigravity CLI; AgentBar does not read or store its credentials."
        )
    }

    private func openCodexAccounts() -> AuthSet? {
        let url = homeDirectory.appendingPathComponent(".opencodex/auth.json")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue <= 2_000_000,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(AuthRoot.self, from: data).googleAntigravity
    }

    private func accessToken(account: AuthAccount, refreshedAt: Date) async throws -> String {
        if account.credential.expires > refreshedAt.timeIntervalSince1970 * 1_000 + 60_000 {
            return account.credential.access
        }
        return try await tokenRefresher(homeDirectory, account.credential.refresh)
    }

    private func fetchQuota(account: AuthAccount, accessToken: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("antigravity/cli/1.0.13 (aidev_client; os_type=darwin; arch=arm64)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["project": account.credential.projectId])
        let response = try await client(request, 15)
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
        return response.data
    }

    private static func unavailableAccount(_ account: AuthAccount, activeID: String?, refreshedAt: Date) -> UsageAccount {
        usageAccount(
            id: account.id,
            name: "Google Antigravity",
            identity: maskedEmail(account.credential.email),
            windows: [],
            active: account.id == activeID,
            unavailable: true,
            source: "OpenCodex login · Google Antigravity",
            refreshedAt: refreshedAt
        )
    }

    private static func usageAccount(
        id: String,
        name: String,
        identity: String?,
        windows: [Window],
        active: Bool,
        unavailable: Bool,
        source: String,
        refreshedAt: Date
    ) -> UsageAccount {
        func window(_ kind: UsageWindow.Kind, name: String) -> UsageWindow? {
            guard let value = windows.first(where: { $0.kind == name }) else { return nil }
            return UsageWindow(
                kind: kind,
                usedPercent: min(max(value.usedPercent, 0), 100),
                windowMinutes: kind == .fiveHour ? 300 : 10_080,
                resetsAt: value.resetsAt
            )
        }
        return UsageAccount(
            id: "google-antigravity:\(id):\(name)",
            service: .antigravity,
            displayName: name,
            username: identity,
            maskedEmail: nil,
            plan: nil,
            sourceDescription: source,
            status: unavailable ? .unavailable : .live,
            fiveHourWindow: window(.fiveHour, name: "5h"),
            weeklyWindow: window(.weekly, name: "weekly"),
            tokens: .zero,
            estimatedCostUSD: nil,
            lastUpdated: refreshedAt,
            isActive: active,
            loginWarning: unavailable ? .quotaUnavailable : nil
        )
    }

    private static func snapshot(accounts: [UsageAccount], refreshedAt: Date, source: String) -> UsageSnapshot {
        UsageSnapshot(
            service: .antigravity,
            status: accounts.contains { $0.status == .live } ? .live : .unavailable,
            accounts: accounts,
            points: [],
            securityNotes: [source],
            refreshedAt: refreshedAt,
            pricingFingerprint: "google-antigravity-quota-v1"
        )
    }

    private static func unavailableSnapshot(refreshedAt: Date) -> UsageSnapshot {
        snapshot(
            accounts: [usageAccount(
                id: "agy",
                name: "Google Antigravity",
                identity: nil,
                windows: [],
                active: true,
                unavailable: true,
                source: "Antigravity CLI · /usage",
                refreshedAt: refreshedAt
            )],
            refreshedAt: refreshedAt,
            source: "Google Antigravity quota could not be refreshed."
        )
    }

    private static func maskedEmail(_ email: String?) -> String? {
        guard let email, let at = email.firstIndex(of: "@") else { return nil }
        return "\(email.prefix(1))***\(email[at...])"
    }

    private static func iso8601Date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func executable(named name: String) -> URL? {
        Self.executable(named: name, homeDirectory: homeDirectory)
    }

    private static func executable(named name: String, homeDirectory: URL) -> URL? {
        var candidates = [
            homeDirectory.appendingPathComponent(".local/bin/\(name)"),
            URL(fileURLWithPath: "/opt/homebrew/bin/\(name)"),
            URL(fileURLWithPath: "/usr/local/bin/\(name)")
        ]
        let versionsDirectory = homeDirectory.appendingPathComponent(".nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(at: versionsDirectory, includingPropertiesForKeys: nil) {
            candidates.append(contentsOf: versions.map { $0.appendingPathComponent("bin/\(name)") })
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func refreshWithInstalledOpenCodex(homeDirectory: URL, refreshToken: String) async throws -> String {
        guard let ocx = executable(named: "ocx", homeDirectory: homeDirectory) else {
            throw URLError(.cannotFindHost)
        }
        let packageRoot = ocx.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        let module = packageRoot.appendingPathComponent("src/oauth/google-antigravity.ts")
        let bundledBun = packageRoot.appendingPathComponent("node_modules/bun/bin/bun.exe")
        let bun = FileManager.default.isExecutableFile(atPath: bundledBun.path)
            ? bundledBun
            : executable(named: "bun", homeDirectory: homeDirectory)
        guard FileManager.default.fileExists(atPath: module.path), let bun else {
            throw URLError(.cannotOpenFile)
        }
        let script = "const m=await import(process.argv[1]);const r=(await Bun.stdin.text()).trim();const c=await m.refreshAntigravityToken(r);process.stdout.write(c.access);"
        let result = try await AsyncProcessRunner.run(
            executableURL: bun,
            arguments: ["-e", script, module.absoluteString],
            standardInput: Data(refreshToken.utf8),
            maximumOutputBytes: 65_536,
            timeout: 30
        )
        guard result.exitStatus == 0, !result.timedOut,
              let access = String(data: result.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !access.isEmpty
        else { throw URLError(.userAuthenticationRequired) }
        return access
    }

    private static func defaultClient(
        request: URLRequest,
        timeout: TimeInterval
    ) async throws -> (statusCode: Int, data: Data) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (response.statusCode, data)
    }
}
