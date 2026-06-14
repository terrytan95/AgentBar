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
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    @Published var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval) }
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
        static let launchAtLogin = "launchAtLogin"
        static let menuBarDisplayMode = "menuBarDisplayMode"
        static let showCodexInMenuBar = "showCodexInMenuBar"
        static let showClaudeInMenuBar = "showClaudeInMenuBar"
        static let didMigrateActiveAccountMenuBarDefault = "didMigrateActiveAccountMenuBarDefault"
        static let themeColor = "themeColor"
        static let useDarkAppearance = "useDarkAppearance"
        static let accountSortMode = "accountSortMode"
        static let popoverHeight = "popoverHeight"
    }
}
