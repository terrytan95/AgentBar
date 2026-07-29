import AppKit
import Foundation
@preconcurrency import UserNotifications

enum AccountActionError: LocalizedError, Equatable {
    case unsupportedService
    case missingRegistry
    case invalidRegistry
    case missingAccount
    case missingAccountSnapshot
    case mismatchedAccountSnapshot
    case emptyAccessToken
    case codexExecutableNotFound
    case accessTokenLoginTimedOut
    case accessTokenLoginCancelled
    case accessTokenLoginFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .unsupportedService: "This service does not expose a safe local account switch action yet."
        case .missingRegistry: "Codex account registry was not found."
        case .invalidRegistry: "Codex account registry could not be parsed."
        case .missingAccount: "The selected account was not found in the Codex registry."
        case .missingAccountSnapshot: "The selected Codex account auth snapshot was not found."
        case .mismatchedAccountSnapshot: "The selected Codex account auth snapshot belongs to a different login."
        case .emptyAccessToken: "No Codex access token was entered."
        case .codexExecutableNotFound: "The Codex executable could not be found in a trusted install location."
        case .accessTokenLoginTimedOut: "Codex did not finish applying the access token before the timeout."
        case .accessTokenLoginCancelled: "The Codex access token update was cancelled."
        case .accessTokenLoginFailed(let status) where status == 503:
            "Codex returned 503 while applying the access token. Log in to one Codex account locally, then try again."
        case .accessTokenLoginFailed(let status):
            "Codex could not apply the access token. codex login exited with status \(status)."
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
        let storage = CodexAccountStorage(homeDirectory: homeDirectory, fileManager: fileManager)
        let registryURL = storage.registryURL
        let accountSnapshotURL = storage.accountAuthURL(for: accountID)
        let activeAuthURL = storage.activeAuthURL
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
        guard let selectedAccount = accounts.first(where: { $0["account_key"] as? String == accountID }) else {
            throw AccountActionError.missingAccount
        }
        let selectedAuth = try Data(contentsOf: accountSnapshotURL)
        if let identity = CodexAccountStorage.chatGPTAuthIdentity(from: selectedAuth),
           !identity.matches(
            accountKey: selectedAccount["account_key"] as? String,
            email: selectedAccount["email"] as? String,
            chatGPTAccountID: selectedAccount["chatgpt_account_id"] as? String,
            workspaceID: selectedAccount["workspace_id"] as? String,
            accountID: selectedAccount["account_id"] as? String
           ) {
            throw AccountActionError.mismatchedAccountSnapshot
        }

        let previous = json["active_account_key"] as? String
        if previous != accountID {
            json["previous_active_account_key"] = previous
        }
        json["active_account_key"] = accountID
        json["active_account_activated_at_ms"] = Int(Date().timeIntervalSince1970 * 1000)

        let previousAuth = try? Data(contentsOf: activeAuthURL)
        let activeAuthPermissions = try? fileManager.attributesOfItem(atPath: activeAuthURL.path)[.posixPermissions]
        try selectedAuth.write(to: activeAuthURL, options: [.atomic])
        if let activeAuthPermissions {
            try? fileManager.setAttributes([.posixPermissions: activeAuthPermissions], ofItemAtPath: activeAuthURL.path)
        }

        do {
            try storage.writeRegistry(json)
        } catch {
            restoreAuth(previousAuth, to: activeAuthURL, permissions: activeAuthPermissions)
            throw error
        }
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

struct CodexAccountAccessTokenUpdater {
    var homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    var fileManager: FileManager = .default
    var codexExecutableURL: URL? = CodexExecutableLocator.find()

    func updateAccount(accountID: String, accessToken rawAccessToken: String) async throws {
        let accessToken = rawAccessToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^Bearer\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty else { throw AccountActionError.emptyAccessToken }

        let tempHome = fileManager.temporaryDirectory.appending(path: "agentbar-codex-token-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: tempHome) }
        try fileManager.createDirectory(at: tempHome, withIntermediateDirectories: true)

        guard let codexExecutableURL else { throw AccountActionError.codexExecutableNotFound }
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = tempHome.path
        environment["CODEX_HOME"] = nil

        let result = try await AsyncProcessRunner.run(
            executableURL: codexExecutableURL,
            arguments: ["login", "--with-access-token"],
            environment: environment,
            standardInput: Data((accessToken + "\n").utf8),
            maximumOutputBytes: 1_048_576,
            timeout: 30
        )
        if result.timedOut { throw AccountActionError.accessTokenLoginTimedOut }
        if result.wasCancelled { throw AccountActionError.accessTokenLoginCancelled }
        guard result.exitStatus == 0 else {
            let message = String(decoding: result.stdout + result.stderr, as: UTF8.self)
            throw AccountActionError.accessTokenLoginFailed(message.contains("503") ? 503 : result.exitStatus)
        }

        let authData = try Data(contentsOf: tempHome.appending(path: ".codex/auth.json"))
        try writeTokenBackedSnapshot(authData, accountID: accountID)
    }

    func writeTokenBackedSnapshot(_ authData: Data, accountID: String) throws {
        let storage = CodexAccountStorage(homeDirectory: homeDirectory, fileManager: fileManager)
        let data = try Data(contentsOf: storage.registryURL)
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var accounts = json["accounts"] as? [[String: Any]]
        else {
            throw AccountActionError.invalidRegistry
        }
        guard let index = accounts.firstIndex(where: { $0["account_key"] as? String == accountID }) else {
            throw AccountActionError.missingAccount
        }

        try fileManager.createDirectory(at: storage.accountsDirectory, withIntermediateDirectories: true)
        try authData.write(to: storage.accountAuthURL(for: accountID), options: [.atomic])
        if json["active_account_key"] as? String == accountID {
            try authData.write(to: storage.activeAuthURL, options: [.atomic])
        }
        accounts[index]["agentbar_token_backed"] = true
        accounts[index].removeValue(forKey: "agentbar_auth_error")
        json["accounts"] = accounts
        try storage.writeRegistry(json)
    }
}

private enum CodexExecutableLocator {
    static func find(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> URL? {
        [
            homeDirectory.appending(path: ".local/bin/codex"),
            homeDirectory.appending(path: ".codex/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex")
        ].first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}

struct CodexAccountRemover {
    var homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    var fileManager: FileManager = .default

    func removeAccount(accountID: String) throws {
        let storage = CodexAccountStorage(homeDirectory: homeDirectory, fileManager: fileManager)
        let registryURL = storage.registryURL
        let accountSnapshotURL = storage.accountAuthURL(for: accountID)
        let activeAuthURL = storage.activeAuthURL
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

        try storage.writeRegistry(json)
        if fileManager.fileExists(atPath: accountSnapshotURL.path) {
            try fileManager.removeItem(at: accountSnapshotURL)
        }
        if wasActive, fileManager.fileExists(atPath: activeAuthURL.path) {
            try fileManager.removeItem(at: activeAuthURL)
        }
    }
}

enum AccountLoginLauncher {
    static let codexAppBundleIdentifier = "com.openai.codex"

    static func promptCodexLoginAgain(recovery: CodexAccountSwitchRecovery) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Codex account switch failed"
            alert.informativeText = "\(recovery.message)\n\nAccount: \(recovery.accountLabel)\n\nAfter login, AgentBar will refresh and retry this account automatically."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Login & Retry")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                recovery.startLogin()
            }
        }
    }

