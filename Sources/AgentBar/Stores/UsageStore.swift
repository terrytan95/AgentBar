import Combine
import Foundation

private final class DarwinNotificationObserver {
    private let name: CFString
    private let handler: () -> Void

    init(name: String, handler: @escaping () -> Void) {
        self.name = name as CFString
        self.handler = handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<DarwinNotificationObserver>
                    .fromOpaque(observer)
                    .takeUnretainedValue()
                    .handler()
            },
            self.name,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(name),
            nil
        )
    }
}

private struct AppSnapshot: Equatable {
    var snapshots: [UsageService: UsageSnapshot] = [:]
    var accounts: [UsageAccount] = []
    var points: [UsagePoint] = []
    var tasks: [AgentTask] = []
    var auditTasks: [AgentTask] = []
    var quotaCapacityHistory = QuotaCapacityHistory(samples: [])
    var isRefreshing = false
    var isManualRefreshFeedbackVisible = false
    var hasLoadedAccountInformation = false
    var hasFinishedInitialSessionLoad = false
    var generation: UInt64 = 0
}

@MainActor
final class UsageStore: ObservableObject {
    static let accountRemovalNotification = Notification.Name("AgentBarUsageStoreAccountRemoval")
    private static let taskHistoryWindow: TimeInterval = 24 * 60 * 60
    private static let maximumTaskHistoryCount = 200

    @Published private var appSnapshot = AppSnapshot()
    @Published private(set) var lastError: String?
    @Published private(set) var switchingAccountID: String?
    @Published var selectedRange: UsageRange = .today {
        didSet { invalidateStatisticsCaches() }
    }
    @Published var customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date() {
        didSet { invalidateStatisticsCaches() }
    }
    @Published var customEnd = Date() {
        didSet { invalidateStatisticsCaches() }
    }

    let settings: SettingsStore
    private let refreshLifecycle: UsageRefreshLifecycle
    private let codexTaskReader: @Sendable () -> [AgentTask]
    private let codexAccountLifecycle = CodexAccountLifecycle()
    private let codexAccountSwitcher: (@Sendable (String) throws -> Void)?
    private let codexAccountRemover: @Sendable (String) throws -> Void
    private let automaticCodexRestarter: @Sendable () -> CodexAppRestartResult
    private let manualCodexAppRestarter: @Sendable () -> Void
    private let codexAccountSwitchFailurePrompter: @Sendable (CodexAccountSwitchRecovery) -> Void
    private let codexAccountRecoveryLoginLauncher: @Sendable (String, String) -> Void
    private let codexAccountLoginSuccessNotifier: @Sendable (String) -> Void
    private let quotaResetNotifier: @Sendable (QuotaResetNotification) -> Void
    private let taskCompletionNotifier: @Sendable (TaskCompletionNotification) -> Void
    private let accessTokenExpiryReminderReconciler: @MainActor @Sendable ([UsageAccount], Bool, AppLanguage) -> Void
    private let quotaCapacityHistoryStore: QuotaCapacityHistoryStore
    private var timer: Timer?
    private var initialRefreshTask: Task<Void, Never>?
    private var taskRefreshTask: Task<Void, Never>?
    private var accountRemovalObserver: NSObjectProtocol?
    private var codexRecoveryLoginObserver: DarwinNotificationObserver?
    private var refreshIntervalObserver: AnyCancellable?
    private var statisticsScopeObserver: AnyCancellable?
    private var accessTokenExpiryNotificationsObserver: AnyCancellable?
    private var isStarted = false
    private var taskRefreshInFlight = false
    private var taskRefreshGeneration: UInt64 = 0
    private var hasLoadedTaskCenter = false
    private var lastTaskRefreshAt: Date?
    private var summaryCache: UsageSummary?
    private var periodChangeCache: UsagePeriodChange?
    private var selectedRangePointsCache: [UsagePoint]?
    private var selectedRangeProjectionCache: UsageRangeProjection?
    private var yearActivityBarsCache: [DailyUsageBar]?

