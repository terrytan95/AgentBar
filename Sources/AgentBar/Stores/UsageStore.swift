import Foundation

@MainActor
final class UsageStore: ObservableObject {
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
    private let codexUsageSynchronizer: @Sendable () -> CodexUsageSyncResult
    private let codexUsageReader: @Sendable () -> UsageSnapshot
    private let claudeUsageReader: @Sendable () -> UsageSnapshot
    private let codexAccountSwitcher: @Sendable (String) throws -> Void
    private let automaticCodexRestarter: @Sendable () -> CodexAppRestartResult
    private let manualCodexAppRestarter: @Sendable () -> Void
    private var timer: Timer?
    private var refreshInFlight = false
    private var refreshQueued = false
    private var manualRefreshQueued = false
    private var manualCodexRotationOverrideAccountID: String?

    init(
        settings: SettingsStore = SettingsStore(),
        codexUsageSynchronizer: @escaping @Sendable () -> CodexUsageSyncResult = {
            CodexUsageAPISyncer().refreshUsage()
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
        automaticCodexRestarter: @escaping @Sendable () -> CodexAppRestartResult = {
            CodexAppRestarter().restartIfNoWorkIsRunning()
        },
        manualCodexAppRestarter: @escaping @Sendable () -> Void = {
            AccountLoginLauncher.forceRestartCodexApp()
        }
    ) {
        self.settings = settings
        self.codexUsageSynchronizer = codexUsageSynchronizer
        self.codexUsageReader = codexUsageReader
        self.claudeUsageReader = claudeUsageReader
        self.codexAccountSwitcher = codexAccountSwitcher
        self.automaticCodexRestarter = automaticCodexRestarter
        self.manualCodexAppRestarter = manualCodexAppRestarter
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
        switch settings.menuBarDisplayMode {
        case .activeAccountWindows:
            return activeAccountWindowTitle
        case .lowestRemaining:
            return DisplayFormatters.percentString(lowestRemaining)
        case .totalTokens:
            return DisplayFormatters.tokenString(summary.totalTokens)
        case .codexRemaining:
            return DisplayFormatters.percentString(codexRemaining)
        }
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
        let syncCodexUsage = codexUsageSynchronizer
        let readCodexUsage = codexUsageReader
        let readClaudeUsage = claudeUsageReader

        DispatchQueue.global(qos: .utility).async {
            let syncResult = syncCodexUsage()
            var codex = readCodexUsage()
            if let note = syncResult.note {
                codex.securityNotes.append(note)
            }
            let claude = readClaudeUsage()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.snapshots = [.codex: codex, .claudeCode: claude]
                self.accounts = codex.accounts + claude.accounts
                self.points = codex.points + claude.points
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

    func switchActiveAccount(_ account: UsageAccount) {
        switchCodexAccount(account, restartMode: .manualForceCodexAppRestart)
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
                self?.switchingAccountID = nil
                if case let .failure(error) = result {
                    if self?.manualCodexRotationOverrideAccountID == account.id {
                        self?.manualCodexRotationOverrideAccountID = nil
                    }
                    self?.lastError = error.localizedDescription.redactedForCredentialWords
                }
                self?.refresh(force: true)
            }
        }
    }

    func openLogin(for service: UsageService) {
        AccountLoginLauncher.openLogin(for: service)
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

    private enum CodexSwitchRestartMode {
        case manualForceCodexAppRestart
        case safeForceCodexAppRestart
    }
}