    static func openLogin(for service: UsageService) {
        switch service {
        case .codex:
            openTerminal(command: "codex login")
        case .claudeCode:
            openTerminal(command: "claude auth login")
        case .xaiAPI:
            guard let url = URL(string: "https://console.x.ai/team/default/settings/management-keys") else { return }
            NSWorkspace.shared.open(url)
        }
    }

    static func openCodexRecoveryLogin(accountID: String, accountLabel: String) {
        let command = codexRecoveryLoginCommand(accountID: accountID)
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "AgentBar Codex account recovery"
            alert.informativeText = """
            Account: \(accountLabel)

            Finish the Codex login. AgentBar will refresh this account automatically.

            Terminal will run: codex login and update AgentBar's account snapshot.

            If your browser does not open, use the authentication URL printed in Terminal.
            On a remote or headless machine, run codex login --device-auth instead.
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open Login")
            alert.addButton(withTitle: "Use Access Token")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                openTerminal(command: command)
            case .alertSecondButtonReturn:
                Task { @MainActor in
                    promptCodexAccessToken(accountID: accountID, accountLabel: accountLabel)
                }
            default:
                break
            }
        }
    }

    static func codexRecoveryLoginCommand(accountID: String) -> String {
        CodexAccountStorage(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
            .recoveryLoginCommand(accountID: accountID)
    }

    private static func openTerminal(command: String) {
        let script = """
        tell application "Terminal"
          activate
          do script \(appleScriptString(command))
        end tell
        """
        DispatchQueue.global(qos: .utility).async {
            if !runAppleScript(script, timeout: 10) {
                NSLog("AgentBar could not open the login command in Terminal")
            }
        }
    }

    @discardableResult
    static func forceRestartCodexApp() -> Bool {
        let restarted = runAppleScript(codexAppRestartScript(), timeout: 15)
        if !restarted {
            NSLog("AgentBar could not restart Codex")
        }
        return restarted
    }

    static func codexAppRestartScript() -> String {
        """
        try
          tell application id "\(codexAppBundleIdentifier)" to quit
        end try
        delay 1
        do shell script "/usr/bin/pkill -x ChatGPT; /usr/bin/pkill -x Codex; true"
        delay 1
        tell application id "\(codexAppBundleIdentifier)" to activate
        """
    }

    private static func runAppleScript(_ script: String, timeout: TimeInterval) -> Bool {
        guard let result = try? AsyncProcessRunner.runBlocking(
            executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", script],
            maximumOutputBytes: 64 * 1024,
            timeout: timeout
        ) else { return false }
        return result.exitStatus == 0 && !result.timedOut && !result.wasCancelled
    }

    @MainActor
    private static func promptCodexAccessToken(accountID: String, accountLabel: String) {
        let alert = NSAlert()
        alert.messageText = "Update Codex access token"
        alert.informativeText = "Account: \(accountLabel)\n\nPaste a Codex access token. AgentBar will update this account snapshot without storing the token in shell history."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Update Token")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        input.placeholderString = "Bearer ..."
        alert.accessoryView = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let token = input.stringValue
        Task.detached(priority: .utility) {
            let result: Result<Void, Error>
            do {
                try await CodexAccountAccessTokenUpdater().updateAccount(accountID: accountID, accessToken: token)
                result = .success(())
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                switch result {
                case .success:
                    postCodexRecoveryNotification()
                    showCodexLoginSuccess(accountLabel: accountLabel)
                case .failure(let error):
                    showError("Codex access token update failed", message: error.localizedDescription.redactedForCredentialWords)
                }
            }
        }
    }

    @MainActor
    private static func showError(_ title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    static func showCodexLoginSuccess(accountLabel: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Codex login successful"
            content.body = "Account: \(accountLabel)"
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "codex-login-success-\(UUID().uuidString)", content: content, trigger: nil))
        }
    }

    private static func postCodexRecoveryNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(CodexAccountStorage.recoveryLoginFinishedNotificationName as CFString),
            nil,
            nil,
            true
        )
    }

    private static func appleScriptString(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

}