    init(
        settings: SettingsStore = .shared,
        codexUsageSynchronizer: (@Sendable () async -> CodexUsageSyncResult)? = nil,
        codexUsagePreviewReader: (@Sendable () -> UsageSnapshot)? = nil,
        codexUsageReadCycleFactory: (@Sendable () -> CodexUsageReadCycle)? = nil,
        codexUsageReader: @escaping @Sendable () -> UsageSnapshot = {
            CodexUsageReader().read()
        },
        codexTaskReader: @escaping @Sendable () -> [AgentTask] = {
            CodexTaskCenterReader().read()
        },
        claudeUsageReader: @escaping @Sendable () -> UsageSnapshot = {
            ClaudeUsageReader.discover(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
        },
        xaiUsageReader: @escaping @Sendable () async -> UsageSnapshot? = {
            await XAIUsageReader().read()
        },
        cursorUsageReader: @escaping @Sendable () async -> UsageSnapshot? = { nil },
        codexAccountSwitcher: (@Sendable (String) throws -> Void)? = nil,
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
        },
        codexAccountLoginSuccessNotifier: @escaping @Sendable (String) -> Void = { accountLabel in
            AccountLoginLauncher.showCodexLoginSuccess(accountLabel: accountLabel)
        },
        quotaResetNotifier: @escaping @Sendable (QuotaResetNotification) -> Void = { notification in
            QuotaResetDesktopNotifier.notify(notification)
        },
        taskCompletionNotifier: @escaping @Sendable (TaskCompletionNotification) -> Void = { notification in
            TaskCompletionDesktopNotifier.notify(notification)
        },
        accessTokenExpiryReminderReconciler: @escaping @MainActor @Sendable ([UsageAccount], Bool, AppLanguage) -> Void = { accounts, enabled, language in
            AccessTokenExpiryDesktopScheduler.shared.reconcile(accounts: accounts, enabled: enabled, language: language)
        },
        quotaCapacityHistoryStore: QuotaCapacityHistoryStore = QuotaCapacityHistoryStore(),
        refreshTimeout: Duration = .seconds(180)
    ) {
        self.settings = settings
        self.quotaCapacityHistoryStore = quotaCapacityHistoryStore
        let resolvedCodexUsageSynchronizer: @Sendable (Bool) async -> CodexUsageSyncResult
        if let codexUsageSynchronizer {
            resolvedCodexUsageSynchronizer = { _ in await codexUsageSynchronizer() }
        } else {
            resolvedCodexUsageSynchronizer = { [weak settings] refreshAllAccounts in
                let configuration = await MainActor.run {
                    (
                        settings?.reuseCLIProxyAPIAuthEnabled ?? false,
                        settings?.reuseOpenCodexAuthEnabled ?? false,
                        settings?.cliProxyAPIAuthDirectory ?? ""
                    )
                }
                return await CodexUsageAPISyncer(
                    reusesCLIProxyAPIAuth: configuration.0,
                    reusesOpenCodexAuth: configuration.1,
                    cliProxyAPIAuthDirectory: configuration.2,
                    accountPollDelay: .seconds(5),
                    resetCreditsCacheDuration: 30 * 60
                ).refreshUsage(refreshAllAccounts: refreshAllAccounts)
            }
        }
        refreshLifecycle = UsageRefreshLifecycle(
            codexUsageSynchronizer: resolvedCodexUsageSynchronizer,
            codexUsagePreviewReader: codexUsagePreviewReader,
            codexUsageReader: codexUsageReader,
            codexUsageReadCycleFactory: codexUsageReadCycleFactory,
            claudeUsageReader: claudeUsageReader,
            xaiUsageReader: xaiUsageReader,
            cursorUsageReader: cursorUsageReader,
            refreshTimeout: refreshTimeout
        )
        self.codexTaskReader = codexTaskReader
        self.codexAccountSwitcher = codexAccountSwitcher
        self.codexAccountRemover = codexAccountRemover
        self.automaticCodexRestarter = automaticCodexRestarter
        self.manualCodexAppRestarter = manualCodexAppRestarter
        self.codexAccountSwitchFailurePrompter = codexAccountSwitchFailurePrompter
        self.codexAccountRecoveryLoginLauncher = codexAccountRecoveryLoginLauncher
        self.codexAccountLoginSuccessNotifier = codexAccountLoginSuccessNotifier
        self.quotaResetNotifier = quotaResetNotifier
        self.taskCompletionNotifier = taskCompletionNotifier
        self.accessTokenExpiryReminderReconciler = accessTokenExpiryReminderReconciler
    }

