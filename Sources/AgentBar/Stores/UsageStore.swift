import Foundation

@MainActor
final class UsageStore: ObservableObject {
    static let accountRemovalNotification = Notification.Name("AgentBarUsageStoreAccountRemoval")

    @Published private(set) var snapshots: [UsageService: UsageSnapshot] = [:]
    @Published private(set) var accounts: [UsageAccount] = []
    @Published private(set) var points: [UsagePoint] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isManualRefreshFeedbackVisible = false
    @Published private(set) var hasLoadedAccountInformation = false
    @Published private(set) var lastError: String?
    @Published private(set) var switchingAccountID: String?
    @Published var selectedRange: UsageRange = .today
    @Published var customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @Published var customEnd = Date()

    let settings: SettingsStore
    private let usageRefreshOrchestrator: UsageRefreshOrchestrator
    private let codexAccountSwitcher: @Sendable (String) throws -> Void
    private let codexAccountRemover: @Sendable (String) throws -> Void
    private let automaticCodexRestarter: @Sendable () -> CodexAppRestartResult
    private let manualCodexAppRestarter: @Sendable () -> Void
    private let codexAccountSwitchFailurePrompter: @Sendable (CodexAccountSwitchRecovery) -> Void
    private let codexAccountRecoveryLoginLauncher: @Sendable (String, String) -> Void
    private var timer: Timer?
    private var accountRemovalObserver: NSObjectProtocol?
    private var refreshInFlight = false
    private var refreshQueued = false
    private var manualRefreshQueued = false
    private var manualCodexRotationOverrideAccountID: String?
    private var pendingCodexSwitchRecovery: PendingCodexSwitchRecovery?

