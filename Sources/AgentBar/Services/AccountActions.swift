import AppKit
import Foundation

enum AccountActionError: LocalizedError {
    case unsupportedService
    case missingRegistry
    case invalidRegistry
    case missingAccount
    case missingAccountSnapshot

    var errorDescription: String? {
        switch self {
        case .unsupportedService: "This service does not expose a safe local account switch action yet."
        case .missingRegistry: "Codex account registry was not found."
        case .invalidRegistry: "Codex account registry could not be parsed."
        case .missingAccount: "The selected account was not found in the Codex registry."
        case .missingAccountSnapshot: "The selected Codex account auth snapshot was not found."
        }
    }
}

struct CodexAccountSwitchRecovery: @unchecked Sendable {
    var accountID: String
    var accountLabel: String
    var message: String
    var startLogin: @MainActor @Sendable () -> Void
}

struct CodexAccountSwitcher {
    var homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    var fileManager: FileManager = .default

    func switchActiveAccount(accountID: String) throws {
        let registryURL = homeDirectory.appending(path: ".codex/accounts/registry.json")
        let accountSnapshotURL = accountSnapshotURL(for: accountID)
        let activeAuthURL = homeDirectory.appending(path: ".codex/auth.json")
        guard fileManager.fileExists(atPath: registryURL.path) else {
            throw AccountActionError.missingRegistry
        }
        guard fileManager.fileExists(atPath: accountSnapshotURL.path) else {
            throw AccountActionError.missingAccountSnapshot
        }
        let data = try Data(contentsOf: registryURL)
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accounts = json["accounts"] as? [[String: Any]]
        else {
            throw AccountActionError.invalidRegistry
        }
        guard accounts.contains(where: { $0["account_key"] as? String == accountID }) else {
            throw AccountActionError.missingAccount
        }

        let previous = json["active_account_key"] as? String
        if previous != accountID {
            json["previous_active_account_key"] = previous
        }
        json["active_account_key"] = accountID
        json["active_account_activated_at_ms"] = Int(Date().timeIntervalSince1970 * 1000)

        let selectedAuth = try Data(contentsOf: accountSnapshotURL)
        let previousAuth = try? Data(contentsOf: activeAuthURL)
        let activeAuthPermissions = try? fileManager.attributesOfItem(atPath: activeAuthURL.path)[.posixPermissions]
        try selectedAuth.write(to: activeAuthURL, options: [.atomic])
        if let activeAuthPermissions {
            try? fileManager.setAttributes([.posixPermissions: activeAuthPermissions], ofItemAtPath: activeAuthURL.path)
        }

        let output = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        do {
            try output.write(to: registryURL, options: [.atomic])
        } catch {
            restoreAuth(previousAuth, to: activeAuthURL, permissions: activeAuthPermissions)
            throw error
        }
    }

    private func accountSnapshotURL(for accountID: String) -> URL {
        let fileKey = accountID.needsCodexAccountFilenameEncoding ? accountID.codexAccountFileKey : accountID
        return homeDirectory.appending(path: ".codex/accounts/\(fileKey).auth.json")
    }

    private func restoreAuth(_ previousAuth: Data?, to activeAuthURL: URL, permissions: Any?) {
        if let previousAuth {
            try? previousAuth.write(to: activeAuthURL, options: [.atomic])
            if let permissions {
                try? fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: activeAuthURL.path)
            }
        } else if fileManager.fileExists(atPath: activeAuthURL.path) {
            try? fileManager.removeItem(at: activeAuthURL)
        }
    }
}

struct CodexAccountRemover {
    var homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    var fileManager: FileManager = .default

    func removeAccount(accountID: String) throws {
        let registryURL = homeDirectory.appending(path: ".codex/accounts/registry.json")
        let accountSnapshotURL = accountSnapshotURL(for: accountID)
        let activeAuthURL = homeDirectory.appending(path: ".codex/auth.json")
        guard fileManager.fileExists(atPath: registryURL.path) else {
            throw AccountActionError.missingRegistry
        }

        let data = try Data(contentsOf: registryURL)
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accounts = json["accounts"] as? [[String: Any]]
        else {
            throw AccountActionError.invalidRegistry
        }
        let filteredAccounts = accounts.filter { $0["account_key"] as? String != accountID }
        guard filteredAccounts.count != accounts.count else {
            throw AccountActionError.missingAccount
        }

        let wasActive = json["active_account_key"] as? String == accountID
        json["accounts"] = filteredAccounts
        if wasActive {
            json.removeValue(forKey: "active_account_key")
            json.removeValue(forKey: "active_account_activated_at_ms")
        }
        if json["previous_active_account_key"] as? String == accountID {
            json.removeValue(forKey: "previous_active_account_key")
        }

        let output = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try output.write(to: registryURL, options: [.atomic])
        if fileManager.fileExists(atPath: accountSnapshotURL.path) {
            try fileManager.removeItem(at: accountSnapshotURL)
        }
        if wasActive, fileManager.fileExists(atPath: activeAuthURL.path) {
            try fileManager.removeItem(at: activeAuthURL)
        }
    }

    private func accountSnapshotURL(for accountID: String) -> URL {
        let fileKey = accountID.needsCodexAccountFilenameEncoding ? accountID.codexAccountFileKey : accountID
        return homeDirectory.appending(path: ".codex/accounts/\(fileKey).auth.json")
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

enum AccountLoginLauncher {
    static func promptCodexLoginAgain(recovery: CodexAccountSwitchRecovery) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Codex account switch failed"
            alert.informativeText = "\(recovery.message)\n\nAccount: \(recovery.accountLabel)\n\nAfter login, AgentBar will retry this account on the next refresh."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Login & Retry")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                recovery.startLogin()
            }
        }
    }

    static func openLogin(for service: UsageService) {
        let command = service == .codex ? "codex login" : "claude login"
        openTerminal(command: command)
    }

    static func openCodexRecoveryLogin(accountID: String, accountLabel: String) {
        let command = codexRecoveryLoginCommand(accountID: accountID)
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "AgentBar Codex account recovery"
            alert.informativeText = """
            Account: \(accountLabel)

            Finish the Codex login. AgentBar will save it for this account and retry on the next refresh.

            Terminal will run: codex login

            If your browser does not open, use the authentication URL printed in Terminal.
            On a remote or headless machine, run codex login --device-auth instead.
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open Login")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                openTerminal(command: command)
            }
        }
    }

    static func codexRecoveryLoginCommand(accountID: String) -> String {
        let fileKey = accountID.needsCodexAccountFilenameEncoding ? accountID.codexAccountFileKey : accountID
        return #"codex login && mkdir -p "$HOME/.codex/accounts" && cp "$HOME/.codex/auth.json" "$HOME/.codex/accounts/\#(fileKey).auth.json""#
    }

    private static func openTerminal(command: String) {
        let script = """
        tell application "Terminal"
          activate
          do script \(appleScriptString(command))
        end tell
        """
        runAppleScript(script)
    }

    static func restartIntegration(for service: UsageService) {
        let appName = service == .codex ? "Codex" : "Claude"
        let script = """
        tell application "\(appName)" to quit
        delay 1
        tell application "\(appName)" to activate
        """
        runAppleScript(script)
    }

    static func forceRestartCodexApp() {
        let script = """
        tell application "Codex" to quit
        delay 1
        do shell script "/usr/bin/pkill -x Codex || true"
        delay 1
        tell application "Codex" to activate
        """
        runAppleScript(script)
    }

    private static func runAppleScript(_ script: String) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            try? process.run()
            process.waitUntilExit()
        }
    }

    private static func appleScriptString(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

}
