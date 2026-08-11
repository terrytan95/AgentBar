import Foundation

enum CodexUsageSyncResult: Equatable, Sendable {
    case success
    case unavailable(String)
    case failed(String)
    case timedOut

    var note: String? {
        switch self {
        case .success:
            return nil
        case let .unavailable(message):
            return "Codex usage API sync unavailable: \(message.redactedForCredentialWords); using local registry and session cache."
        case let .failed(message):
            return "Codex usage API sync failed: \(message.redactedForCredentialWords); using local registry and session cache."
        case .timedOut:
            return "Codex usage API sync timed out; using local registry and session cache."
        }
    }
}

struct CodexUsageAPIResponse: Sendable {
    var statusCode: Int
    var data: Data
}

struct CodexUsageAPISyncer {
    typealias UsageClient = @Sendable (URLRequest, TimeInterval) async throws -> CodexUsageAPIResponse

    static let usageEndpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    static let resetCreditsEndpoint = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!

    var homeDirectory: URL
    var fileManager: FileManager
    var now: @Sendable () -> Date
    var usageClient: UsageClient
    var timeout: TimeInterval
    var reusesCLIProxyAPIAuth: Bool
    var reusesOpenCodexAuth: Bool
    var cliProxyAPIAuthDirectory: String
    var accountPollDelay: Duration
    var resetCreditsCacheDuration: TimeInterval

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init,
        usageClient: @escaping UsageClient = Self.defaultUsageClient,
        timeout: TimeInterval = 5,
        reusesCLIProxyAPIAuth: Bool = false,
        reusesOpenCodexAuth: Bool = false,
        cliProxyAPIAuthDirectory: String = "",
        accountPollDelay: Duration = .zero,
        resetCreditsCacheDuration: TimeInterval = 0
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.now = now
        self.usageClient = usageClient
        self.timeout = timeout
        self.reusesCLIProxyAPIAuth = reusesCLIProxyAPIAuth
        self.reusesOpenCodexAuth = reusesOpenCodexAuth
        self.cliProxyAPIAuthDirectory = cliProxyAPIAuthDirectory
        self.accountPollDelay = accountPollDelay
        self.resetCreditsCacheDuration = resetCreditsCacheDuration
    }

    func refreshUsage(refreshAllAccounts: Bool = false) async -> CodexUsageSyncResult {
        let storage = CodexAccountStorage(homeDirectory: homeDirectory, fileManager: fileManager)
        let registryURL = storage.registryURL
        let openCodexReader = OpenCodexAuthReader(
            homeDirectory: homeDirectory,
            now: now
        )
        let openCodexDiscovery = reusesOpenCodexAuth
            ? openCodexReader.discover()
            : CLIProxyCodexDiscovery(credentials: [], scanCompleted: true, hasBroadReadPermissions: false)
        let cliProxyDiscovery = reusesCLIProxyAPIAuth
            ? CLIProxyCodexAuthReader(
                homeDirectory: homeDirectory,
                configuredDirectory: cliProxyAPIAuthDirectory,
                now: now
            ).discover()
            : CLIProxyCodexDiscovery(credentials: [], scanCompleted: true, hasBroadReadPermissions: false)
        let discovery = CLIProxyCodexDiscovery.merged([
            cliProxyDiscovery,
            openCodexDiscovery
        ])
        let openCodexActiveAccountID = reusesOpenCodexAuth
            ? await openCodexReader.activeAccountID()
            : nil

        let registryData = try? storage.readRegistryBootstrappingActiveAccount(now: now())
        let parsedRegistry = registryData
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        guard parsedRegistry != nil || !discovery.credentials.isEmpty else {
            return .unavailable("Codex account registry was not found or could not be parsed.")
        }
        var registry = parsedRegistry ?? [:]
        let originalRegistry = registry
        var accounts = registry["accounts"] as? [[String: Any]] ?? []
        accounts = Self.reconcileCLIProxyAccounts(
            accounts,
            discovery: discovery
        )
        Self.promoteNativeAccounts(&accounts, storage: storage, fileManager: fileManager)
        let openCodexActiveAccountKey = openCodexActiveAccountID
            .flatMap { activeID in
                discovery.credentials.first { $0.openCodexAccountID == activeID }
            }
            .flatMap { credential in
                Self.activeAccountKey(in: accounts, matching: credential.identity)
            }
        if let openCodexActiveAccountKey {
            registry["active_account_key"] = openCodexActiveAccountKey
        }
        registry["accounts"] = accounts
        if discovery.scanCompleted, discovery.hasBroadReadPermissions {
            registry[CLIProxyCodexRegistryMetadata.broadReadPermissions] = true
        } else if discovery.scanCompleted {
            registry.removeValue(forKey: CLIProxyCodexRegistryMetadata.broadReadPermissions)
        }
        if !Self.jsonValue(originalRegistry, equals: registry) {
            do {
                try fileManager.createDirectory(at: storage.accountsDirectory, withIntermediateDirectories: true)
                try storage.writeRegistry(registry)
            } catch {
                return .failed(error.localizedDescription)
            }
        }

        let activeAuthIdentity = (try? Data(contentsOf: storage.activeAuthURL))
            .flatMap(CodexAccountStorage.chatGPTAuthIdentity)
        let activeAccountKey = openCodexActiveAccountKey
            ?? Self.activeAccountKey(in: accounts, matching: activeAuthIdentity)
            ?? registry["active_account_key"] as? String
        guard let activeAccountIndex = accounts.firstIndex(where: { account in
            (account["account_key"] as? String) == activeAccountKey
        }) ?? accounts.indices.first else {
            return .unavailable("No active ChatGPT account was available for usage refresh.")
        }

        let refreshStartedAt = now().timeIntervalSince1970
        let inactiveRefreshCutoff = refreshStartedAt - 60 * 60
        let inactiveIndexes = accounts.indices.filter { index in
            guard index != activeAccountIndex else { return false }
            if refreshAllAccounts { return true }
            let lastRefreshAt = Self.firstNumber([
                accounts[index]["agentbar_last_usage_refresh_at"],
                accounts[index]["last_usage_at"]
            ])?.doubleValue ?? -.infinity
            return lastRefreshAt <= inactiveRefreshCutoff
        }
        let refreshIndexes = [activeAccountIndex] + inactiveIndexes

        var activeResult: CodexUsageSyncResult?
        var updatedFieldsByAccountKey: [String: Set<String>] = [:]
        var requestedAccountCount = 0

        for index in refreshIndexes {
            if let authMode = accounts[index]["auth_mode"] as? String,
               authMode.localizedCaseInsensitiveCompare("apikey") == .orderedSame {
                continue
            }
            guard let accountKey = accounts[index]["account_key"] as? String,
                  !accountKey.isEmpty
            else {
                continue
            }
            let accountSnapshotURL = storage.accountAuthURL(for: accountKey)
            let authURL = preferredAuthURL(
                for: accountKey,
                activeAccountKey: activeAccountKey,
                accountSnapshotURL: accountSnapshotURL,
                storage: storage,
                activeAuthMatchesAccount: Self.account(accounts[index], matches: activeAuthIdentity)
            )
            let nativeAuthData = try? Data(contentsOf: authURL)
            var authCandidates: [(authInfo: CodexUsageAuthInfo, usesExternalCredential: Bool)] = []
            if let nativeAuthInfo = nativeAuthData.flatMap(CodexAccountStorage.usageAuthInfo) {
                authCandidates.append((nativeAuthInfo, false))
            }
            for externalDiscovery in [openCodexDiscovery, cliProxyDiscovery] {
                if let credential = externalDiscovery.credentials.first(where: {
                    Self.account(accounts[index], matches: $0.identity)
                }) {
                    authCandidates.append((credential.authInfo, true))
                }
            }
            guard !authCandidates.isEmpty else {
                continue
            }

            if requestedAccountCount > 0, accountPollDelay > .zero {
                do {
                    try await Task.sleep(for: accountPollDelay)
                } catch {
                    return activeResult ?? .timedOut
                }
            }
            requestedAccountCount += 1

            if index != activeAccountIndex {
                accounts[index]["agentbar_last_usage_refresh_at"] = now().timeIntervalSince1970
                updatedFieldsByAccountKey[accountKey, default: []].insert("agentbar_last_usage_refresh_at")
            }
            var response: CodexUsageAPIResponse?
            var selectedAuth: (authInfo: CodexUsageAuthInfo, usesExternalCredential: Bool)?
            var triedAccessTokens = Set<String>()
            do {
                for candidate in authCandidates where triedAccessTokens.insert(candidate.authInfo.accessToken).inserted {
                    var request = URLRequest(url: Self.usageEndpoint)
                    request.httpMethod = "GET"
                    request.timeoutInterval = timeout
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    request.setValue("AgentBar", forHTTPHeaderField: "User-Agent")
                    request.setValue("Bearer \(candidate.authInfo.accessToken)", forHTTPHeaderField: "Authorization")
                    request.setValue(candidate.authInfo.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
                    selectedAuth = candidate
                    response = try await usageClient(request, timeout)
                    if response?.statusCode != 401 { break }
                }
            } catch let error as URLError where error.code == .timedOut {
                if index == activeAccountIndex { activeResult = .timedOut }
                continue
            } catch {
                if index == activeAccountIndex { activeResult = .failed(error.localizedDescription) }
                continue
            }
            guard let response, let selectedAuth else { continue }
            let authInfo = selectedAuth.authInfo
            let usesExternalCredential = selectedAuth.usesExternalCredential

            guard 200..<300 ~= response.statusCode else {
                if response.statusCode == 401 {
                    accounts[index]["agentbar_auth_error"] = [
                        "status_code": 401,
                        "detected_at": now().timeIntervalSince1970
                    ]
                    updatedFieldsByAccountKey[accountKey, default: []].insert("agentbar_auth_error")
                }
                if index == activeAccountIndex {
                    activeResult = .failed("HTTP \(response.statusCode)\(Self.responseErrorCode(from: response.data))")
                }
                continue
            }
            guard var usage = Self.parseUsageResponse(data: response.data) else {
                if index == activeAccountIndex {
                    activeResult = .failed("Usage response did not contain rate limit windows.")
                }
                continue
            }
            let previousUsage = accounts[index]["last_usage"] as? [String: Any]
            let previousResetCredits = previousUsage?["reset_credits"]
            let detailedResetCreditsAttemptedAt = Self.firstNumber([
                accounts[index]["agentbar_reset_credits_refresh_at"]
            ])?.doubleValue ?? -.infinity
            let hasRecentDetailAttempt = detailedResetCreditsAttemptedAt >
                refreshStartedAt - resetCreditsCacheDuration
            if Self.hasCompleteResetCredits(usage["reset_credits"]) {
                // The main usage response is authoritative, including an explicit zero.
            } else if hasRecentDetailAttempt {
                if usage["reset_credits"] == nil, let previousResetCredits {
                    usage["reset_credits"] = previousResetCredits
                }
            } else {
                accounts[index]["agentbar_reset_credits_refresh_at"] = refreshStartedAt
                updatedFieldsByAccountKey[accountKey, default: []].insert("agentbar_reset_credits_refresh_at")
                if let detailedResetCredits = await fetchDetailedResetCredits(authInfo: authInfo) {
                    usage["reset_credits"] = detailedResetCredits
                } else if usage["reset_credits"] == nil, let previousResetCredits {
                    usage["reset_credits"] = previousResetCredits
                }
            }

            if !usesExternalCredential,
               authURL != accountSnapshotURL,
               let nativeAuthData {
                do {
                    try nativeAuthData.write(to: accountSnapshotURL, options: [.atomic])
                } catch {
                    if index == activeAccountIndex { activeResult = .failed(error.localizedDescription) }
                    continue
                }
            }
            if accounts[index]["agentbar_auth_error"] != nil {
                accounts[index].removeValue(forKey: "agentbar_auth_error")
                updatedFieldsByAccountKey[accountKey, default: []].insert("agentbar_auth_error")
            }
            if !Self.jsonValue(accounts[index]["last_usage"], equals: usage) {
                accounts[index]["last_usage"] = usage
                accounts[index]["last_usage_at"] = now().timeIntervalSince1970
                updatedFieldsByAccountKey[accountKey, default: []].formUnion(["last_usage", "last_usage_at"])
            }
            if index == activeAccountIndex { activeResult = .success }
        }

        if !updatedFieldsByAccountKey.isEmpty {
            do {
                let latestData = try Data(contentsOf: registryURL)
                guard var latestRegistry = try JSONSerialization.jsonObject(with: latestData) as? [String: Any],
                      var latestAccounts = latestRegistry["accounts"] as? [[String: Any]]
                else {
                    return .failed("Codex account registry could not be parsed after usage refresh.")
                }
                var refreshedAccounts: [String: [String: Any]] = [:]
                for account in accounts {
                    guard let accountKey = account["account_key"] as? String else { continue }
                    refreshedAccounts[accountKey] = account
                }
                for index in latestAccounts.indices {
                    guard let accountKey = latestAccounts[index]["account_key"] as? String,
                          let updatedFields = updatedFieldsByAccountKey[accountKey],
                          let refreshedAccount = refreshedAccounts[accountKey]
                    else { continue }
                    for field in updatedFields {
                        latestAccounts[index][field] = refreshedAccount[field]
                    }
                }
                latestRegistry["accounts"] = latestAccounts
                try storage.writeRegistry(latestRegistry)
            } catch {
                return .failed(error.localizedDescription)
            }
        }

        return activeResult ?? .unavailable("No active ChatGPT account auth snapshot was available for usage refresh.")
    }

    private func preferredAuthURL(
        for accountKey: String,
        activeAccountKey: String?,
        accountSnapshotURL: URL,
        storage: CodexAccountStorage,
        activeAuthMatchesAccount: Bool
    ) -> URL {
        let activeAuthURL = storage.activeAuthURL
        if activeAuthMatchesAccount { return activeAuthURL }
        guard accountKey == activeAccountKey else { return accountSnapshotURL }
        guard let activeModifiedAt = modificationDate(activeAuthURL) else { return accountSnapshotURL }
        let snapshotModifiedAt = modificationDate(accountSnapshotURL) ?? .distantPast
        return activeModifiedAt > snapshotModifiedAt ? activeAuthURL : accountSnapshotURL
    }

    private func modificationDate(_ url: URL) -> Date? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.modificationDate] as? Date
    }

    private static func defaultUsageClient(request: URLRequest, timeout: TimeInterval) async throws -> CodexUsageAPIResponse {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
        }

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return CodexUsageAPIResponse(statusCode: statusCode, data: data)
    }

    private static func parseUsageResponse(data: Data) -> [String: Any]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var snapshot: [String: Any] = [:]
        if let planType = root["plan_type"] as? String, !planType.isEmpty {
            snapshot["plan_type"] = planType
        }
        if let rateLimit = root["rate_limit"] as? [String: Any] {
            if let primary = parseWindow(rateLimit["primary_window"]) {
                snapshot["primary"] = primary
            }
            if let secondary = parseWindow(rateLimit["secondary_window"]) {
                snapshot["secondary"] = secondary
            }
        }
        if let credits = parseCredits(root["credits"]) {
            snapshot["credits"] = credits
        }
        if let resetCredits = parseResetCredits(root["rate_limit_reset_credits"]) {
            snapshot["reset_credits"] = resetCredits
        }

        guard snapshot["primary"] != nil || snapshot["secondary"] != nil else {
            return nil
        }
        return snapshot
    }

    private static func parseWindow(_ value: Any?) -> [String: Any]? {
        guard let object = value as? [String: Any],
              let usedPercent = number(object["used_percent"])?.doubleValue
        else {
            return nil
        }
        var window: [String: Any] = ["used_percent": usedPercent]
        if let seconds = number(object["limit_window_seconds"])?.intValue, seconds > 0 {
            window["window_minutes"] = (seconds + 59) / 60
        }
        if let resetAt = number(object["reset_at"])?.doubleValue {
            window["resets_at"] = resetAt
        }
        return window
    }

    private static func parseResetCredits(_ value: Any?) -> [String: Any]? {
        guard let object = value as? [String: Any] else { return nil }
        let resetItems = firstArray([object["resets"], object["credits"], object["items"]])
            .compactMap(parseResetCredit)
        let explicitCount = firstNumber([object["available_count"], object["availableCount"], object["count"]])?.intValue
        guard explicitCount != nil || !resetItems.isEmpty else { return nil }
        let availableCount = explicitCount ?? resetItems.count
        guard availableCount >= 0 else { return nil }

        var output: [String: Any] = ["available_count": availableCount]
        if !resetItems.isEmpty {
            output["resets"] = resetItems
        }
        return output
    }

    private static func hasCompleteResetCredits(_ value: Any?) -> Bool {
        guard let object = value as? [String: Any],
              let count = firstNumber([object["available_count"]])?.intValue,
              count >= 0
        else { return false }
        if count == 0 { return true }
        return firstArray([object["resets"]]).compactMap(parseResetCredit).count >= count
    }

    private static func parseResetCredit(_ value: Any) -> [String: Any]? {
        guard let object = value as? [String: Any] else { return nil }
        var output: [String: Any] = [:]
        if let expiresAt = firstDateEpoch([
            object["expires_at"],
            object["expiration_at"],
            object["expiresAt"],
            object["expirationAt"],
            object["valid_until"],
            object["validUntil"]
        ]) {
            output["expires_at"] = expiresAt
        }
        return output.isEmpty ? nil : output
    }

    private func fetchDetailedResetCredits(authInfo: CodexUsageAuthInfo) async -> [String: Any]? {
        var request = URLRequest(url: Self.resetCreditsEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AgentBar", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(authInfo.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(authInfo.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        request.setValue("CODEX", forHTTPHeaderField: "OAI-Product-Sku")

        let response = try? await usageClient(request, timeout)
        guard let response, 200..<300 ~= response.statusCode else { return nil }
        return Self.parseDetailedResetCreditsResponse(data: response.data)
    }

    private static func parseDetailedResetCreditsResponse(data: Data) -> [String: Any]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let credits = firstArray([root["credits"], root["resets"], root["items"]])
            .compactMap(parseDetailedResetCredit)
        let available = credits.filter { ($0["is_available"] as? Bool) ?? true }
        let explicitCount = firstNumber([root["available_count"], root["availableCount"], root["count"]])?.intValue
        let hasCreditList = root["credits"] is [Any] || root["resets"] is [Any] || root["items"] is [Any]
        guard explicitCount != nil || hasCreditList else { return nil }
        let availableCount = explicitCount ?? available.count
        guard availableCount >= 0 else { return nil }
        var output: [String: Any] = ["available_count": availableCount]
        let resets = available.map { credit in
            credit.filter { $0.key != "is_available" }
        }
        if !resets.isEmpty {
            output["resets"] = resets
        }
        return output
    }

    private static func parseDetailedResetCredit(_ value: Any) -> [String: Any]? {
        guard let object = value as? [String: Any] else { return nil }
        let status = firstNonEmptyString([object["status"]])
        var output: [String: Any] = [
            "is_available": status?.localizedCaseInsensitiveCompare("available") == .orderedSame || status == nil
        ]
        if let expiresAt = firstDateEpoch([object["expires_at"], object["expiresAt"], object["expiration_at"], object["expirationAt"]]) {
            output["expires_at"] = expiresAt
        }
        return output
    }

    private static func parseCredits(_ value: Any?) -> [String: Any]? {
        guard let object = value as? [String: Any] else { return nil }
        var credits: [String: Any] = [:]
        credits["has_credits"] = (object["has_credits"] as? Bool) ?? false
        credits["unlimited"] = (object["unlimited"] as? Bool) ?? false
        if let balance = object["balance"] as? String, !balance.isEmpty {
            credits["balance"] = balance
        }
        return credits
    }

    private static func responseErrorCode(from data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        let code = nestedErrorCode(root["error"]) ?? nestedErrorCode(root["detail"])
        guard let code, !code.isEmpty else { return "" }
        return " \(code)"
    }

    private static func nestedErrorCode(_ value: Any?) -> String? {
        (value as? [String: Any])?["code"] as? String
    }

    private static func firstNonEmptyString(_ values: [Any?]) -> String? {
        values.compactMap { value -> String? in
            guard let string = value as? String else { return nil }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }.first
    }

    private static func activeAccountKey(in accounts: [[String: Any]], matching identity: CodexAuthIdentity?) -> String? {
        accounts.first { account($0, matches: identity) }
            .flatMap { firstNonEmptyString([$0["account_key"]]) }
    }

    private static func account(_ account: [String: Any], matches identity: CodexAuthIdentity?) -> Bool {
        identity?.matches(
            accountKey: firstNonEmptyString([account["account_key"]]),
            email: firstNonEmptyString([account["email"]]),
            chatGPTAccountID: firstNonEmptyString([account["chatgpt_account_id"]]),
            workspaceID: firstNonEmptyString([account["workspace_id"]]),
            accountID: firstNonEmptyString([account["account_id"]])
        ) == true
    }

    private static func reconcileCLIProxyAccounts(
        _ currentAccounts: [[String: Any]],
        discovery: CLIProxyCodexDiscovery
    ) -> [[String: Any]] {
        var accounts = currentAccounts
        if discovery.scanCompleted {
            accounts.removeAll {
                ($0[CLIProxyCodexRegistryMetadata.externalOnly] as? Bool) == true
            }
            for index in accounts.indices {
                accounts[index].removeValue(forKey: CLIProxyCodexRegistryMetadata.source)
                accounts[index].removeValue(forKey: CLIProxyCodexRegistryMetadata.accessTokenExpiresAt)
                accounts[index].removeValue(forKey: CLIProxyCodexRegistryMetadata.hasSignInLease)
            }
        }

        for credential in discovery.credentials {
            let index: Int
            if let existingIndex = accounts.firstIndex(where: {
                account($0, matches: credential.identity)
            }) {
                index = existingIndex
            } else {
                var account: [String: Any] = [
                    "account_key": externalAccountKey(for: credential),
                    "chatgpt_account_id": credential.authInfo.accountID,
                    CLIProxyCodexRegistryMetadata.externalOnly: true
                ]
                account["email"] = credential.identity.email
                accounts.append(account)
                index = accounts.index(before: accounts.endIndex)
            }
            accounts[index][CLIProxyCodexRegistryMetadata.source] = credential.sources.sorted().joined(separator: "+")
            accounts[index][CLIProxyCodexRegistryMetadata.accessTokenExpiresAt] =
                credential.accessTokenExpiresAt?.timeIntervalSince1970
            accounts[index][CLIProxyCodexRegistryMetadata.hasSignInLease] = credential.nativeAuthLease != nil
        }
        return accounts
    }

    private static func externalAccountKey(for credential: CLIProxyCodexCredential) -> String {
        let email = credential.identity.email?.lowercased() ?? ""
        let source = credential.sources.contains(CLIProxyCodexRegistryMetadata.sourceValue)
            ? CLIProxyCodexRegistryMetadata.sourceValue
            : CLIProxyCodexRegistryMetadata.openCodexSourceValue
        return "\(source)|\(credential.authInfo.accountID)|\(email)"
    }

    private static func promoteNativeAccounts(
        _ accounts: inout [[String: Any]],
        storage: CodexAccountStorage,
        fileManager: FileManager
    ) {
        for index in accounts.indices {
            guard (accounts[index][CLIProxyCodexRegistryMetadata.externalOnly] as? Bool) == true,
                  let accountKey = firstNonEmptyString([accounts[index]["account_key"]])
            else { continue }
            let authURL = storage.accountAuthURL(for: accountKey)
            guard fileManager.fileExists(atPath: authURL.path),
                  let data = try? Data(contentsOf: authURL),
                  account(accounts[index], matches: CodexAccountStorage.chatGPTAuthIdentity(from: data))
            else { continue }
            accounts[index].removeValue(forKey: CLIProxyCodexRegistryMetadata.externalOnly)
        }
    }

    private static func firstNumber(_ values: [Any?]) -> NSNumber? {
        values.compactMap(number).first
    }

    private static func firstDateEpoch(_ values: [Any?]) -> Double? {
        for value in values {
            if let number = number(value) {
                return number.doubleValue
            }
            if let string = value as? String,
               let date = iso8601Date(from: string) {
                return date.timeIntervalSince1970
            }
        }
        return nil
    }

    private static func firstArray(_ values: [Any?]) -> [Any] {
        values.compactMap { $0 as? [Any] }.first ?? []
    }

    private static func number(_ value: Any?) -> NSNumber? {
        value as? NSNumber
    }

    private static func iso8601Date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func jsonValue(_ lhs: Any?, equals rhs: [String: Any]) -> Bool {
        guard let lhs = lhs else { return false }
        return NSDictionary(dictionary: rhs).isEqual(lhs)
    }
}
