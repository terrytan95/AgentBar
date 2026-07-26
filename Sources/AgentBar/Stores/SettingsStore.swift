import Foundation
import ServiceManagement

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case activeAccountWindows
    case lowestRemaining
    case totalTokens
    case codexRemaining

    var id: String { rawValue }
}

enum AccountSortMode: String, CaseIterable, Identifiable {
    case quotaPressure
    case activeFirst
    case alphabetical

    var id: String { rawValue }
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var language: AppLanguage {
        didSet { persist(language.rawValue, forKey: Keys.language) }
    }

    @Published var refreshInterval: TimeInterval {
        didSet { persist(refreshInterval, forKey: Keys.refreshInterval) }
    }

    @Published var quotaCapacityHistoryInterval: TimeInterval {
        didSet {
            let clamped = Self.clampedQuotaCapacityHistoryInterval(quotaCapacityHistoryInterval)
            if clamped != quotaCapacityHistoryInterval {
                quotaCapacityHistoryInterval = clamped
            }
            persist(clamped, forKey: Keys.quotaCapacityHistoryInterval)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            persist(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLoginItemPreference()
        }
    }

    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet { persist(menuBarDisplayMode.rawValue, forKey: Keys.menuBarDisplayMode) }
    }

    @Published var showCodexInMenuBar: Bool {
        didSet { persist(showCodexInMenuBar, forKey: Keys.showCodexInMenuBar) }
    }

    @Published var showCodexSidebarQuotaOverlay: Bool {
        didSet { persist(showCodexSidebarQuotaOverlay, forKey: Keys.showCodexSidebarQuotaOverlay) }
    }

    @Published var codexSidebarQuotaOverlayIndependent: Bool {
        didSet { persist(codexSidebarQuotaOverlayIndependent, forKey: Keys.codexSidebarQuotaOverlayIndependent) }
    }

    @Published var quotaWidgetHotKey: QuotaWidgetHotKey? {
        didSet {
            persist(try? JSONEncoder().encode(quotaWidgetHotKey), forKey: Keys.quotaWidgetHotKey)
        }
    }

    @Published var didCompleteQuotaWidgetOnboarding: Bool {
        didSet { persist(didCompleteQuotaWidgetOnboarding, forKey: Keys.didCompleteQuotaWidgetOnboarding) }
    }

    @Published var showClaudeInMenuBar: Bool {
        didSet { persist(showClaudeInMenuBar, forKey: Keys.showClaudeInMenuBar) }
    }

    @Published var useDarkAppearance: Bool {
        didSet { persist(useDarkAppearance, forKey: Keys.useDarkAppearance) }
    }

    @Published var useTranslucentAppearance: Bool {
        didSet { persist(useTranslucentAppearance, forKey: Keys.useTranslucentAppearance) }
    }

    @Published var accountSortMode: AccountSortMode {
        didSet { persist(accountSortMode.rawValue, forKey: Keys.accountSortMode) }
    }

    @Published var showAggregatedAccountData: Bool {
        didSet { persist(showAggregatedAccountData, forKey: Keys.showAggregatedAccountData) }
    }

    @Published var autoCodexAccountRotationEnabled: Bool {
        didSet { persist(autoCodexAccountRotationEnabled, forKey: Keys.autoCodexAccountRotationEnabled) }
    }

    @Published var quotaResetNotificationsEnabled: Bool {
        didSet { persist(quotaResetNotificationsEnabled, forKey: Keys.quotaResetNotificationsEnabled) }
    }

    @Published var taskCompletionNotificationsEnabled: Bool {
        didSet { persist(taskCompletionNotificationsEnabled, forKey: Keys.taskCompletionNotificationsEnabled) }
    }

    @Published var accessTokenExpiryNotificationsEnabled: Bool {
        didSet { persist(accessTokenExpiryNotificationsEnabled, forKey: Keys.accessTokenExpiryNotificationsEnabled) }
    }

    @Published private(set) var projectBudgets: [ProjectBudget] {
        didSet {
            guard let data = try? JSONEncoder().encode(projectBudgets) else { return }
            persist(data, forKey: Keys.projectBudgets)
        }
    }

    @Published var codexRotationThresholdRemainingPercent: Double {
        didSet {
            let clamped = Self.clampedRotationThreshold(codexRotationThresholdRemainingPercent)
            if clamped != codexRotationThresholdRemainingPercent {
                codexRotationThresholdRemainingPercent = clamped
            }
            persist(clamped, forKey: Keys.codexRotationThresholdRemainingPercent)
        }
    }