    init(
        settings: SettingsStore = SettingsStore(),
        codexUsageSynchronizer: @escaping @Sendable () -> CodexUsageSyncResult = {
            CodexUsageAPISyncer().refreshUsage()
        },
        codexDetailedResetCreditsSynchronizer: @escaping @Sendable () -> CodexUsageSyncResult = {
            CodexUsageAPISyncer(detailedResetCreditsEnabled: true).refreshUsage()
        },
        codexUsageReader: @escaping @Sendable () -> UsageSnapshot = {
            CodexUsageReader().read()
        },
        claudeUsageReader: @escaping @Sendable () -> UsageSnapshot = {
            ClaudeUsageReader().read()
        },
        codexAccountSwitcher: @escaping @Sendable (String) throws -> Void = { accountID in
            try CodexAccountSwitcher().switchActiveAccount(accountID: accountID)
        },
        codexAccountRemover: @escaping @Sendable (String) throws -> Void = { accountID in
            try CodexAccountRemover().removeAccount(accountID: accountID)
        },
        automaticCodexRestarter: @escaping @Sendable () -> CodexAppRestartResult = {
            CodexAppRestarter().restartIfNoWorkIsRunning()
        },
        manualCodexAppRestarter: @escaping @Sendable () -> Void = {
            AccountLoginLauncher.forceRestartCodexApp()
        },
        codexAccountSwitchFailurePrompter: @escaping @Sendable (CodexAccountSwitchRecovery) -> Void = { recovery in
            AccountLoginLauncher.promptCodexLoginAgain(recovery: recovery)
        },
        codexAccountRecoveryLoginLauncher: @escaping @Sendable (String, String) -> Void = { accountID, accountLabel in
            AccountLoginLauncher.openCodexRecoveryLogin(accountID: accountID, accountLabel: accountLabel)
        }
    ) {
        self.settings = settings
        let codexUsageSource = CodexUsageSource(
            codexUsageSynchronizer: codexUsageSynchronizer,
            codexDetailedResetCreditsSynchronizer: codexDetailedResetCreditsSynchronizer,
            codexUsageReader: codexUsageReader
        )
        usageRefreshOrchestrator = UsageRefreshOrchestrator(
            codexUsageSource: { detailedResetCreditsEnabled in
                codexUsageSource.read(detailedResetCreditsEnabled: detailedResetCreditsEnabled)
            },
            claudeUsageReader: claudeUsageReader
        )
        self.codexAccountSwitcher = codexAccountSwitcher
        self.codexAccountRemover = codexAccountRemover
        self.automaticCodexRestarter = automaticCodexRestarter
        self.manualCodexAppRestarter = manualCodexAppRestarter
        self.codexAccountSwitchFailurePrompter = codexAccountSwitchFailurePrompter
        self.codexAccountRecoveryLoginLauncher = codexAccountRecoveryLoginLauncher
        accountRemovalObserver = NotificationCenter.default.addObserver(
            forName: Self.accountRemovalNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh(force: true)
            }
        }
        configureTimer()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            refresh(force: true)
        }
    }

    var language: AppLanguage { settings.language }

    var isLoadingAccountInformation: Bool {
        !hasLoadedAccountInformation
    }

    var menuBarTitle: String {
        let title = switch settings.menuBarDisplayMode {
        case .activeAccountWindows:
            activeAccountWindowTitle
        case .lowestRemaining:
            DisplayFormatters.percentString(lowestRemaining)
        case .totalTokens:
            DisplayFormatters.tokenString(summary.totalTokens)
        case .codexRemaining:
            DisplayFormatters.percentString(codexRemaining)
        }
        return budgetWarningPrefix + title
    }

    var popoverHeaderQuotaTitle: String {
        guard let account = activeAccount else {
            return "\(DisplayFormatters.percentString(lowestRemaining)) \(L.text("remaining", language))"
        }
        let fiveHour = DisplayFormatters.percentString(account.fiveHourWindow?.remainingPercent)
        let weekly = DisplayFormatters.percentString(account.weeklyWindow?.remainingPercent)
        return "5H \(fiveHour) \(L.text("remaining", language)) · WK \(weekly) \(L.text("remaining", language))"
    }

    private var activeAccountWindowTitle: String {
        guard let account = activeAccount else {
            return DisplayFormatters.percentString(lowestRemaining)
        }
        let fiveHour = DisplayFormatters.percentString(account.fiveHourWindow?.remainingPercent)
        let weekly = DisplayFormatters.percentString(account.weeklyWindow?.remainingPercent)
        return "5H \(fiveHour)  WK \(weekly)"
    }

    var lowestRemaining: Double? {
        visibleAccounts.compactMap(\.mostConstrainedRemainingPercent).min()
    }

    var codexRemaining: Double? {
        visibleAccounts.filter { $0.service == .codex }.compactMap(\.mostConstrainedRemainingPercent).min()
    }

    var visibleAccounts: [UsageAccount] {
        accounts.filter { account in
            switch account.service {
            case .codex: settings.showCodexInMenuBar
            case .claudeCode: settings.showClaudeInMenuBar
            }
        }
    }

    var activeAccount: UsageAccount? {
        accounts.first(where: \.isActive) ?? accounts.first
    }

    var summary: UsageSummary {
        UsageStatistics.summarize(points: points, range: selectedRange, customStart: customStart, customEnd: customEnd)
    }

    var hasBudgetWarning: Bool {
        [budgetStatus(for: .today), budgetStatus(for: .thisWeek)].contains { status in
            status.tokenSeverity != .ok || status.costSeverity != .ok
        }
    }

    var rapidUsageAlert: RapidUsageAlert? {
        UsageInsights.rapidUsageAlert(points: points)
    }

    var securityNotes: [String] {
        snapshots.values.flatMap(\.securityNotes)
    }

    var uiDataSourceSnapshots: [UsageSnapshot] {
        snapshots.values
            .filter { snapshot in
                snapshot.status == .live || !snapshot.accounts.isEmpty
            }
            .sorted(by: { $0.service.rawValue < $1.service.rawValue })
    }

    func budgetStatus(for range: UsageRange) -> BudgetStatus {
        let rangeSummary = UsageStatistics.summarize(points: points, range: range)
        switch range {
        case .today:
            return UsageInsights.budgetStatus(
                summary: rangeSummary,
                dailyTokenBudget: settings.dailyTokenBudget,
                dailyCostBudgetUSD: settings.dailyCostBudgetUSD > 0 ? Decimal(settings.dailyCostBudgetUSD) : nil
            )
        case .thisWeek:
            return UsageInsights.budgetStatus(
                summary: rangeSummary,
                dailyTokenBudget: settings.weeklyTokenBudget,
                dailyCostBudgetUSD: settings.weeklyCostBudgetUSD > 0 ? Decimal(settings.weeklyCostBudgetUSD) : nil
            )
        default:
            return UsageInsights.budgetStatus(summary: rangeSummary, dailyTokenBudget: 0, dailyCostBudgetUSD: nil)
        }
    }

    func refresh(force: Bool = false, showManualFeedback: Bool = false) {
        if showManualFeedback {
            isManualRefreshFeedbackVisible = true
        }

        if refreshInFlight {
            if force {
                refreshQueued = true
                if showManualFeedback {
                    manualRefreshQueued = true
                }
            }
            return
        }
        refreshInFlight = true
        isRefreshing = true
        lastError = nil
        let orchestrator = usageRefreshOrchestrator
        let detailedResetCreditsEnabled = settings.detailedResetCreditsEnabled

        DispatchQueue.global(qos: .utility).async {
            let refreshed = orchestrator.refresh(detailedResetCreditsEnabled: detailedResetCreditsEnabled)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.snapshots = refreshed.snapshots
                self.accounts = refreshed.accounts
                self.points = refreshed.points
                self.hasLoadedAccountInformation = true
                self.isRefreshing = false
                self.refreshInFlight = false
                if self.refreshQueued {
                    let queuedShowsManualFeedback = self.manualRefreshQueued
                    self.refreshQueued = false
                    self.manualRefreshQueued = false
                    self.refresh(force: true, showManualFeedback: queuedShowsManualFeedback)
                } else {
                    self.isManualRefreshFeedbackVisible = false
                    if self.retryPendingCodexSwitchRecovery() {
                        return
                    }
                    self.evaluateAutomaticCodexRotation()
                }
            }
        }
    }

    func configureTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(30, settings.refreshInterval), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func sortedAccounts(_ accounts: [UsageAccount]? = nil) -> [UsageAccount] {
        (accounts ?? self.accounts).sorted(using: settings.accountSortMode)
    }

    func accountDisplayGroups(_ accounts: [UsageAccount]? = nil) -> [UsageAccountDisplayGroup] {
        (accounts ?? self.accounts).displayGroupsByIdentity(sortMode: settings.accountSortMode)
    }

    func switchActiveAccount(_ account: UsageAccount) {
        switchCodexAccount(account, restartMode: .manualForceCodexAppRestart)
    }

    func removeAccount(_ account: UsageAccount) {
        guard account.service == .codex else {
            lastError = AccountActionError.unsupportedService.localizedDescription
            return
        }
        let remover = codexAccountRemover
        lastError = nil
        DispatchQueue.global(qos: .utility).async {
            let result = Result {
                try remover(account.id)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if case let .failure(error) = result {
                    self.lastError = error.localizedDescription.redactedForCredentialWords
                    return
                }
                if self.manualCodexRotationOverrideAccountID == account.id {
                    self.manualCodexRotationOverrideAccountID = nil
                }
                if self.pendingCodexSwitchRecovery?.accountID == account.id {
                    self.pendingCodexSwitchRecovery = nil
                }
                self.accounts.removeAll { $0.service == .codex && $0.id == account.id }
                NotificationCenter.default.post(name: Self.accountRemovalNotification, object: nil)
            }
        }
    }

    func evaluateAutomaticCodexRotation(now: Date = Date()) {
        guard settings.autoCodexAccountRotationEnabled, switchingAccountID == nil else { return }
        if shouldHonorManualCodexSelection() {
            return
        }
        let policy = CodexAccountRotationPolicy(
            thresholdRemainingPercent: settings.codexRotationThresholdRemainingPercent
        )
        guard let account = policy.selectedAccount(from: accounts, now: now) else { return }
        switchCodexAccount(account, restartMode: .safeForceCodexAppRestart)
    }

    private func shouldHonorManualCodexSelection() -> Bool {
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
           remaining > settings.codexRotationThresholdRemainingPercent {
            manualCodexRotationOverrideAccountID = nil
            return false
        }
        return true
    }

    private var budgetWarningPrefix: String {
        (hasBudgetWarning || rapidUsageAlert != nil) ? "! " : ""
    }

    private func switchCodexAccount(_ account: UsageAccount, restartMode: CodexSwitchRestartMode) {
        guard switchingAccountID == nil else { return }
        guard account.service == .codex else {
            lastError = AccountActionError.unsupportedService.localizedDescription
            return
        }
        if restartMode == .manualForceCodexAppRestart {
            manualCodexRotationOverrideAccountID = account.id
        }
        switchingAccountID = account.id
        lastError = nil
        let switcher = codexAccountSwitcher
        let restarter = automaticCodexRestarter
        let manualRestarter = manualCodexAppRestarter
        let promptRelogin = codexAccountSwitchFailurePrompter

        DispatchQueue.global(qos: .utility).async {
            let result = Result {
                try switcher(account.id)
            }
            if case .success = result {
                switch restartMode {
                case .manualForceCodexAppRestart:
                    manualRestarter()
                case .safeForceCodexAppRestart:
                    _ = restarter()
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.switchingAccountID = nil
                if case let .failure(error) = result {
                    if self.manualCodexRotationOverrideAccountID == account.id {
                        self.manualCodexRotationOverrideAccountID = nil
                    }
                    let message = Self.codexSwitchFailureMessage(for: error)
                    self.lastError = message.redactedForCredentialWords
                    promptRelogin(self.codexSwitchRecovery(for: account, restartMode: restartMode, message: message))
                } else if self.pendingCodexSwitchRecovery?.accountID == account.id {
                    self.pendingCodexSwitchRecovery = nil
                }
                self.refresh(force: true)
            }
        }
    }

    private func retryPendingCodexSwitchRecovery() -> Bool {
        guard let pending = pendingCodexSwitchRecovery,
              let account = accounts.first(where: { $0.id == pending.accountID && $0.service == .codex })
        else {
            return false
        }
        pendingCodexSwitchRecovery = nil
        switchCodexAccount(account, restartMode: pending.restartMode)
        return true
    }

    private func codexSwitchRecovery(
        for account: UsageAccount,
        restartMode: CodexSwitchRestartMode,
        message: String
    ) -> CodexAccountSwitchRecovery {
        let loginLauncher = codexAccountRecoveryLoginLauncher
        return CodexAccountSwitchRecovery(
            accountID: account.id,
            accountLabel: account.displayName,
            message: message,
            startLogin: { [weak self] in
                self?.pendingCodexSwitchRecovery = PendingCodexSwitchRecovery(
                    accountID: account.id,
                    restartMode: restartMode
                )
                loginLauncher(account.id, account.displayName)
            }
        )
    }

    private static func codexSwitchFailureMessage(for error: Error) -> String {
        let reason = error.localizedDescription.redactedForCredentialWords
        return "The Codex account switch failed. Please login to this Codex account again. Additional phone number authentication might be needed. \(reason)"
    }

    func openLogin(for service: UsageService) {
        AccountLoginLauncher.openLogin(for: service)
    }

    func openLogin(for account: UsageAccount) {
        if account.service == .codex {
            AccountLoginLauncher.openCodexRecoveryLogin(accountID: account.id, accountLabel: account.displayName)
        } else {
            AccountLoginLauncher.openLogin(for: account.service)
        }
    }

    func applyTestData(
        snapshots: [UsageService: UsageSnapshot] = [:],
        accounts: [UsageAccount] = [],
        points: [UsagePoint] = []
    ) {
        self.snapshots = snapshots
        self.accounts = accounts
        self.points = points
        hasLoadedAccountInformation = true
        isRefreshing = false
        isManualRefreshFeedbackVisible = false
        refreshInFlight = false
        refreshQueued = false
        manualRefreshQueued = false
    }

    private struct PendingCodexSwitchRecovery {
        var accountID: String
        var restartMode: CodexSwitchRestartMode
    }

    private enum CodexSwitchRestartMode: Sendable {
        case manualForceCodexAppRestart
        case safeForceCodexAppRestart
    }
}
