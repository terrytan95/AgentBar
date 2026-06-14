import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject private var settings: SettingsStore

    init(store: UsageStore) {
        self.store = store
        self.settings = store.settings
    }

    private var popoverMaximumHeight: Double {
        Double(PopoverLayout.maximumHeight(forScreenHeight: NSScreen.main?.visibleFrame.height))
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
                    Text("30s").tag(TimeInterval(30))
                    Text("60s").tag(TimeInterval(60))
                    Text("5m").tag(TimeInterval(300))
                    Text("10m").tag(TimeInterval(600))
                }
                Toggle(L.text("login_item", store.language), isOn: $settings.launchAtLogin)
                if let message = settings.loginItemMessage {
                    Text(message.redactedForCredentialWords)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle(L.text("dark_theme", store.language), isOn: $settings.useDarkAppearance)
                Picker(L.text("tone_color", store.language), selection: $settings.themeColor) {
                    ForEach(AppThemeColor.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
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
                Picker(L.text("account_sort", store.language), selection: $settings.accountSortMode) {
                    ForEach(AccountSortMode.allCases) { mode in
                        Text(mode.title(store.language)).tag(mode)
                    }
                }
                Slider(
                    value: $settings.popoverHeight,
                    in: Double(PopoverLayout.minimumHeight)...popoverMaximumHeight,
                    step: 20
                ) {
                    Text(L.text("popover_height", store.language))
                } minimumValueLabel: {
                    Text("\(Int(PopoverLayout.minimumHeight))")
                } maximumValueLabel: {
                    Text("\(Int(popoverMaximumHeight))")
                }
                Toggle("Codex", isOn: $settings.showCodexInMenuBar)
                Toggle("Claude Code", isOn: $settings.showClaudeInMenuBar)
                Button(L.text("login_codex", store.language)) {
                    store.openLogin(for: .codex)
                }
                Button(L.text("login_claude", store.language)) {
                    store.openLogin(for: .claudeCode)
                }
            }
            .padding(18)
            .tabItem { Label(L.text("menu_item", store.language), systemImage: "menubar.rectangle") }
        }
        .onChange(of: settings.refreshInterval) {
            store.configureTimer()
        }
        .onAppear {
            settings.updatePopoverMaximumHeight(popoverMaximumHeight)
        }
        .frame(width: 520, height: 350)
    }
}