    @Published var dailyTokenBudget: Int {
        didSet {
            let clamped = Self.clampedBudgetCount(dailyTokenBudget)
            if clamped != dailyTokenBudget {
                dailyTokenBudget = clamped
            }
            persist(clamped, forKey: Keys.dailyTokenBudget)
        }
    }

    @Published var weeklyTokenBudget: Int {
        didSet {
            let clamped = Self.clampedBudgetCount(weeklyTokenBudget)
            if clamped != weeklyTokenBudget {
                weeklyTokenBudget = clamped
            }
            persist(clamped, forKey: Keys.weeklyTokenBudget)
        }
    }

    @Published var dailyCostBudgetUSD: Double {
        didSet {
            let clamped = Self.clampedBudgetCost(dailyCostBudgetUSD)
            if clamped != dailyCostBudgetUSD {
                dailyCostBudgetUSD = clamped
            }
            persist(clamped, forKey: Keys.dailyCostBudgetUSD)
        }
    }

    @Published var weeklyCostBudgetUSD: Double {
        didSet {
            let clamped = Self.clampedBudgetCost(weeklyCostBudgetUSD)
            if clamped != weeklyCostBudgetUSD {
                weeklyCostBudgetUSD = clamped
            }
            persist(clamped, forKey: Keys.weeklyCostBudgetUSD)
        }
    }

    var popoverHeight: Double {
        get { storedPopoverHeight }
        set {
            let clampedHeight = Self.clampedPopoverHeight(newValue, maximumHeight: popoverMaximumHeight)
            guard storedPopoverHeight != clampedHeight else {
                persist(clampedHeight, forKey: Keys.popoverHeight)
                return
            }
            objectWillChange.send()
            storedPopoverHeight = clampedHeight
            persist(clampedHeight, forKey: Keys.popoverHeight)
        }
    }

    @Published private(set) var loginItemMessage: String?

    private let defaults: UserDefaults
    private let persistence: SettingsPersistence?
    private var storedPopoverHeight = Double(PopoverLayout.defaultHeight)
    private var popoverMaximumHeight = Double(PopoverLayout.maximumHeight)

    convenience init() {
        self.init(defaults: .standard, persistenceURL: SettingsPersistence.defaultURL)
    }

