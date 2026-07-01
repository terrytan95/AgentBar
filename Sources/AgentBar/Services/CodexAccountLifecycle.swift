import Foundation

@MainActor
final class CodexAccountLifecycle {
    enum RestartMode: Sendable {
        case manualForceCodexAppRestart
        case safeForceCodexAppRestart
    }

    private var manualCodexRotationOverrideAccountID: String?
    private var pendingCodexSwitchRecovery: PendingSwitchRecovery?

    func beginSwitch(
        account: UsageAccount,
        restartMode: RestartMode,
        switchingAccountID: String?
    ) throws -> String? {
        guard switchingAccountID == nil else { return nil }
        guard account.service == .codex else {
            throw AccountActionError.unsupportedService
        }
        if restartMode == .manualForceCodexAppRestart {
            manualCodexRotationOverrideAccountID = account.id
        }
        return account.id
    }

    func automaticRotationAccount(
        accounts: [UsageAccount],
        autoRotationEnabled: Bool,
        thresholdRemainingPercent: Double,
        switchingAccountID: String?,
        now: Date = Date()
    ) -> UsageAccount? {
        guard autoRotationEnabled, switchingAccountID == nil else { return nil }
        if shouldHonorManualCodexSelection(accounts: accounts, thresholdRemainingPercent: thresholdRemainingPercent) {
            return nil
        }
        let policy = CodexAccountRotationPolicy(thresholdRemainingPercent: thresholdRemainingPercent)
        return policy.selectedAccount(from: accounts, now: now)
    }

    func finishSwitch(
        account: UsageAccount,
        restartMode: RestartMode,
        result: Result<Void, Error>,
        loginLauncher: @escaping @MainActor @Sendable (String, String) -> Void
    ) -> CodexAccountSwitchCompletion {
        switch result {
        case .success:
            if pendingCodexSwitchRecovery?.accountID == account.id {
                pendingCodexSwitchRecovery = nil
            }
            return .success
        case .failure(let error):
            if manualCodexRotationOverrideAccountID == account.id {
                manualCodexRotationOverrideAccountID = nil
            }
            let message = Self.switchFailureMessage(for: error)
            return .failure(
                message: message,
                recovery: recovery(for: account, restartMode: restartMode, message: message, loginLauncher: loginLauncher)
            )
        }
    }

    func pendingRecoverySwitch(accounts: [UsageAccount]) -> (account: UsageAccount, restartMode: RestartMode)? {
        guard let pending = pendingCodexSwitchRecovery,
              let account = accounts.first(where: { $0.id == pending.accountID && $0.service == .codex })
        else {
            return nil
        }
        pendingCodexSwitchRecovery = nil
        return (account, pending.restartMode)
    }

    func removeAccount(_ accountID: String) {
        if manualCodexRotationOverrideAccountID == accountID {
            manualCodexRotationOverrideAccountID = nil
        }
        if pendingCodexSwitchRecovery?.accountID == accountID {
            pendingCodexSwitchRecovery = nil
        }
    }

    private func shouldHonorManualCodexSelection(accounts: [UsageAccount], thresholdRemainingPercent: Double) -> Bool {
        guard let overrideAccountID = manualCodexRotationOverrideAccountID else { return false }
        guard let activeCodexAccount = accounts.first(where: { $0.service == .codex && $0.isActive }) else {
            manualCodexRotationOverrideAccountID = nil
            return false
        }
        guard activeCodexAccount.id == overrideAccountID else {
            manualCodexRotationOverrideAccountID = nil
            return false
        }
        if let remaining = activeCodexAccount.fiveHourWindow?.remainingPercent,
           remaining > thresholdRemainingPercent {
            manualCodexRotationOverrideAccountID = nil
            return false
        }
        return true
    }

    private func recovery(
        for account: UsageAccount,
        restartMode: RestartMode,
        message: String,
        loginLauncher: @escaping @MainActor @Sendable (String, String) -> Void
    ) -> CodexAccountSwitchRecovery {
        CodexAccountSwitchRecovery(
            accountID: account.id,
            accountLabel: account.displayName,
            message: message,
            startLogin: { [weak self] in
                self?.pendingCodexSwitchRecovery = PendingSwitchRecovery(
                    accountID: account.id,
                    restartMode: restartMode
                )
                loginLauncher(account.id, account.displayName)
            }
        )
    }

    private static func switchFailureMessage(for error: Error) -> String {
        let reason = error.localizedDescription.redactedForCredentialWords
        return "The Codex account switch failed. Please login to this Codex account again. Additional phone number authentication might be needed. \(reason)"
    }

    private struct PendingSwitchRecovery {
        var accountID: String
        var restartMode: RestartMode
    }
}

enum CodexAccountSwitchCompletion {
    case success
    case failure(message: String, recovery: CodexAccountSwitchRecovery)
}
