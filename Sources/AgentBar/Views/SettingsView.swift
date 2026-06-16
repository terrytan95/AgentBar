import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var updates: AppUpdateStore

    init(store: UsageStore, updates: AppUpdateStore = .shared) {
        self.store = store
        self.settings = store.settings
        self.updates = updates
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
                Section(L.text("software_update", store.language)) {
                    HStack {
                        Text(L.text("current_version", store.language))
                        Spacer()
                        Text(updates.currentVersion)
                            .foregroundStyle(.secondary)
                    }
                    if updates.showsCheckForUpdatesControl {
                        HStack {
                            Button(L.text("check_for_updates", store.language)) {
                                Task { await updates.checkForUpdates() }
                            }
                            .disabled(!updates.canCheckForUpdates)
                            if updates.status.isBusy {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    Text(updates.status.localizedMessage(language: store.language))
                        .font(.caption)
                        .foregroundStyle(updateStatusColor)
                    if updates.canInstallDownloadedUpdate {
                        Button(L.text("install_and_restart", store.language)) {
                            updates.installDownloadedUpdate()
                        }
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
                Toggle(L.text("auto_codex_rotation", store.language), isOn: $settings.autoCodexAccountRotationEnabled)
                HStack {
                    Text(L.text("codex_rotation_threshold", store.language))
                    Spacer()
                    CodexRotationThresholdControl(
                        threshold: $settings.codexRotationThresholdRemainingPercent,
                        isEnabled: settings.autoCodexAccountRotationEnabled,
                        language: store.language
                    )
                }
                .disabled(!settings.autoCodexAccountRotationEnabled)
                Toggle("Codex", isOn: $settings.showCodexInMenuBar)
                Toggle("Claude Code", isOn: $settings.showClaudeInMenuBar)
                Section(budgetLocalized("budgets")) {
                    HStack {
                        Text(budgetLocalized("daily_token_budget"))
                        Spacer()
                        SettingsBudgetIntegerField(value: $settings.dailyTokenBudget, language: store.language)
                    }
                    HStack {
                        Text(budgetLocalized("weekly_token_budget"))
                        Spacer()
                        SettingsBudgetIntegerField(value: $settings.weeklyTokenBudget, language: store.language)
                    }
                    HStack {
                        Text(budgetLocalized("daily_cost_budget"))
                        Spacer()
                        SettingsBudgetCostField(value: $settings.dailyCostBudgetUSD)
                    }
                    HStack {
                        Text(budgetLocalized("weekly_cost_budget"))
                        Spacer()
                        SettingsBudgetCostField(value: $settings.weeklyCostBudgetUSD)
                    }
                }
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
        .frame(width: 540, height: 470)
    }

    private var updateStatusColor: Color {
        if updates.status.isFailure {
            return .red
        }
        return .secondary
    }

    private func budgetLocalized(_ key: String) -> String {
        switch (key, store.language) {
        case ("budgets", .chinese): "预算"
        case ("daily_token_budget", .chinese): "每日 Token 预算"
        case ("weekly_token_budget", .chinese): "每周 Token 预算"
        case ("daily_cost_budget", .chinese): "每日费用预算"
        case ("weekly_cost_budget", .chinese): "每周费用预算"
        case ("budgets", _): "Budgets"
        case ("daily_token_budget", _): "Daily token budget"
        case ("weekly_token_budget", _): "Weekly token budget"
        case ("daily_cost_budget", _): "Daily cost budget"
        case ("weekly_cost_budget", _): "Weekly cost budget"
        default: key
        }
    }
}

struct CodexRotationThresholdControl: View {
    @Binding var threshold: Double
    var isEnabled: Bool
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 6) {
            TextField(
                L.text("codex_rotation_threshold", language),
                value: $threshold,
                format: .number.precision(.fractionLength(0))
            )
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 58)

            Text("%")
                .foregroundStyle(.secondary)

            Stepper(
                "",
                value: $threshold,
                in: 1...100,
                step: 1
            )
            .labelsHidden()
        }
        .disabled(!isEnabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L.text("codex_rotation_threshold", language))
    }
}

private struct SettingsBudgetIntegerField: View {
    @Binding var value: Int
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 6) {
            TextField("0", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(L.text("tokens", language))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsBudgetCostField: View {
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 6) {
            Text("$")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("0", value: $value, format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 86)
        }
    }
}
