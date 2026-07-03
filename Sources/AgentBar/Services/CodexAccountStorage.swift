import Foundation

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

    func accountAuthURL(for accountID: String) -> URL {
        accountsDirectory.appending(path: "\(Self.fileKey(for: accountID)).auth.json")
    }

    func recoveryLoginCommand(accountID: String) -> String {
        let fileKey = Self.fileKey(for: accountID)
        return #"codex login && mkdir -p "$HOME/.codex/accounts" && cp "$HOME/.codex/auth.json" "$HOME/.codex/accounts/\#(fileKey).auth.json""#
    }

    static func chatGPTAccountID(from authData: Data) -> String? {
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
        return firstNonEmptyString([
            tokens?["account_id"],
            root["account_id"]
        ])
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

    private static func firstNonEmptyString(_ values: [Any?]) -> String? {
        values.compactMap { value -> String? in
            guard let string = value as? String else { return nil }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }.first
    }
}