    init(defaults: UserDefaults, persistenceURL: URL? = nil) {
        let persistence = persistenceURL.map(SettingsPersistence.init)
        persistence?.restore(defaults: defaults, keys: Keys.all)
        self.defaults = defaults
        self.persistence = persistence
        language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .english
        let savedInterval = defaults.double(forKey: Keys.refreshInterval)
        refreshInterval = savedInterval >= 30 ? savedInterval : 60
        let savedHistoryInterval = defaults.double(forKey: Keys.quotaCapacityHistoryInterval)
        quotaCapacityHistoryInterval = Self.clampedQuotaCapacityHistoryInterval(savedHistoryInterval > 0 ? savedHistoryInterval : 3_600)
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        if !defaults.bool(forKey: Keys.didMigrateActiveAccountMenuBarDefault) {
            defaults.set(MenuBarDisplayMode.activeAccountWindows.rawValue, forKey: Keys.menuBarDisplayMode)
            defaults.set(true, forKey: Keys.didMigrateActiveAccountMenuBarDefault)
        }
        menuBarDisplayMode = MenuBarDisplayMode(rawValue: defaults.string(forKey: Keys.menuBarDisplayMode) ?? "") ?? .activeAccountWindows
        showCodexInMenuBar = defaults.object(forKey: Keys.showCodexInMenuBar) as? Bool ?? true
        showCodexSidebarQuotaOverlay = defaults.object(forKey: Keys.showCodexSidebarQuotaOverlay) as? Bool ?? false
        codexSidebarQuotaOverlayIndependent = defaults.object(forKey: Keys.codexSidebarQuotaOverlayIndependent) as? Bool ?? false
        quotaWidgetHotKey = defaults.data(forKey: Keys.quotaWidgetHotKey)
            .flatMap { try? JSONDecoder().decode(QuotaWidgetHotKey.self, from: $0) }
        didCompleteQuotaWidgetOnboarding = defaults.bool(forKey: Keys.didCompleteQuotaWidgetOnboarding)
        showClaudeInMenuBar = defaults.object(forKey: Keys.showClaudeInMenuBar) as? Bool ?? true
        useDarkAppearance = defaults.object(forKey: Keys.useDarkAppearance) as? Bool ?? false
        useTranslucentAppearance = defaults.object(forKey: Keys.useTranslucentAppearance) as? Bool ?? true
        accountSortMode = AccountSortMode(rawValue: defaults.string(forKey: Keys.accountSortMode) ?? "") ?? .quotaPressure
        showAggregatedAccountData = defaults.object(forKey: Keys.showAggregatedAccountData) as? Bool ?? false
        autoCodexAccountRotationEnabled = defaults.object(forKey: Keys.autoCodexAccountRotationEnabled) as? Bool ?? false
        quotaResetNotificationsEnabled = defaults.object(forKey: Keys.quotaResetNotificationsEnabled) as? Bool ?? false
        taskCompletionNotificationsEnabled = defaults.object(forKey: Keys.taskCompletionNotificationsEnabled) as? Bool ?? false
        accessTokenExpiryNotificationsEnabled = defaults.object(forKey: Keys.accessTokenExpiryNotificationsEnabled) as? Bool ?? false
        projectBudgets = defaults.data(forKey: Keys.projectBudgets)
            .flatMap { try? JSONDecoder().decode([ProjectBudget].self, from: $0) }
            ?? []
        let savedRotationThreshold = defaults.double(forKey: Keys.codexRotationThresholdRemainingPercent)
        codexRotationThresholdRemainingPercent = Self.clampedRotationThreshold(savedRotationThreshold > 0 ? savedRotationThreshold : 10)
        dailyTokenBudget = Self.clampedBudgetCount(defaults.integer(forKey: Keys.dailyTokenBudget))
        weeklyTokenBudget = Self.clampedBudgetCount(defaults.integer(forKey: Keys.weeklyTokenBudget))
        dailyCostBudgetUSD = Self.clampedBudgetCost(defaults.double(forKey: Keys.dailyCostBudgetUSD))
        weeklyCostBudgetUSD = Self.clampedBudgetCost(defaults.double(forKey: Keys.weeklyCostBudgetUSD))
        let savedPopoverHeight = defaults.double(forKey: Keys.popoverHeight)
        storedPopoverHeight = Self.clampedPopoverHeight(
            savedPopoverHeight > 0 ? savedPopoverHeight : Double(PopoverLayout.defaultHeight),
            maximumHeight: popoverMaximumHeight
        )
        persist(popoverHeight, forKey: Keys.popoverHeight)
    }

    func updatePopoverMaximumHeight(_ maximumHeight: Double) {
        let nextMaximumHeight = max(Double(PopoverLayout.minimumHeight), maximumHeight)
        popoverMaximumHeight = nextMaximumHeight
        popoverHeight = storedPopoverHeight
    }

    static func clampedPopoverHeight(
        _ height: Double,
        maximumHeight: Double = Double(PopoverLayout.maximumHeight)
    ) -> Double {
        min(maximumHeight, max(Double(PopoverLayout.minimumHeight), height))
    }

    static func clampedRotationThreshold(_ threshold: Double) -> Double {
        min(100, max(1, threshold))
    }

    static func clampedBudgetCount(_ value: Int) -> Int {
        max(0, value)
    }

    static func clampedBudgetCost(_ value: Double) -> Double {
        max(0, value)
    }

    static func clampedQuotaCapacityHistoryInterval(_ value: TimeInterval) -> TimeInterval {
        max(300, value)
    }

    func projectBudget(for id: String) -> ProjectBudget {
        projectBudgets.first(where: { $0.id == id }) ?? ProjectBudget(id: id)
    }

    func updateProjectBudget(_ budget: ProjectBudget) {
        let budget = ProjectBudget(
            id: budget.id,
            dailyTokenLimit: Self.clampedBudgetCount(budget.dailyTokenLimit),
            weeklyTokenLimit: Self.clampedBudgetCount(budget.weeklyTokenLimit),
            dailyCostLimitUSD: Self.clampedBudgetCost(budget.dailyCostLimitUSD),
            weeklyCostLimitUSD: Self.clampedBudgetCost(budget.weeklyCostLimitUSD)
        )
        if let index = projectBudgets.firstIndex(where: { $0.id == budget.id }) {
            if budget.isConfigured {
                projectBudgets[index] = budget
            } else {
                projectBudgets.remove(at: index)
            }
        } else if budget.isConfigured {
            projectBudgets.append(budget)
        }
    }

