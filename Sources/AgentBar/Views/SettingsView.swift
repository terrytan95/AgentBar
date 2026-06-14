import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject private var settings: SettingsStore

    init(store: UsageStore) {
        self.store = store
        self.settings = store.settings
    }

    var body: some View {
        TabView {
            Form {
                Picker(L.text("language", store.language), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                Picker(L.text("refresh_interval", store.language), selection: $settings.refreshInterval) {
                    Text("15s").tag(TimeInterval(15))
                    Text("30s").tag(TimeInterval(30))
                    Text("60s").tag(TimeInterval(60))
                    Text("5m").tag(TimeInterval(300))
                }
                Toggle(L.text("login_item", store.language), isOn: $settings.launchAtLogin)
                if let message = settings.loginItemMessage {
                    Text(message.redactedForCredentialWords)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .tabItem { Label(L.text("settings", store.language), systemImage: "gearshape") }

            Form {
                Picker(L.text("menu_item", store.language), selection: $settings.menuBarDisplayMode) {
                    Text(L.text("active_account_windows", store.language)).tag(MenuBarDisplayMode.activeAccountWindows)
                    Text(L.text("lowest_remaining", store.language)).tag(MenuBarDisplayMode.lowestRemaining)
                    Text(L.text("total_tokens", store.language)).tag(MenuBarDisplayMode.totalTokens)
                    Text(L.text("codex_only", store.language)).tag(MenuBarDisplayMode.codexRemaining)
                }
                Toggle("Codex", isOn: $settings.showCodexInMenuBar)
                Toggle("Claude Code", isOn: $settings.showClaudeInMenuBar)
            }
            .padding(18)
            .tabItem { Label(L.text("menu_item", store.language), systemImage: "menubar.rectangle") }
        }
        .onChange(of: settings.refreshInterval) {
            store.configureTimer()
        }
        .frame(width: 520, height: 320)
    }
}
