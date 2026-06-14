import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshots: [UsageService: UsageSnapshot] = [:]
    @Published private(set) var accounts: [UsageAccount] = []
    @Published private(set) var points: [UsagePoint] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var hasLoadedAccountInformation = false
    @Published private(set) var lastError: String?
    @Published private(set) var switchingAccountID: String?
    @Published var selectedRange: UsageRange = .today
    @Published var customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @Published var customEnd = Date()

    let settings: SettingsStore
    private let codexAccountSwitcher: @Sendable (String) throws -> Void
    private let automaticCodexRestarter: @Sendable () -> CodexAppRestartResult
    private var timer: Timer?
    private var refreshInFlight = false
    private var refreshQueued = false

    init(
        settings: SettingsStore = SettingsStore(),
        codexAccountSwitcher: @escaping @Sendable (String) throws -> Void = { accountID in
            try CodexAccountSwitcher().switchActiveAccount(accountID: accountID)
        },
        automaticCodexRestarter: @escaping @Sendable () -> CodexAppRestartResult = {
            CodexAppRestarter().restartIfNoWorkIsRunning()
        }
    ) {
        self.settings = settings
        self.codexAccountSwitcher = codexAccountSwitcher
        self.automaticCodexRestarter = automaticCodexRestarter
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

    func refresh(force: Bool = false) {
        if refreshInFlight {
            if force { refreshQueued = true }
            return
        }
        refreshInFlight = true
        isRefreshing = true
        lastError = nil

        DispatchQueue.global(qos: .utility).async {
            let codex = CodexUsageReader().read()
            let claude = ClaudeUsageReader().read()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.snapshots = [.codex: codex, .claudeCode: claude]
                self.accounts = codex.accounts + claude.accounts
                self.points = codex.points + claude.points
                self.hasLoadedAccountInformation = true
                self.isRefreshing = false
                self.refreshInFlight = false
                if self.refreshQueued {
                    self.refreshQueued = false
                    self.refresh(force: true)
                } else {
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
        switchCodexAccount(account, restartMode: .manualIntegrationRestart)
    }

    func evaluateAutomaticCodexRotation(now: Date = Date()) {
        guard settings.autoCodexAccountRotationEnabled, switchingAccountID == nil else { return }
        let policy = CodexAccountRotationPolicy(
            thresholdRemainingPercent: settings.codexRotationThresholdRemainingPercent
        )
        guard let account = policy.selectedAccount(from: accounts, now: now) else { return }
        switchCodexAccount(account, restartMode: .safeForceCodexAppRestart)
    }

    private func switchCodexAccount(_ account: UsageAccount, restartMode: CodexSwitchRestartMode) {
        guard switchingAccountID == nil else { return }
        guard account.service == .codex else {
            lastError = AccountActionError.unsupportedService.localizedDescription
            return
        }
        switchingAccountID = account.id
        lastError = nil
        let switcher = codexAccountSwitcher
        let restarter = automaticCodexRestarter

        DispatchQueue.global(qos: .utility).async {
            let result = Result {
                try switcher(account.id)
            }
            if case .success = result {
                switch restartMode {
                case .manualIntegrationRestart:
                    AccountLoginLauncher.restartIntegration(for: account.service)
                case .safeForceCodexAppRestart:
                    _ = restarter()
                }
            }

            DispatchQueue.main.async { [weak self] in
                self?.switchingAccountID = nil
                if case let .failure(error) = result {
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
        refreshInFlight = false
        refreshQueued = false
    }

    private enum CodexSwitchRestartMode {
        case manualIntegrationRestart
        case safeForceCodexAppRestart
    }
}
