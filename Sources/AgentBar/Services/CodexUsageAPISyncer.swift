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
    typealias UsageClient = @Sendable (URLRequest, TimeInterval) throws -> CodexUsageAPIResponse

    static let usageEndpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    var homeDirectory: URL
    var fileManager: FileManager
    var now: @Sendable () -> Date
    var usageClient: UsageClient
    var timeout: TimeInterval

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init,
        usageClient: @escaping UsageClient = Self.defaultUsageClient,
        timeout: TimeInterval = 5
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.now = now
        self.usageClient = usageClient
        self.timeout = timeout
    }

    func refreshUsage() -> CodexUsageSyncResult {
        let registryURL = homeDirectory.appending(path: ".codex/accounts/registry.json")
        guard let data = try? Data(contentsOf: registryURL),
              var registry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var accounts = registry["accounts"] as? [[String: Any]]
        else {
            return .unavailable("Codex account registry was not found or could not be parsed.")
        }

        let activeAccountKey = registry["active_account_key"] as? String
        var attempted = 0
        var updated = false
        var lastFailure: CodexUsageSyncResult?

        for index in accounts.indices {
            if let authMode = accounts[index]["auth_mode"] as? String,
               authMode.localizedCaseInsensitiveCompare("apikey") == .orderedSame {
                continue
            }
            guard let accountKey = accounts[index]["account_key"] as? String,
                  !accountKey.isEmpty
            else {
                continue
            }
            let accountSnapshotURL = accountAuthURL(for: accountKey)
            let authURL = preferredAuthURL(for: accountKey, activeAccountKey: activeAccountKey, accountSnapshotURL: accountSnapshotURL)
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
                response = try usageClient(request, timeout)
            } catch CodexUsageSyncError.timedOut {
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
            guard let usage = Self.parseUsageResponse(data: response.data) else {
                lastFailure = .failed("Usage response did not contain rate limit windows.")
                continue
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
                try writeRegistry(registry, to: registryURL)
            } catch {
                return .failed(error.localizedDescription)
            }
        }

        return lastFailure ?? .success
    }

    private func accountAuthURL(for accountKey: String) -> URL {
        let fileKey = accountKey.needsCodexAccountFilenameEncoding ? accountKey.codexAccountFileKey : accountKey
        return homeDirectory.appending(path: ".codex/accounts/\(fileKey).auth.json")
    }

    private func preferredAuthURL(for accountKey: String, activeAccountKey: String?, accountSnapshotURL: URL) -> URL {
        guard accountKey == activeAccountKey else { return accountSnapshotURL }
        let activeAuthURL = homeDirectory.appending(path: ".codex/auth.json")
        guard let activeModifiedAt = modificationDate(activeAuthURL) else { return accountSnapshotURL }
        let snapshotModifiedAt = modificationDate(accountSnapshotURL) ?? .distantPast
        return activeModifiedAt > snapshotModifiedAt ? activeAuthURL : accountSnapshotURL
    }

    private func modificationDate(_ url: URL) -> Date? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.modificationDate] as? Date
    }

    private func writeRegistry(_ registry: [String: Any], to registryURL: URL) throws {
        let permissions = try? fileManager.attributesOfItem(atPath: registryURL.path)[.posixPermissions]
        let output = try JSONSerialization.data(withJSONObject: registry, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try output.write(to: registryURL, options: [.atomic])
        if let permissions {
            try? fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: registryURL.path)
        }
    }

    private static func defaultUsageClient(request: URLRequest, timeout: TimeInterval) throws -> CodexUsageAPIResponse {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
        }

        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = CodexUsageAPIResultBox()
        let task = session.dataTask(with: request) { data, response, error in
            let resolved: Result<CodexUsageAPIResponse, Error>
            if let error {
                resolved = .failure(error)
            } else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                resolved = .success(CodexUsageAPIResponse(statusCode: statusCode, data: data ?? Data()))
            }

            resultBox.store(resolved)
            semaphore.signal()
        }
        task.resume()

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            task.cancel()
            throw CodexUsageSyncError.timedOut
        }

        let resolved = resultBox.result
        return try resolved?.get() ?? CodexUsageAPIResponse(statusCode: 0, data: Data())
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
        if let expiresAt = firstNumber([
            object["expires_at"],
            object["expiration_at"],
            object["expiresAt"],
            object["expirationAt"],
            object["valid_until"],
            object["validUntil"]
        ])?.doubleValue {
            output["expires_at"] = expiresAt
        }
        return output.isEmpty ? nil : output
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

    private static func firstArray(_ values: [Any?]) -> [Any] {
        values.compactMap { $0 as? [Any] }.first ?? []
    }

    private static func number(_ value: Any?) -> NSNumber? {
        value as? NSNumber
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

private enum CodexUsageSyncError: Error {
    case timedOut
}

private final class CodexUsageAPIResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: Result<CodexUsageAPIResponse, Error>?

    var result: Result<CodexUsageAPIResponse, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }

    func store(_ result: Result<CodexUsageAPIResponse, Error>) {
        lock.lock()
        storedResult = result
        lock.unlock()
    }
}

private extension String {
    var needsCodexAccountFilenameEncoding: Bool {
        guard !isEmpty, self != ".", self != ".." else { return true }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        return unicodeScalars.contains { !allowed.contains($0) }
    }

    var codexAccountFileKey: String {
        Data(utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
