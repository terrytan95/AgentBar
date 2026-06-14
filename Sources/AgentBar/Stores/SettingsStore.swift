import Foundation
import ServiceManagement

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case lowestRemaining
    case totalTokens
    case codexRemaining

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

    @Published private(set) var loginItemMessage: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .english
        let savedInterval = defaults.double(forKey: Keys.refreshInterval)
        refreshInterval = savedInterval > 0 ? savedInterval : 60
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        menuBarDisplayMode = MenuBarDisplayMode(rawValue: defaults.string(forKey: Keys.menuBarDisplayMode) ?? "") ?? .lowestRemaining
        showCodexInMenuBar = defaults.object(forKey: Keys.showCodexInMenuBar) as? Bool ?? true
        showClaudeInMenuBar = defaults.object(forKey: Keys.showClaudeInMenuBar) as? Bool ?? true
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
    }
}