    private func persist(_ value: Any?, forKey key: String) {
        defaults.set(value, forKey: key)
        persistence?.save(defaults: defaults, keys: Keys.all)
    }

    private func applyLoginItemPreference() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
                loginItemMessage = "Login item registered."
            } else {
                try SMAppService.mainApp.unregister()
                loginItemMessage = "Login item unregistered."
            }
        } catch {
            loginItemMessage = error.localizedDescription
        }
    }

    private enum Keys {
        static let language = "language"
        static let refreshInterval = "refreshInterval"
        static let quotaCapacityHistoryInterval = "quotaCapacityHistoryInterval"
        static let launchAtLogin = "launchAtLogin"
        static let menuBarDisplayMode = "menuBarDisplayMode"
        static let showCodexInMenuBar = "showCodexInMenuBar"
        static let showCodexSidebarQuotaOverlay = "showCodexSidebarQuotaOverlay"
        static let codexSidebarQuotaOverlayIndependent = "codexSidebarQuotaOverlayIndependent"
        static let quotaWidgetHotKey = "quotaWidgetHotKey"
        static let didCompleteQuotaWidgetOnboarding = "didCompleteQuotaWidgetOnboarding"
        static let showClaudeInMenuBar = "showClaudeInMenuBar"
        static let didMigrateActiveAccountMenuBarDefault = "didMigrateActiveAccountMenuBarDefault"
        static let useDarkAppearance = "useDarkAppearance"
        static let useTranslucentAppearance = "useTranslucentAppearance"
        static let accountSortMode = "accountSortMode"
        static let showAggregatedAccountData = "showAggregatedAccountData"
        static let autoCodexAccountRotationEnabled = "autoCodexAccountRotationEnabled"
        static let quotaResetNotificationsEnabled = "quotaResetNotificationsEnabled"
        static let taskCompletionNotificationsEnabled = "taskCompletionNotificationsEnabled"
        static let accessTokenExpiryNotificationsEnabled = "accessTokenExpiryNotificationsEnabled"
        static let projectBudgets = "projectBudgets"
        static let codexRotationThresholdRemainingPercent = "codexRotationThresholdRemainingPercent"
        static let dailyTokenBudget = "dailyTokenBudget"
        static let weeklyTokenBudget = "weeklyTokenBudget"
        static let dailyCostBudgetUSD = "dailyCostBudgetUSD"
        static let weeklyCostBudgetUSD = "weeklyCostBudgetUSD"
        static let popoverHeight = "popoverHeight"

        static let all = [
            language,
            refreshInterval,
            quotaCapacityHistoryInterval,
            launchAtLogin,
            menuBarDisplayMode,
            showCodexInMenuBar,
            showCodexSidebarQuotaOverlay,
            codexSidebarQuotaOverlayIndependent,
            quotaWidgetHotKey,
            didCompleteQuotaWidgetOnboarding,
            showClaudeInMenuBar,
            didMigrateActiveAccountMenuBarDefault,
            useDarkAppearance,
            useTranslucentAppearance,
            accountSortMode,
            showAggregatedAccountData,
            autoCodexAccountRotationEnabled,
            quotaResetNotificationsEnabled,
            taskCompletionNotificationsEnabled,
            accessTokenExpiryNotificationsEnabled,
            projectBudgets,
            codexRotationThresholdRemainingPercent,
            dailyTokenBudget,
            weeklyTokenBudget,
            dailyCostBudgetUSD,
            weeklyCostBudgetUSD,
            popoverHeight
        ]
    }
}

private struct SettingsPersistence {
    static let defaultURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "AgentBar/Settings.plist")

    let url: URL

    func restore(defaults: UserDefaults, keys: [String]) {
        guard let data = try? Data(contentsOf: url),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return }

        for key in keys where defaults.object(forKey: key) == nil {
            defaults.set(values[key], forKey: key)
        }
    }

    func save(defaults: UserDefaults, keys: [String]) {
        let values = keys.reduce(into: [String: Any]()) { values, key in
            values[key] = defaults.object(forKey: key)
        }
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: values,
            format: .binary,
            options: 0
        ) else { return }

        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }
}