    var snapshots: [UsageService: UsageSnapshot] { appSnapshot.snapshots }
    var accounts: [UsageAccount] { appSnapshot.accounts }
    var points: [UsagePoint] { appSnapshot.points }
    var tasks: [AgentTask] { appSnapshot.tasks }
    var auditTasks: [AgentTask] { appSnapshot.auditTasks }
    var quotaCapacityHistory: QuotaCapacityHistory { appSnapshot.quotaCapacityHistory }
    var isRefreshing: Bool { appSnapshot.isRefreshing }
    var isManualRefreshFeedbackVisible: Bool { appSnapshot.isManualRefreshFeedbackVisible }
    var hasLoadedAccountInformation: Bool { appSnapshot.hasLoadedAccountInformation }
    var refreshGeneration: UInt64 { appSnapshot.generation }
    var accountsPublisher: AnyPublisher<[UsageAccount], Never> {
        $appSnapshot.map(\.accounts).removeDuplicates().eraseToAnyPublisher()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        var next = appSnapshot
        next.quotaCapacityHistory = quotaCapacityHistoryStore.load()
        publish(next)
        accountRemovalObserver = NotificationCenter.default.addObserver(
            forName: Self.accountRemovalNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                self.refresh(force: true)
            }
        }
        codexRecoveryLoginObserver = DarwinNotificationObserver(name: CodexAccountStorage.recoveryLoginFinishedNotificationName) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                self.refresh(force: true)
            }
        }
        configureTimer()
        refreshIntervalObserver = settings.$refreshInterval
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isStarted else { return }
                    self.configureTimer()
                }
            }
        statisticsScopeObserver = settings.$showAggregatedAccountData
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isStarted else { return }
                    invalidateStatisticsCaches()
                    objectWillChange.send()
                }
            }
        accessTokenExpiryNotificationsObserver = settings.$accessTokenExpiryNotificationsEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                Task { @MainActor [weak self] in
                    guard let self, self.isStarted else { return }
                    self.accessTokenExpiryReminderReconciler(self.accounts, enabled, self.language)
                }
            }
        initialRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            guard let self, self.isStarted else { return }
            self.refresh(force: true)
        }
    }

    func stop() {
        isStarted = false
        timer?.invalidate()
        timer = nil
        initialRefreshTask?.cancel()
        initialRefreshTask = nil
        taskRefreshTask?.cancel()
        taskRefreshTask = nil
        taskRefreshGeneration &+= 1
        taskRefreshInFlight = false
        refreshLifecycle.reset()

        if let accountRemovalObserver {
            NotificationCenter.default.removeObserver(accountRemovalObserver)
        }
        accountRemovalObserver = nil
        codexRecoveryLoginObserver = nil
        refreshIntervalObserver = nil
        statisticsScopeObserver = nil
        accessTokenExpiryNotificationsObserver = nil

        guard appSnapshot.isRefreshing || appSnapshot.isManualRefreshFeedbackVisible else { return }
        var next = appSnapshot
        next.isRefreshing = false
        next.isManualRefreshFeedbackVisible = false
        publish(next)
    }

    var language: AppLanguage { settings.language }

    var isLoadingAccountInformation: Bool {
        !hasLoadedAccountInformation
    }

    var isLoadingSessionData: Bool {
        !appSnapshot.hasFinishedInitialSessionLoad
    }

    var menuBarTitle: String {
        switch settings.menuBarDisplayMode {
        case .activeAccountWindows:
            activeAccountWindowTitle
        case .lowestRemaining:
            mostConstrainedMenuBarQuotaTitle
        case .totalTokens:
            DisplayFormatters.tokenString(menuBarSummary.totalTokens)
        case .codexRemaining:
            DisplayFormatters.percentString(codexRemaining)
        }
    }

    var popoverHeaderQuotaTitle: String {
        guard let account = activeAccount else {
            if summary.totalTokens > 0 {
                return "\(DisplayFormatters.tokenString(summary.totalTokens)) \(L.text("tokens", language))"
            }
            return "\(DisplayFormatters.percentString(lowestRemaining)) \(L.text("remaining", language))"
        }
        let titles = accountWindowTitles(account)
        guard !titles.isEmpty else {
            return "\(DisplayFormatters.tokenString(summary.totalTokens)) \(L.text("tokens", language))"
        }
        return titles.map { "\($0) \(L.text("remaining", language))" }.joined(separator: " · ")
    }

    private var activeAccountWindowTitle: String {
        guard let account = menuBarActiveAccount else {
            if menuBarSummary.totalTokens > 0 {
                return DisplayFormatters.tokenString(menuBarSummary.totalTokens)
            }
            return DisplayFormatters.percentString(lowestRemaining)
        }
        let titles = accountWindowTitles(account)
        return titles.isEmpty ? DisplayFormatters.tokenString(menuBarSummary.totalTokens) : titles.joined(separator: "  ")
    }

    private func accountWindowTitles(_ account: UsageAccount) -> [String] {
        [
            account.fiveHourWindow.map { "5H \(DisplayFormatters.percentString($0.remainingPercent))" },
            account.weeklyWindow.map { "WK \(DisplayFormatters.percentString($0.remainingPercent))" },
            account.cursorSubscriptionUsage.map { "Cursor \(DisplayFormatters.percentString($0.includedRemainingPercent))" }
        ].compactMap { $0 }
    }

    var lowestRemaining: Double? {
        mostConstrainedMenuBarQuota?.remainingPercent
    }

    var codexRemaining: Double? {
        menuBarAccounts.filter { $0.service == .codex }.compactMap(\.mostConstrainedRemainingPercent).min()
    }

    var menuBarEnabledServices: [UsageService] {
        UsageService.allCases.filter(showsInMenuBar)
    }

    private var menuBarAccounts: [UsageAccount] {
        accounts.filter { showsInMenuBar($0.service) }
    }

    private var menuBarActiveAccount: UsageAccount? {
        menuBarAccounts.first(where: \.isActive) ?? menuBarAccounts.first
    }

    private var menuBarSummary: UsageSummary {
        UsageRangeProjection(
            points: points.filter { showsInMenuBar($0.service) },
            range: selectedRange,
            customStart: customStart,
            customEnd: customEnd
        ).summary
    }

    private func showsInMenuBar(_ service: UsageService) -> Bool {
        switch service {
        case .codex: settings.showCodexInMenuBar
        case .claudeCode: settings.showClaudeInMenuBar
        case .xaiAPI: settings.showGrokInMenuBar
        case .cursorAgent: settings.showCursorAgentInMenuBar
        }
    }

    private var mostConstrainedMenuBarQuotaTitle: String {
        guard let quota = mostConstrainedMenuBarQuota else {
            return DisplayFormatters.percentString(nil)
        }
        return "\(quota.label) \(DisplayFormatters.percentString(quota.remainingPercent))"
    }

    private var mostConstrainedMenuBarQuota: (label: String, remainingPercent: Double)? {
        menuBarAccounts
            .flatMap(menuBarQuotaCandidates)
            .min { lhs, rhs in
                if lhs.remainingPercent != rhs.remainingPercent {
                    return lhs.remainingPercent < rhs.remainingPercent
                }
                return lhs.label < rhs.label
            }
    }

    private func menuBarQuotaCandidates(for account: UsageAccount) -> [(label: String, remainingPercent: Double)] {
        switch account.service {
        case .codex:
            return [
                account.fiveHourWindow.map { ("5H", $0.remainingPercent) },
                account.weeklyWindow.map { ("WK", $0.remainingPercent) }
            ].compactMap { $0 }
        case .claudeCode:
            return []
        case .xaiAPI:
            guard let usage = account.grokSubscriptionUsage,
                  let used = usage.onDemandUsedUSD,
                  let cap = usage.onDemandCapUSD
            else { return [] }
            let usedValue = NSDecimalNumber(decimal: used).doubleValue
            let capValue = NSDecimalNumber(decimal: cap).doubleValue
            guard capValue > 0 else { return [] }
            return [("Grok", 100 - min(max(usedValue / capValue * 100, 0), 100))]
        case .cursorAgent:
            guard let usage = account.cursorSubscriptionUsage else { return [] }
            return [("Cursor", usage.includedRemainingPercent)]
        }
    }

    var activeAccount: UsageAccount? {
        accounts.first(where: \.isActive) ?? accounts.first
    }

    private static func accountsForDisplay(_ accounts: [UsageAccount]) -> [UsageAccount] {
        let activeCodex = accounts.first { $0.service == .codex && $0.isActive }
            ?? accounts.first { $0.service == .codex }
        guard activeCodex?.fiveHourWindow == nil, activeCodex?.weeklyWindow != nil else { return accounts }
        return accounts.map { account in
            guard account.service == .codex else { return account }
            var account = account
            account.fiveHourWindow = nil
            return account
        }
    }

    var usageDataDisplayPoints: [UsagePoint] {
        guard !settings.showAggregatedAccountData, let activeService = activeAccount?.service else {
            return points
        }
        return points.filter { $0.service == activeService }
    }

    var summary: UsageSummary {
        if let summaryCache { return summaryCache }
        let summary = selectedRangeProjection.summary
        summaryCache = summary
        return summary
    }

    var periodChange: UsagePeriodChange {
        if let periodChangeCache { return periodChangeCache }
        let change = selectedRangeProjection.periodChange
        periodChangeCache = change
        return change
    }

    var selectedRangePoints: [UsagePoint] {
        if let selectedRangePointsCache { return selectedRangePointsCache }
        let rangePoints = selectedRangeProjection.rangePoints
        selectedRangePointsCache = rangePoints
        return rangePoints
    }

    private var selectedRangeProjection: UsageRangeProjection {
        if let selectedRangeProjectionCache { return selectedRangeProjectionCache }
        let projection = UsageRangeProjection(points: usageDataDisplayPoints, range: selectedRange, customStart: customStart, customEnd: customEnd)
        selectedRangeProjectionCache = projection
        return projection
    }

    var yearActivityBars: [DailyUsageBar] {
        if let yearActivityBarsCache { return yearActivityBarsCache }
        let bars = UsageStatistics.yearActivityBars(points: points)
        yearActivityBarsCache = bars
        return bars
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
        var next = appSnapshot
        next.isManualRefreshFeedbackVisible = next.isManualRefreshFeedbackVisible || showManualFeedback
        let started = refreshLifecycle.refresh(
            force: force,
            refreshAllCodexAccounts: showManualFeedback
        ) { [weak self] completion in
            self?.finishRefresh(completion)
        }
        if started {
            next.isRefreshing = true
            if lastError != nil {
                lastError = nil
            }
        }
        if next.isRefreshing != appSnapshot.isRefreshing ||
            next.isManualRefreshFeedbackVisible != appSnapshot.isManualRefreshFeedbackVisible {
            publish(next)
        }
    }

    private func finishRefresh(_ completion: UsageRefreshLifecycle.Completion) {
        if case let .progress(result) = completion {
            var next = appSnapshot
            next.snapshots = result.snapshots
            next.accounts = Self.accountsForDisplay(result.accounts)
            next.points = result.points
            next.tasks = Self.visibleTasks(result.tasks, now: Date())
            next.auditTasks = Self.sortedAuditTasks(result.tasks)
            next.hasLoadedAccountInformation = true
            next.generation = result.generation
            publish(next)
            return
        }
        guard case let .result(result) = completion else {
            var next = appSnapshot
            next.isRefreshing = false
            next.isManualRefreshFeedbackVisible = false
            next.hasFinishedInitialSessionLoad = true
            publish(next)
            NSLog("AgentBar usage refresh timed out")
            return
        }

        let now = Date()
        let previous = appSnapshot
        let taskCenterWasLoaded = hasLoadedTaskCenter
        let completedAfter = lastTaskRefreshAt ?? now
        var next = previous
        next.snapshots = result.snapshots
        next.accounts = Self.accountsForDisplay(result.accounts)
        next.points = result.points
        next.tasks = Self.visibleTasks(result.tasks, now: now)
        next.auditTasks = Self.sortedAuditTasks(result.tasks)
        next.quotaCapacityHistory = previous.quotaCapacityHistory.appendingSample(
            account: next.accounts.first(where: \.isActive) ?? next.accounts.first,
            points: next.points,
            now: now,
            minimumInterval: settings.quotaCapacityHistoryInterval
        )
        next.isRefreshing = false
        next.isManualRefreshFeedbackVisible = false
        next.hasLoadedAccountInformation = true
        next.hasFinishedInitialSessionLoad = true
        next.generation = result.generation
        publish(next)

        hasLoadedTaskCenter = true
        lastTaskRefreshAt = now
        accessTokenExpiryReminderReconciler(
            next.accounts,
            settings.accessTokenExpiryNotificationsEnabled,
            language
        )
        if next.quotaCapacityHistory != previous.quotaCapacityHistory {
            quotaCapacityHistoryStore.save(next.quotaCapacityHistory)
        }
        if taskCenterWasLoaded, settings.taskCompletionNotificationsEnabled {
            for notification in TaskCompletionNotifications.newlyCompleted(
                previous: previous.tasks,
                current: next.tasks,
                completedAfter: completedAfter,
                language: language
            ) {
                taskCompletionNotifier(notification)
            }
        }
        sendQuotaResetNotifications(
            previousAccounts: previous.accounts,
            wasLoaded: previous.hasLoadedAccountInformation,
            now: now
        )
        if !retryPendingCodexSwitchRecovery() {
            evaluateAutomaticCodexRotation()
        }
    }

    func configureTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(SettingsStore.minimumRefreshInterval, settings.refreshInterval), repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isStarted else { return }
                self.refresh()
            }
        }
    }

    func refreshTaskCenter() {
        guard isStarted, !taskRefreshInFlight else { return }
        taskRefreshInFlight = true
        taskRefreshGeneration &+= 1
        let generation = taskRefreshGeneration
        let codexTaskReader = codexTaskReader

        taskRefreshTask = Task.detached(priority: .utility) { [weak self] in
            let tasks = codexTaskReader()
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self,
                      self.isStarted,
                      self.taskRefreshGeneration == generation
                else { return }
                self.taskRefreshTask = nil
                self.taskRefreshInFlight = false
                self.applyTaskCenter(tasks)
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
        guard account.supportsAccountSwitching else { return }
        switchCodexAccount(account, restartMode: .manualForceCodexAppRestart)
    }

    func removeAccount(_ account: UsageAccount) {
        guard account.service == .codex, account.supportsAccountRemoval else {
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
                self.codexAccountLifecycle.removeAccount(account.id)
                var next = self.appSnapshot
                next.accounts.removeAll { $0.service == .codex && $0.id == account.id }
                self.publish(next)
                NotificationCenter.default.post(name: Self.accountRemovalNotification, object: nil)
            }
        }
    }

    func evaluateAutomaticCodexRotation(now: Date = Date()) {
        guard let account = codexAccountLifecycle.automaticRotationAccount(
            accounts: accounts,
            autoRotationEnabled: settings.autoCodexAccountRotationEnabled,
            thresholdRemainingPercent: settings.codexRotationThresholdRemainingPercent,
            switchingAccountID: switchingAccountID,
            now: now
        ) else { return }
        switchCodexAccount(account, restartMode: .safeForceCodexAppRestart)
    }

    private func invalidateStatisticsCaches() {
        summaryCache = nil
        periodChangeCache = nil
        selectedRangePointsCache = nil
        selectedRangeProjectionCache = nil
    }

    private func switchCodexAccount(
        _ account: UsageAccount,
        restartMode: CodexAccountLifecycle.RestartMode,
        showLoginSuccess: Bool = false
    ) {
        do {
            guard let switchingAccountID = try codexAccountLifecycle.beginSwitch(
                account: account,
                restartMode: restartMode,
                switchingAccountID: switchingAccountID
            ) else { return }
            self.switchingAccountID = switchingAccountID
        } catch {
            lastError = error.localizedDescription
            return
        }
        lastError = nil
        let switcher = codexAccountSwitcher
        let reusesCLIProxyAPIAuth = settings.reuseCLIProxyAPIAuthEnabled
        let cliProxyAPIAuthDirectory = settings.cliProxyAPIAuthDirectory
        let restarter = automaticCodexRestarter
        let manualRestarter = manualCodexAppRestarter
        let promptRelogin = codexAccountSwitchFailurePrompter
        let notifyLoginSuccess = codexAccountLoginSuccessNotifier

        DispatchQueue.global(qos: .utility).async {
            let result = Result {
                if let switcher {
                    try switcher(account.id)
                } else {
                    try CodexAccountSwitcher(
                        reusesCLIProxyAPIAuth: reusesCLIProxyAPIAuth,
                        cliProxyAPIAuthDirectory: cliProxyAPIAuthDirectory
                    ).switchActiveAccount(accountID: account.id)
                }
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
                switch self.codexAccountLifecycle.finishSwitch(
                    account: account,
                    restartMode: restartMode,
                    result: result,
                    loginLauncher: self.codexAccountRecoveryLoginLauncher
                ) {
                case .success:
                    if showLoginSuccess {
                        notifyLoginSuccess(account.displayName)
                    }
                case .failure(let message, let recovery):
                    self.lastError = message.redactedForCredentialWords
                    promptRelogin(recovery)
                }
                self.refresh(force: true)
            }
        }
    }

    private func retryPendingCodexSwitchRecovery() -> Bool {
        guard let pending = codexAccountLifecycle.pendingRecoverySwitch(accounts: accounts) else { return false }
        switchCodexAccount(pending.account, restartMode: pending.restartMode, showLoginSuccess: true)
        return true
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
        points: [UsagePoint] = [],
        tasks: [AgentTask] = []
    ) {
        stop()

        var next = appSnapshot
        next.snapshots = snapshots
        next.accounts = Self.accountsForDisplay(accounts)
        next.points = points
        next.tasks = tasks
        next.auditTasks = tasks
        next.hasLoadedAccountInformation = true
        next.hasFinishedInitialSessionLoad = true
        next.isRefreshing = false
        next.isManualRefreshFeedbackVisible = false
        publish(next)
        hasLoadedTaskCenter = true
        lastTaskRefreshAt = Date()
    }

    func recordQuotaCapacitySample(now: Date = Date()) {
        let history = quotaCapacityHistory.appendingSample(
            account: activeAccount,
            points: points,
            now: now,
            minimumInterval: settings.quotaCapacityHistoryInterval
        )
        guard history != quotaCapacityHistory else { return }
        var next = appSnapshot
        next.quotaCapacityHistory = history
        publish(next)
        quotaCapacityHistoryStore.save(history)
    }

    private func sendQuotaResetNotifications(previousAccounts: [UsageAccount], wasLoaded: Bool, now: Date = Date()) {
        guard wasLoaded, settings.quotaResetNotificationsEnabled else { return }
        for notification in QuotaResetNotifications.refreshedQuotaWindows(
            previous: previousAccounts,
            current: accounts,
            now: now,
            language: language
        ) {
            quotaResetNotifier(notification)
        }
    }

    private func applyTaskCenter(
        _ nextTasks: [AgentTask],
        now: Date = Date(),
        updatesAuditHistory: Bool = false
    ) {
        let previousTasks = tasks
        var next = appSnapshot
        if updatesAuditHistory {
            next.auditTasks = Self.sortedAuditTasks(nextTasks)
        }

        let completedAfter = lastTaskRefreshAt ?? now
        next.tasks = Self.visibleTasks(nextTasks, now: now)
        publish(next)

        if hasLoadedTaskCenter, settings.taskCompletionNotificationsEnabled {
            for notification in TaskCompletionNotifications.newlyCompleted(
                previous: previousTasks,
                current: next.tasks,
                completedAfter: completedAfter,
                language: language
            ) {
                taskCompletionNotifier(notification)
            }
        }
        hasLoadedTaskCenter = true
        lastTaskRefreshAt = now
    }

    private static func sortedAuditTasks(_ tasks: [AgentTask]) -> [AgentTask] {
        tasks.sorted { lhs, rhs in
            if lhs.auditDate != rhs.auditDate { return lhs.auditDate > rhs.auditDate }
            return lhs.id > rhs.id
        }
    }

    private static func visibleTasks(_ tasks: [AgentTask], now: Date) -> [AgentTask] {
        let historyCutoff = now.addingTimeInterval(-taskHistoryWindow)
        return Array(tasks
            .filter { ($0.completedAt ?? $0.lastActivityAt) >= historyCutoff }
            .sorted { lhs, rhs in
                let lhsDate = lhs.completedAt ?? lhs.lastActivityAt
                let rhsDate = rhs.completedAt ?? rhs.lastActivityAt
                return lhsDate > rhsDate
            }
            .prefix(Self.maximumTaskHistoryCount))
    }

    private func publish(_ next: AppSnapshot) {
        guard appSnapshot != next else { return }
        if appSnapshot.points != next.points || appSnapshot.accounts != next.accounts {
            invalidateStatisticsCaches()
            yearActivityBarsCache = nil
        }
        appSnapshot = next
    }

}
