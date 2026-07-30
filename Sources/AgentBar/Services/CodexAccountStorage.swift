import Foundation

struct CodexAuthIdentity: Equatable {
    var accountID: String?
    var email: String?

    func matches(
        accountKey: String?,
        email registryEmail: String?,
        chatGPTAccountID: String?,
        workspaceID: String?,
        accountID registryAccountID: String? = nil
    ) -> Bool {
        guard let accountID = trimmed(accountID), !accountID.isEmpty else {
            return false
        }
        let accountIDMatches = [
            accountKey,
            chatGPTAccountID,
            workspaceID,
            registryAccountID,
            accountKey.flatMap(Self.codexWorkspaceID)
        ]
        .compactMap { trimmed($0) }
        .contains(accountID)
        guard accountIDMatches else { return false }
        guard let authEmail = trimmed(email)?.lowercased(),
              let registryEmail = trimmed(registryEmail)?.lowercased()
        else {
            return true
        }
        return authEmail == registryEmail
    }

    private func trimmed(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func codexWorkspaceID(from accountKey: String) -> String? {
        guard let delimiter = accountKey.range(of: "::") else { return nil }
        let value = accountKey[delimiter.upperBound...]
        return value.isEmpty ? nil : String(value)
    }
}

struct CodexAccountStorage {
    var homeDirectory: URL
    var fileManager: FileManager = .default

    var accountsDirectory: URL {
        homeDirectory.appending(path: ".codex/accounts", directoryHint: .isDirectory)
    }

    var registryURL: URL {
        accountsDirectory.appending(path: "registry.json")
    }

    var activeAuthURL: URL {
        homeDirectory.appending(path: ".codex/auth.json")
    }

    func readRegistryBootstrappingActiveAccount(now: Date) throws -> Data {
        do {
            return try Data(contentsOf: registryURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            let authData = try Data(contentsOf: activeAuthURL)
            guard let identity = Self.chatGPTAuthIdentity(from: authData),
                  let accountID = identity.accountID
            else { throw error }

            try fileManager.createDirectory(at: accountsDirectory, withIntermediateDirectories: true)
            let snapshotURL = accountAuthURL(for: accountID)
            try authData.write(to: snapshotURL, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: snapshotURL.path)

            var account: [String: Any] = [
                "account_key": accountID,
                "chatgpt_account_id": accountID
            ]
            account["email"] = identity.email
            try writeRegistry([
                "active_account_key": accountID,
                "active_account_activated_at_ms": Int(now.timeIntervalSince1970 * 1_000),
                "accounts": [account]
            ])
            return try Data(contentsOf: registryURL)
        }
    }

    func accountAuthURL(for accountID: String) -> URL {
        accountsDirectory.appending(path: "\(Self.fileKey(for: accountID)).auth.json")
    }

    func recoveryLoginCommand(accountID: String) -> String {
        [
            "codex login",
            "mkdir -p \(Self.shellQuoted(accountsDirectory.path))",
            "cp \(Self.shellQuoted(activeAuthURL.path)) \(Self.shellQuoted(accountAuthURL(for: accountID).path))",
            "/usr/bin/notifyutil -p \(Self.recoveryLoginFinishedNotificationName)"
        ].joined(separator: " && ")
    }

    static func chatGPTAccountID(from authData: Data) -> String? {
        chatGPTAuthIdentity(from: authData)?.accountID
    }

    static func chatGPTAuthIdentity(from authData: Data) -> CodexAuthIdentity? {
        guard let root = try? JSONSerialization.jsonObject(with: authData) as? [String: Any] else {
            return nil
        }
        if firstNonEmptyString([root["OPENAI_API_KEY"]]) != nil {
            return nil
        }
        if let authMode = firstNonEmptyString([root["auth_mode"]]),
           authMode.localizedCaseInsensitiveCompare("apikey") == .orderedSame {
            return nil
        }
        let tokens = root["tokens"] as? [String: Any]
        let accountID = firstNonEmptyString([
            tokens?["account_id"],
            root["account_id"]
        ])
        let jwt = jwtPayload(firstNonEmptyString([tokens?["id_token"], root["id_token"]]))
        let email = firstNonEmptyString([
            root["email"],
            tokens?["email"],
            jwt?["email"]
        ])
        guard accountID != nil || email != nil else { return nil }
        return CodexAuthIdentity(accountID: accountID, email: email)
    }

    static func accessTokenExpiration(from authData: Data) -> Date? {
        guard let root = try? JSONSerialization.jsonObject(with: authData) as? [String: Any] else {
            return nil
        }
        if firstNonEmptyString([root["OPENAI_API_KEY"]]) != nil {
            return nil
        }
        if let authMode = firstNonEmptyString([root["auth_mode"]]),
           authMode.localizedCaseInsensitiveCompare("apikey") == .orderedSame {
            return nil
        }
        let tokens = root["tokens"] as? [String: Any]
        guard let payload = jwtPayload(firstNonEmptyString([
            tokens?["access_token"],
            root["access_token"]
        ])),
              let seconds = (payload["exp"] as? NSNumber)?.doubleValue,
              seconds.isFinite,
              seconds > 0
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    func writeRegistry(_ registry: [String: Any]) throws {
        let permissions = try? fileManager.attributesOfItem(atPath: registryURL.path)[.posixPermissions]
        let output = try JSONSerialization.data(withJSONObject: registry, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try output.write(to: registryURL, options: [.atomic])
        if let permissions {
            try? fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: registryURL.path)
        }
    }

    static func fileKey(for accountID: String) -> String {
        guard !accountID.isEmpty, accountID != ".", accountID != ".." else {
            return encodedFileKey(for: accountID)
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        if accountID.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            return accountID
        }
        return encodedFileKey(for: accountID)
    }

    private static func encodedFileKey(for accountID: String) -> String {
        Data(accountID.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static let recoveryLoginFinishedNotificationName = "com.agentbar.codexRecoveryLoginFinished"

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func firstNonEmptyString(_ values: [Any?]) -> String? {
        values.compactMap { value -> String? in
            guard let string = value as? String else { return nil }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }.first
    }

    private static func jwtPayload(_ token: String?) -> [String: Any]? {
        guard let payload = token?.split(separator: ".").dropFirst().first else { return nil }
        var value = String(payload)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: value) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
