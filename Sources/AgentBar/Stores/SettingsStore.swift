import Foundation
import ServiceManagement

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case activeAccountWindows
    case lowestRemaining
    case totalTokens
    case codexRemaining

    var id: String { rawValue }
}

enum AppThemeColor: String, CaseIterable, Identifiable {
    case blue
    case green
    case purple
    case orange
    case graphite

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
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    @Published var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval) }
    }

    @Published var quotaCapacityHistoryInterval: TimeInterval {
        didSet {
            let clamped = Self.clampedQuotaCapacityHistoryInterval(quotaCapacityHistoryInterval)
            if clamped != quotaCapacityHistoryInterval {
                quotaCapacityHistoryInterval = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.quotaCapacityHistoryInterval)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLoginItemPreference()
        }
    }

    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet { defaults.set(menuBarDisplayMode.rawValue, forKey: Keys.menuBarDisplayMode) }
    }

    @Published var showCodexInMenuBar: Bool {
        didSet { defaults.set(showCodexInMenuBar, forKey: Keys.showCodexInMenuBar) }
    }

    @Published var showClaudeInMenuBar: Bool {
        didSet { defaults.set(showClaudeInMenuBar, forKey: Keys.showClaudeInMenuBar) }
    }

    @Published var themeColor: AppThemeColor {
        didSet { defaults.set(themeColor.rawValue, forKey: Keys.themeColor) }
    }

    @Published var useDarkAppearance: Bool {
        didSet { defaults.set(useDarkAppearance, forKey: Keys.useDarkAppearance) }
    }

    @Published var accountSortMode: AccountSortMode {
        didSet { defaults.set(accountSortMode.rawValue, forKey: Keys.accountSortMode) }
    }

    @Published var showAggregatedAccountData: Bool {
        didSet { defaults.set(showAggregatedAccountData, forKey: Keys.showAggregatedAccountData) }
    }

    @Published var autoCodexAccountRotationEnabled: Bool {
        didSet { defaults.set(autoCodexAccountRotationEnabled, forKey: Keys.autoCodexAccountRotationEnabled) }
    }

    @Published var detailedResetCreditsEnabled: Bool {
        didSet { defaults.set(detailedResetCreditsEnabled, forKey: Keys.detailedResetCreditsEnabled) }
    }

    @Published var quotaResetNotificationsEnabled: Bool {
        didSet { defaults.set(quotaResetNotificationsEnabled, forKey: Keys.quotaResetNotificationsEnabled) }
    }

    @Published var codexRotationThresholdRemainingPercent: Double {
        didSet {
            let clamped = Self.clampedRotationThreshold(codexRotationThresholdRemainingPercent)
            if clamped != codexRotationThresholdRemainingPercent {
                codexRotationThresholdRemainingPercent = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.codexRotationThresholdRemainingPercent)
        }
    }

    @Published var dailyTokenBudget: Int {
        didSet {
            let clamped = Self.clampedBudgetCount(dailyTokenBudget)
            if clamped != dailyTokenBudget {
                dailyTokenBudget = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.dailyTokenBudget)
        }
    }

    @Published var weeklyTokenBudget: Int {
        didSet {
            let clamped = Self.clampedBudgetCount(weeklyTokenBudget)
            if clamped != weeklyTokenBudget {
                weeklyTokenBudget = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.weeklyTokenBudget)
        }
    }

    @Published var dailyCostBudgetUSD: Double {
        didSet {
            let clamped = Self.clampedBudgetCost(dailyCostBudgetUSD)
            if clamped != dailyCostBudgetUSD {
                dailyCostBudgetUSD = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.dailyCostBudgetUSD)
        }
    }

    @Published var weeklyCostBudgetUSD: Double {
        didSet {
            let clamped = Self.clampedBudgetCost(weeklyCostBudgetUSD)
            if clamped != weeklyCostBudgetUSD {
                weeklyCostBudgetUSD = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.weeklyCostBudgetUSD)
        }
    }

    var popoverHeight: Double {
        get { storedPopoverHeight }
        set {
            let clampedHeight = Self.clampedPopoverHeight(newValue, maximumHeight: popoverMaximumHeight)
            guard storedPopoverHeight != clampedHeight else {
                defaults.set(clampedHeight, forKey: Keys.popoverHeight)
                return
            }
            objectWillChange.send()
            storedPopoverHeight = clampedHeight
            defaults.set(clampedHeight, forKey: Keys.popoverHeight)
        }
    }

    @Published private(set) var loginItemMessage: String?

    private let defaults: UserDefaults
    private var storedPopoverHeight = Double(PopoverLayout.defaultHeight)
    private var popoverMaximumHeight = Double(PopoverLayout.maximumHeight)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        showClaudeInMenuBar = defaults.object(forKey: Keys.showClaudeInMenuBar) as? Bool ?? true
        themeColor = AppThemeColor(rawValue: defaults.string(forKey: Keys.themeColor) ?? "") ?? .blue
        useDarkAppearance = defaults.object(forKey: Keys.useDarkAppearance) as? Bool ?? false
        accountSortMode = AccountSortMode(rawValue: defaults.string(forKey: Keys.accountSortMode) ?? "") ?? .quotaPressure
        showAggregatedAccountData = defaults.object(forKey: Keys.showAggregatedAccountData) as? Bool ?? false
        autoCodexAccountRotationEnabled = defaults.object(forKey: Keys.autoCodexAccountRotationEnabled) as? Bool ?? false
        detailedResetCreditsEnabled = defaults.object(forKey: Keys.detailedResetCreditsEnabled) as? Bool ?? false
        quotaResetNotificationsEnabled = defaults.object(forKey: Keys.quotaResetNotificationsEnabled) as? Bool ?? false
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
        defaults.set(popoverHeight, forKey: Keys.popoverHeight)
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
        static let showClaudeInMenuBar = "showClaudeInMenuBar"
        static let didMigrateActiveAccountMenuBarDefault = "didMigrateActiveAccountMenuBarDefault"
        static let themeColor = "themeColor"
        static let useDarkAppearance = "useDarkAppearance"
        static let accountSortMode = "accountSortMode"
        static let showAggregatedAccountData = "showAggregatedAccountData"
        static let autoCodexAccountRotationEnabled = "autoCodexAccountRotationEnabled"
        static let detailedResetCreditsEnabled = "detailedResetCreditsEnabled"
        static let quotaResetNotificationsEnabled = "quotaResetNotificationsEnabled"
        static let codexRotationThresholdRemainingPercent = "codexRotationThresholdRemainingPercent"
        static let dailyTokenBudget = "dailyTokenBudget"
        static let weeklyTokenBudget = "weeklyTokenBudget"
        static let dailyCostBudgetUSD = "dailyCostBudgetUSD"
        static let weeklyCostBudgetUSD = "weeklyCostBudgetUSD"
        static let popoverHeight = "popoverHeight"
    }
}
