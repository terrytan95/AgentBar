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
    var detailedResetCreditsEnabled: Bool

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init,
        usageClient: @escaping UsageClient = Self.defaultUsageClient,
        timeout: TimeInterval = 5,
        detailedResetCreditsEnabled: Bool = false
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.now = now
        self.usageClient = usageClient
        self.timeout = timeout
        self.detailedResetCreditsEnabled = detailedResetCreditsEnabled
    }

    func refreshUsage() async -> CodexUsageSyncResult {
        let storage = CodexAccountStorage(homeDirectory: homeDirectory, fileManager: fileManager)
        let registryURL = storage.registryURL
        guard let data = try? Data(contentsOf: registryURL),
              var registry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var accounts = registry["accounts"] as? [[String: Any]]
        else {
            return .unavailable("Codex account registry was not found or could not be parsed.")
        }

        let activeAccountKey = registry["active_account_key"] as? String
        guard let activeAccountIndex = accounts.firstIndex(where: { account in
            (account["account_key"] as? String) == activeAccountKey
        }) else {
            return .unavailable("No active ChatGPT account was available for usage refresh.")
        }

        var attempted = 0
        var updated = false
        var lastFailure: CodexUsageSyncResult?

        for index in [activeAccountIndex] {
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
            let authURL = preferredAuthURL(for: accountKey, activeAccountKey: activeAccountKey, accountSnapshotURL: accountSnapshotURL, storage: storage)
            guard let authData = try? Data(contentsOf: authURL),
                  let authInfo = Self.parseAuthInfo(data: authData)
            else {
                continue
            }

            attempted += 1
            var request = URLRequest(url: Self.usageEndpoint)
            request.httpMethod = "GET"
            request.timeoutInterval = timeout
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("AgentBar", forHTTPHeaderField: "User-Agent")
            request.setValue("Bearer \(authInfo.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(authInfo.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")

            let response: CodexUsageAPIResponse
            do {
                response = try await usageClient(request, timeout)
            } catch let error as URLError where error.code == .timedOut {
                lastFailure = .timedOut
                continue
            } catch {
                lastFailure = .failed(error.localizedDescription)
                continue
            }

            guard 200..<300 ~= response.statusCode else {
                if response.statusCode == 401 {
                    accounts[index]["agentbar_auth_error"] = [
                        "status_code": 401,
                        "detected_at": now().timeIntervalSince1970
                    ]
                    updated = true
                }
                lastFailure = .failed("HTTP \(response.statusCode)\(Self.responseErrorCode(from: response.data))")
                continue
            }
            guard var usage = Self.parseUsageResponse(data: response.data) else {
                lastFailure = .failed("Usage response did not contain rate limit windows.")
                continue
            }
            if detailedResetCreditsEnabled,
               let detailedResetCredits = await fetchDetailedResetCredits(authInfo: authInfo) {
                usage["reset_credits"] = detailedResetCredits
            }

            if authURL != accountSnapshotURL {
                do {
                    try authData.write(to: accountSnapshotURL, options: [.atomic])
                } catch {
                    lastFailure = .failed(error.localizedDescription)
                    continue
                }
            }
            if accounts[index]["agentbar_auth_error"] != nil {
                accounts[index].removeValue(forKey: "agentbar_auth_error")
                updated = true
            }
            if !Self.jsonValue(accounts[index]["last_usage"], equals: usage) {
                accounts[index]["last_usage"] = usage
                accounts[index]["last_usage_at"] = now().timeIntervalSince1970
                updated = true
            }
        }

        guard attempted > 0 else {
            return .unavailable("No ChatGPT account auth snapshots were available for usage refresh.")
        }

        if updated {
            registry["accounts"] = accounts
            do {
                try storage.writeRegistry(registry)
            } catch {
                return .failed(error.localizedDescription)
            }
        }

        return lastFailure ?? .success
    }

    private func preferredAuthURL(for accountKey: String, activeAccountKey: String?, accountSnapshotURL: URL, storage: CodexAccountStorage) -> URL {
        guard accountKey == activeAccountKey else { return accountSnapshotURL }
        let activeAuthURL = storage.activeAuthURL
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

    private static func parseAuthInfo(data: Data) -> CodexUsageAuthInfo? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let apiKey = root["OPENAI_API_KEY"] as? String,
           !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        if let authMode = root["auth_mode"] as? String,
           authMode.localizedCaseInsensitiveCompare("apikey") == .orderedSame {
            return nil
        }

        let tokens = root["tokens"] as? [String: Any]
        let accessToken = firstNonEmptyString([
            tokens?["access_token"],
            root["access_token"]
        ])
        let accountID = firstNonEmptyString([
            tokens?["account_id"],
            root["account_id"]
        ])
        guard let accessToken, let accountID else { return nil }
        return CodexUsageAuthInfo(accessToken: accessToken, accountID: accountID)
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
        let availableCount = firstNumber([object["available_count"], object["availableCount"], object["count"]])?.intValue ?? resetItems.count
        guard availableCount > 0 || !resetItems.isEmpty else { return nil }

        var output: [String: Any] = ["available_count": availableCount]
        if !resetItems.isEmpty {
            output["resets"] = resetItems
        }
        return output
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

        guard let response = try? await usageClient(request, timeout),
              200..<300 ~= response.statusCode
        else { return nil }
        return Self.parseDetailedResetCreditsResponse(data: response.data)
    }

    private static func parseDetailedResetCreditsResponse(data: Data) -> [String: Any]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let credits = firstArray([root["credits"], root["resets"], root["items"]])
            .compactMap(parseDetailedResetCredit)
        let available = credits.filter { ($0["is_available"] as? Bool) ?? true }
        let availableCount = firstNumber([root["available_count"], root["availableCount"], root["count"]])?.intValue ?? available.count
        guard availableCount > 0 || !available.isEmpty else { return nil }
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

private struct CodexUsageAuthInfo {
    var accessToken: String
    var accountID: String
}
