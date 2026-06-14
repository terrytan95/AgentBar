import AppKit
import Foundation

enum AccountActionError: LocalizedError {
    case unsupportedService
    case missingRegistry
    case invalidRegistry
    case missingAccount

    var errorDescription: String? {
        switch self {
        case .unsupportedService: "This service does not expose a safe local account switch action yet."
        case .missingRegistry: "Codex account registry was not found."
        case .invalidRegistry: "Codex account registry could not be parsed."
        case .missingAccount: "The selected account was not found in the Codex registry."
        }
    }
}

struct CodexAccountSwitcher {
    var homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    var fileManager: FileManager = .default

    func switchActiveAccount(accountID: String) throws {
        let registryURL = homeDirectory.appending(path: ".codex/accounts/registry.json")
        guard fileManager.fileExists(atPath: registryURL.path) else {
            throw AccountActionError.missingRegistry
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

        json["active_account_key"] = accountID
        let output = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try output.write(to: registryURL, options: [.atomic])
    }
}

enum AccountLoginLauncher {
    static func openLogin(for service: UsageService) {
        let command = service == .codex ? "codex login" : "claude login"
        let script = """
        tell application "Terminal"
          activate
          do script "\(command)"
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

    private static func runAppleScript(_ script: String) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            try? process.run()
            process.waitUntilExit()
        }
    }
}
