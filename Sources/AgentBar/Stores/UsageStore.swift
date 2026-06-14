import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshots: [UsageService: UsageSnapshot] = [:]
    @Published private(set) var accounts: [UsageAccount] = []
    @Published private(set) var points: [UsagePoint] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var hasLoadedAccountInformation = false
    @Published private(set) var lastError: String?
    @Published var selectedRange: UsageRange = .today
    @Published var customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @Published var customEnd = Date()

    let settings: SettingsStore
    private var timer: Timer?
    private var refreshInFlight = false

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        configureTimer()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            refresh()
        }
    }

    var language: AppLanguage { settings.language }

    var isLoadingAccountInformation: Bool {
        !hasLoadedAccountInformation || isRefreshing
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

    func refresh() {
        guard !refreshInFlight else { return }
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
            }
        }
    }

    func configureTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(15, settings.refreshInterval), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
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
        refreshInFlight = false
    }
}
