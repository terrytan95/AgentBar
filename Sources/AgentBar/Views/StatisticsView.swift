import AppKit
import SwiftUI

struct StatisticsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var updates: AppUpdateStore
    @State private var viewMode: DashboardViewMode = .overview
    @State private var topTab: DashboardTopTab

    private static let dashboardContentTopPadding: CGFloat = 12
    private static let dashboardContentBottomPadding: CGFloat = 26

    init(
        store: UsageStore,
        initialTab: DashboardTopTab = .usage,
        updates: AppUpdateStore = .shared
    ) {
        self.store = store
        self.settings = store.settings
        self.updates = updates
        _topTab = State(initialValue: initialTab)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 216)

            VStack(spacing: 0) {
                if topTab == .usage {
                    usageContent
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        settingsContent
                            .padding(.top, 12)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 28)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .tint(settings.themeColor.primary)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: DashboardNavigation.tabRequestNotification)) { notification in
            guard let rawValue = notification.userInfo?["tab"] as? String,
                  let tab = DashboardTopTab(rawValue: rawValue)
            else { return }
            setTopTab(tab)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            sidebarGroup(title: L.text("usage_statistics", store.language)) {
                sidebarItem(L.text("overview", store.language), systemImage: "rectangle.split.2x2", active: topTab == .usage && viewMode == .overview) {
                    topTab = .usage
                    viewMode = .overview
                }
                sidebarItem("Audit", systemImage: "chart.bar.doc.horizontal", active: topTab == .usage && viewMode == .audit) {
                    topTab = .usage
                    viewMode = .audit
                }
            }

            sidebarGroup(title: L.text("settings", store.language)) {
                sidebarItem(L.text("settings", store.language), systemImage: "gearshape", active: topTab == .settings) {
                    topTab = .settings
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 42)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassPanel(cornerRadius: 0, interactive: false)
    }

    private func setTopTab(_ tab: DashboardTopTab) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            topTab = tab
        }
    }

    private func sidebarGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            content()
        }
    }

    private func sidebarItem(
        _ title: String,
        systemImage: String? = nil,
        active: Bool,
        service: UsageService? = nil,
        tint: Color? = nil,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 14)
                } else if service == .codex {
                    OpenAILogoMark(size: 12)
                        .frame(width: 14)
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint ?? Color.secondary)
                        .frame(width: 8, height: 8)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(active ? .white : (enabled ? Color.primary.opacity(0.86) : Color.secondary.opacity(0.72)))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(active ? settings.themeColor.primary : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.86)
        .tactilePlainButton(enabled: enabled)
        .glassPanel(cornerRadius: 8, interactive: enabled)
    }

    private var usageContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                switch viewMode {
                case .overview:
                    dashboardContent
                case .audit:
                    AuditView(
                        store: store,
                        points: filteredPoints,
                        dataSourceHealth: dataSourceHealth,
                        theme: settings.themeColor
                    )
                }
            }
            .padding(.top, Self.dashboardContentTopPadding)
            .padding(.horizontal, 22)
            .padding(.bottom, Self.dashboardContentBottomPadding)
        }
    }

    private var dashboardRefreshButton: some View {
        Button {
            store.refresh(force: true, showManualFeedback: true)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                Text(L.text("refresh", store.language))
                    .font(.system(size: 12, weight: .semibold))
                if store.isManualRefreshFeedbackVisible {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(settings.themeColor.primary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(L.text("refresh", store.language)))
        }
        .tactilePlainButton()
        .glassPanel(cornerRadius: 10, interactive: true)
        .help(L.text("refresh", store.language))
    }

    @ViewBuilder
    private var dashboardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            dashboardOverviewHeader

            if !store.hasLoadedAccountInformation {
                LoadingAccountPanel(
                    title: L.text("loading_account_info", store.language),
                    subtitle: L.text("loading_account_info_subtitle", store.language)
                )
            }

            GeometryReader { proxy in
                LazyVGrid(columns: kpiColumns(for: proxy.size.width), spacing: 12) {
                    DashboardKPI(title: L.text("total_tokens", store.language), value: DisplayFormatters.compactTokenString(summary.totalTokens, language: store.language), delta: DisplayFormatters.changePercentString(periodChange.tokenPercent), accent: .primary, theme: settings.themeColor)
                    DashboardKPI(title: L.text("total_cost", store.language), value: costText(summary.estimatedCostUSD), delta: DisplayFormatters.changePercentString(periodChange.costPercent), accent: .primary, theme: settings.themeColor)
                    DashboardKPI(title: "OpenAI", value: serviceCostText(.codex), delta: serviceShareText(.codex), marker: settings.themeColor.tertiary, accent: settings.themeColor.tertiary, theme: settings.themeColor)
                    if hasClaudeData {
                        DashboardKPI(title: "Anthropic", value: serviceCostText(.claudeCode), delta: serviceShareText(.claudeCode), marker: settings.themeColor.secondary, accent: settings.themeColor.secondary, theme: settings.themeColor)
                    }
                }
            }
            .frame(height: hasClaudeData ? 152 : 70)

            QuotaPressurePanel(pressure: quotaPressure, language: store.language, theme: settings.themeColor)

            Panel(title: "\(L.text("daily_usage_for", store.language)) · \(store.selectedRange.dashboardLabel(store.language))") {
                DashboardStackedBars(bars: displayBars, language: store.language, theme: settings.themeColor)
                    .frame(height: 206)
                HStack(spacing: 14) {
                    Spacer()
                    LegendItem(title: "Codex", color: settings.themeColor.tertiary)
                    if hasClaudeData {
                        LegendItem(title: "Claude", color: settings.themeColor.secondary)
                    }
                }
            }

            if !usageAnomalies.isEmpty {
                UsageAnomalyPanel(anomalies: usageAnomalies, language: store.language, theme: settings.themeColor)
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 14) {
                    Panel(title: L.text("by_service", store.language)) {
                        serviceMixRows
                    }
                    Panel(title: L.text("by_model", store.language)) {
                        modelRows
                    }
                    if hasConfiguredBudgets {
                        Panel(title: budgetLocalized("budgets")) {
                            BudgetStatusPanel(
                                today: store.budgetStatus(for: .today),
                                weekly: store.budgetStatus(for: .thisWeek),
                                language: store.language,
                                theme: settings.themeColor
                            )
                        }
                    }
                    Panel(title: dataSourceLocalized("data_source_health")) {
                        DataSourceHealthPanel(health: dataSourceHealth, language: store.language, theme: settings.themeColor)
                    }
                }
                .frame(minWidth: 360, maxWidth: .infinity, alignment: .top)

                Panel(title: L.text("current_limits", store.language)) {
                    currentLimitsRows
                }
                .frame(minWidth: 360, maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var dashboardOverviewHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L.text("overview", store.language))
                    .font(.system(size: 20, weight: .bold))
                Text("\(L.text("daily_usage_for", store.language)) · \(store.selectedRange.dashboardLabel(store.language))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Text(L.text("interval", store.language))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Picker("", selection: $store.selectedRange) {
                    ForEach(UsageRange.allCases) { range in
                        Text(range.dashboardLabel(store.language)).tag(range)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .glassPanel(cornerRadius: 12, interactive: true)

            dashboardRefreshButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(title: L.text("accounts", store.language), subtitle: L.text("accounts_settings_subtitle", store.language)) {
                SettingsRow(title: "Codex", subtitle: "\(codexAccounts.count) \(L.text("accounts_loaded", store.language))") {
                    Toggle("", isOn: $settings.showCodexInMenuBar).labelsHidden()
                }
                SettingsRow(title: "Claude Code", subtitle: hasClaudeData ? L.text("available", store.language) : L.text("no_safe_local_source", store.language)) {
                    Toggle("", isOn: $settings.showClaudeInMenuBar).labelsHidden()
                }
                SettingsRow(title: L.text("login_accounts", store.language), subtitle: L.text("login_accounts_subtitle", store.language)) {
                    HStack {
                        Button(L.text("login_codex", store.language)) {
                            store.openLogin(for: .codex)
                        }
                        .pointingHandCursor()
                        Button(L.text("login_claude", store.language)) {
                            store.openLogin(for: .claudeCode)
                        }
                        .pointingHandCursor()
                    }
                }
                SettingsRow(title: L.text("account_sort", store.language), subtitle: L.text("account_sort_subtitle", store.language)) {
                    Picker("", selection: $settings.accountSortMode) {
                        ForEach(AccountSortMode.allCases) { mode in
                            Text(mode.title(store.language)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .settingsControl(width: SettingsControlLayout.widePickerWidth)
                }
                SettingsRow(title: L.text("auto_codex_rotation", store.language), subtitle: L.text("auto_codex_rotation_subtitle", store.language)) {
                    Toggle("", isOn: $settings.autoCodexAccountRotationEnabled).labelsHidden()
                }
                SettingsRow(title: L.text("codex_rotation_threshold", store.language), subtitle: L.text("codex_rotation_threshold_subtitle", store.language)) {
                    CodexRotationThresholdControl(
                        threshold: $settings.codexRotationThresholdRemainingPercent,
                        isEnabled: settings.autoCodexAccountRotationEnabled,
                        language: store.language
                    )
                    .settingsControl(width: SettingsControlLayout.widePickerWidth)
                }
            }

            SettingsGroup(title: L.text("menu_bar", store.language), subtitle: L.text("menu_bar_settings_subtitle", store.language)) {
                SettingsRow(title: L.text("display_value", store.language), subtitle: L.text("display_value_subtitle", store.language)) {
                    Picker("", selection: $settings.menuBarDisplayMode) {
                        Text(L.text("active_account_windows", store.language)).tag(MenuBarDisplayMode.activeAccountWindows)
                        Text(L.text("lowest_remaining", store.language)).tag(MenuBarDisplayMode.lowestRemaining)
                        Text(L.text("total_tokens", store.language)).tag(MenuBarDisplayMode.totalTokens)
                        Text(L.text("codex_only", store.language)).tag(MenuBarDisplayMode.codexRemaining)
                    }
                    .labelsHidden()
                    .settingsControl(width: SettingsControlLayout.widePickerWidth)
                }
            }

            SettingsGroup(title: budgetLocalized("budgets"), subtitle: budgetLocalized("budget_subtitle")) {
                SettingsRow(title: budgetLocalized("daily_token_budget"), subtitle: budgetLocalized("daily_token_budget_subtitle")) {
                    BudgetIntegerField(value: $settings.dailyTokenBudget, language: store.language)
                        .settingsControl(width: SettingsControlLayout.mediumPickerWidth)
                }
                SettingsRow(title: budgetLocalized("weekly_token_budget"), subtitle: budgetLocalized("weekly_token_budget_subtitle")) {
                    BudgetIntegerField(value: $settings.weeklyTokenBudget, language: store.language)
                        .settingsControl(width: SettingsControlLayout.mediumPickerWidth)
                }
                SettingsRow(title: budgetLocalized("daily_cost_budget"), subtitle: budgetLocalized("daily_cost_budget_subtitle")) {
                    BudgetCostField(value: $settings.dailyCostBudgetUSD, language: store.language)
                        .settingsControl(width: SettingsControlLayout.mediumPickerWidth)
                }
                SettingsRow(title: budgetLocalized("weekly_cost_budget"), subtitle: budgetLocalized("weekly_cost_budget_subtitle")) {
                    BudgetCostField(value: $settings.weeklyCostBudgetUSD, language: store.language)
                        .settingsControl(width: SettingsControlLayout.mediumPickerWidth)
                }
            }

            SettingsGroup(title: L.text("refresh", store.language), subtitle: L.text("refresh_settings_subtitle", store.language)) {
                SettingsRow(title: L.text("refresh_interval", store.language), subtitle: L.text("refresh_interval_subtitle", store.language)) {
                    Picker("", selection: $settings.refreshInterval) {
                        Text("30s").tag(TimeInterval(30))
                        Text("60s").tag(TimeInterval(60))
                        Text("5m").tag(TimeInterval(300))
                        Text("10m").tag(TimeInterval(600))
                    }
                    .labelsHidden()
                    .settingsControl(width: SettingsControlLayout.compactPickerWidth)
                }
                SettingsRow(title: L.text("login_item", store.language), subtitle: settings.loginItemMessage ?? L.text("open_at_login_subtitle", store.language)) {
                    Toggle("", isOn: $settings.launchAtLogin).labelsHidden()
                }
            }

            SettingsGroup(title: L.text("general", store.language), subtitle: L.text("general_settings_subtitle", store.language)) {
                SettingsRow(title: L.text("language", store.language), subtitle: L.text("language_subtitle", store.language)) {
                    Picker("", selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .labelsHidden()
                    .settingsControl(width: SettingsControlLayout.mediumPickerWidth)
                }
                SettingsRow(title: L.text("dark_theme", store.language), subtitle: L.text("dark_theme_subtitle", store.language)) {
                    Toggle("", isOn: $settings.useDarkAppearance)
                        .labelsHidden()
                }
                SettingsRow(title: L.text("tone_color", store.language), subtitle: L.text("tone_color_subtitle", store.language)) {
                    Picker("", selection: $settings.themeColor) {
                        ForEach(AppThemeColor.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .labelsHidden()
                    .settingsControl(width: SettingsControlLayout.mediumPickerWidth)
                }
            }

            SettingsGroup(title: L.text("software_update", store.language), subtitle: L.text("updates_daily_check", store.language)) {
                SettingsRow(title: L.text("current_version", store.language), subtitle: updates.currentVersion) {
                    EmptyView()
                }
                if updates.showsCheckForUpdatesControl {
                    SettingsRow(title: L.text("check_for_updates", store.language), subtitle: updates.status.localizedMessage(language: store.language)) {
                        HStack(spacing: 10) {
                            Button(L.text("check_for_updates", store.language)) {
                                Task { await updates.checkForUpdates() }
                            }
                            .disabled(!updates.canCheckForUpdates)
                            .pointingHandCursor(enabled: updates.canCheckForUpdates)
                            if updates.status.isBusy {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        .settingsControl(width: SettingsControlLayout.widePickerWidth)
                    }
                }
                if updates.canInstallDownloadedUpdate {
                    SettingsRow(title: L.text("install_and_restart", store.language), subtitle: updates.status.localizedMessage(language: store.language)) {
                        Button(L.text("install_and_restart", store.language)) {
                            updates.installDownloadedUpdate()
                        }
                        .pointingHandCursor()
                        .settingsControl(width: SettingsControlLayout.widePickerWidth)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var summary: UsageSummary {
        UsageStatistics.summarize(
            points: filteredPoints,
            range: store.selectedRange,
            customStart: store.customStart,
            customEnd: store.customEnd
        )
    }

    private var periodChange: UsagePeriodChange {
        UsageStatistics.periodChange(
            points: filteredPoints,
            range: store.selectedRange,
            customStart: store.customStart,
            customEnd: store.customEnd
        )
    }

    private var filteredPoints: [UsagePoint] {
        store.points
    }

    private var codexAccounts: [UsageAccount] {
        store.accounts.filter { $0.service == .codex }
    }

    private var claudeAccounts: [UsageAccount] {
        store.accounts.filter { $0.service == .claudeCode }
    }

    private var hasClaudeData: Bool {
        !claudeAccounts.isEmpty || store.points.contains { $0.service == .claudeCode }
    }

    private func kpiColumns(for width: CGFloat) -> [GridItem] {
        let count: Int
        if hasClaudeData {
            count = 2
        } else {
            count = width < 760 ? 2 : 3
        }
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    private var displayBars: [DailyUsageBar] {
        let bars = summary.dailyBars
        guard !bars.isEmpty else { return [] }
        return Array(bars.suffix(24))
    }

    private func serviceCostText(_ service: UsageService) -> String {
        let costs = filteredPoints.filter { $0.service == service }.compactMap(\.estimatedCostUSD)
        guard !costs.isEmpty else { return L.text("no_cost_data", store.language) }
        return DisplayFormatters.costString(costs.reduce(Decimal(0), +))
    }

    private func serviceShareText(_ service: UsageService) -> String {
        let total = max(1, summary.serviceBreakdown.values.reduce(0, +))
        let value = summary.serviceBreakdown[service, default: 0]
        return "\(Int((Double(value) / Double(total) * 100).rounded()))% \(L.text("share", store.language))"
    }

    private func costText(_ value: Decimal?) -> String {
        guard let value else { return L.text("no_cost_data", store.language) }
        return DisplayFormatters.costString(value)
    }

    @ViewBuilder
    private var serviceMixRows: some View {
        let rows = serviceRows
        if rows.isEmpty {
            EmptyPanelMessage(L.text("no_usage_data", store.language))
        } else {
            VStack(spacing: 16) {
                ForEach(rows, id: \.service) { row in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            LegendItem(title: row.title, color: row.color, subtitle: row.subtitle)
                            Spacer()
                            Text(row.cost)
                                .font(.system(size: 13, weight: .bold))
                                .monospacedDigit()
                        }
                        ProgressView(value: row.share)
                            .tint(row.color)
                        HStack {
                            Text(DisplayFormatters.compactTokenString(row.tokens, language: store.language) + " \(L.text("tokens", store.language))")
                            Spacer()
                            Text("\(Int((row.share * 100).rounded()))% \(L.text("share", store.language))")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var serviceRows: [ServiceMixRow] {
        let total = max(1, summary.serviceBreakdown.values.reduce(0, +))
        return UsageService.allCases.compactMap { service in
            let tokens = summary.serviceBreakdown[service, default: 0]
            guard tokens > 0 || (service == .codex && !codexAccounts.isEmpty) || (service == .claudeCode && hasClaudeData) else { return nil }
            let color = service == .codex ? settings.themeColor.tertiary : settings.themeColor.secondary
            return ServiceMixRow(
                service: service,
                title: service == .codex ? "Codex" : "Claude Code",
                subtitle: service == .codex ? "OpenAI" : "Anthropic",
                tokens: tokens,
                share: Double(tokens) / Double(total),
                cost: serviceCostText(service),
                color: color
            )
        }
    }

    @ViewBuilder
    private var currentLimitsRows: some View {
        let accounts = currentLimitAccounts
        if accounts.isEmpty {
            EmptyPanelMessage(L.text("no_quota_windows", store.language))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                CurrentLimitSummaryStrip(
                    summary: currentLimitSummary,
                    resetCreditsCount: totalResetCreditsCount,
                    language: store.language,
                    theme: settings.themeColor
                )

                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(accounts) { account in
                        AccountLimitGroupView(account: account, language: store.language, theme: settings.themeColor)
                    }
                }
            }
        }
    }

    private var currentLimitSummary: CurrentLimitSummary {
        UsageInsights.currentLimitSummary(accounts: currentLimitAccounts)
    }

    private var totalResetCreditsCount: Int {
        store.accounts.reduce(0) { $0 + ($1.resetCredits?.visibleCount ?? 0) }
    }

    private var quotaPressure: QuotaPressureInsight {
        UsageInsights.quotaPressure(
            accounts: store.accounts,
            points: filteredPoints,
            rotationThresholdRemainingPercent: settings.codexRotationThresholdRemainingPercent,
            autoRotationEnabled: settings.autoCodexAccountRotationEnabled
        )
    }

    private var usageAnomalies: [UsageAnomaly] {
        UsageInsights.usageAnomalies(points: filteredPoints)
    }

    private var hasConfiguredBudgets: Bool {
        settings.dailyTokenBudget > 0 ||
            settings.weeklyTokenBudget > 0 ||
            settings.dailyCostBudgetUSD > 0 ||
            settings.weeklyCostBudgetUSD > 0
    }

    private var dataSourceHealth: DataSourceHealthSummary {
        UsageInsights.dataSourceHealth(snapshots: store.snapshots)
    }

    private func budgetLocalized(_ key: String) -> String {
        switch (key, store.language) {
        case ("budgets", .chinese): "预算"
        case ("budget_subtitle", .chinese): "为日/周 Token 和费用设置软阈值，超出时菜单栏提示。"
        case ("daily_token_budget", .chinese): "每日 Token 预算"
        case ("weekly_token_budget", .chinese): "每周 Token 预算"
        case ("daily_cost_budget", .chinese): "每日费用预算"
        case ("weekly_cost_budget", .chinese): "每周费用预算"
        case ("daily_token_budget_subtitle", .chinese): "0 表示关闭每日 Token 提醒。"
        case ("weekly_token_budget_subtitle", .chinese): "0 表示关闭每周 Token 提醒。"
        case ("daily_cost_budget_subtitle", .chinese): "0 表示关闭每日费用提醒。"
        case ("weekly_cost_budget_subtitle", .chinese): "0 表示关闭每周费用提醒。"
        case ("budgets", _): "Budgets"
        case ("budget_subtitle", _): "Set soft daily and weekly token/cost thresholds; AgentBar marks the menu bar when they are high."
        case ("daily_token_budget", _): "Daily token budget"
        case ("weekly_token_budget", _): "Weekly token budget"
        case ("daily_cost_budget", _): "Daily cost budget"
        case ("weekly_cost_budget", _): "Weekly cost budget"
        case ("daily_token_budget_subtitle", _): "Set 0 to disable daily token alerts."
        case ("weekly_token_budget_subtitle", _): "Set 0 to disable weekly token alerts."
        case ("daily_cost_budget_subtitle", _): "Set 0 to disable daily cost alerts."
        case ("weekly_cost_budget_subtitle", _): "Set 0 to disable weekly cost alerts."
        default: key
        }
    }

    private func dataSourceLocalized(_ key: String) -> String {
        switch (key, store.language) {
        case ("data_source_health", .chinese): "数据源健康"
        case ("data_source_health", _): "Data source health"
        default: key
        }
    }

    private var currentLimitAccounts: [UsageAccount] {
        store.accounts.filter { account in
            account.fiveHourWindow != nil ||
                account.weeklyWindow != nil ||
                account.resetCredits?.hasAvailableCredits == true
        }
        .sorted(using: settings.accountSortMode)
    }

    @ViewBuilder
    private var modelRows: some View {
        let rows = modelBreakdownRows
        if rows.isEmpty {
            EmptyPanelMessage(L.text("no_model_data", store.language))
        } else {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    HStack {
                        Text(row.name)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("\(L.text("input_abbrev", store.language)) \(DisplayFormatters.compactTokenString(row.input, language: store.language))")
                        Text("\(L.text("output_abbrev", store.language)) \(DisplayFormatters.compactTokenString(row.output, language: store.language))")
                            .frame(width: 96, alignment: .trailing)
                        Text(costText(row.cost))
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 88, alignment: .trailing)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(row.isHeader ? .secondary : .primary)
                    .padding(.vertical, 5)
                    if row.dividerAfter {
                        Divider().padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var modelBreakdownRows: [ModelBreakdownRow] {
        let grouped = Dictionary(grouping: filteredPoints, by: \.model)
        return grouped.map { model, points in
            let tokens = points.reduce(TokenTotals.zero) { $0 + $1.tokens }
            let costValues = points.compactMap(\.estimatedCostUSD)
            return ModelBreakdownRow(
                name: model,
                input: tokens.input,
                output: tokens.output,
                cost: costValues.isEmpty ? nil : costValues.reduce(Decimal(0), +),
                isHeader: false,
                dividerAfter: false
            )
        }
        .sorted { ($0.cost ?? 0, $0.input + $0.output) > ($1.cost ?? 0, $1.input + $1.output) }
    }

    private func resetText(_ date: Date?) -> String {
        guard let date else { return L.text("reset_time_unknown", store.language) }
        return "\(DisplayFormatters.relativeString(for: date)) \(L.text("resets_after", store.language))"
    }

    private func statusColor(_ percent: Double?, fallback: Color) -> Color {
        guard let percent else { return .secondary }
        if percent < 15 { return .red }
        if percent < 35 { return .orange }
        return fallback
    }
}

enum DashboardTopTab: String, Hashable {
    case usage
    case settings
}

private enum DashboardViewMode: Hashable {
    case overview
    case audit
}

private struct DashboardKPI: View {
    var title: String
    var value: String
    var delta: String
    var marker: Color?
    var accent: Color
    var theme: AppThemeColor

    init(title: String, value: String, delta: String, marker: Color? = nil, accent: Color, theme: AppThemeColor) {
        self.title = title
        self.value = value
        self.delta = delta
        self.marker = marker
        self.accent = accent
        self.theme = theme
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let marker {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(marker)
                        .frame(width: 7, height: 7)
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(accent)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(delta)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.primary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .dashboardPanel()
    }
}

private struct Panel<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .dashboardPanel()
    }
}

private struct ResizablePanel<Content: View>: View {
    var title: String
    @Binding var height: CGFloat
    var minHeight: CGFloat
    var maxHeight: CGFloat
    var theme: AppThemeColor
    @ViewBuilder var content: () -> Content
    @State private var dragStartHeight: CGFloat?
    @State private var liveHeight: CGFloat?

    private var effectiveHeight: CGFloat {
        liveHeight ?? height
    }

    private var bounds: PanelResizeBounds {
        PanelResizeBounds(minHeight: Double(minHeight), maxHeight: Double(maxHeight))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
            content()
                .frame(height: effectiveHeight)
                .clipped()
            resizeHandle
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .dashboardPanel()
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var resizeHandle: some View {
        HStack {
            Spacer()
            Capsule()
                .fill(theme.primary.opacity(0.28))
                .frame(width: 46, height: 5)
                .overlay {
                    Capsule()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            let startHeight = dragStartHeight ?? height
                            dragStartHeight = startHeight
                            let nextHeight = CGFloat(bounds.height(
                                startHeight: Double(startHeight),
                                translation: Double(value.location.y - value.startLocation.y)
                            ))
                            if abs((liveHeight ?? height) - nextHeight) >= 0.5 {
                                liveHeight = nextHeight
                            }
                        }
                        .onEnded { value in
                            let startHeight = dragStartHeight ?? height
                            let nextHeight = CGFloat(bounds.height(
                                startHeight: Double(startHeight),
                                translation: Double(value.location.y - value.startLocation.y)
                            ))
                            liveHeight = nil
                            dragStartHeight = nil
                            height = nextHeight
                        }
                )
                .verticalResizeCursor()
                .accessibilityLabel("Resize Current limits")
            Spacer()
        }
        .padding(.top, 1)
    }
}

private struct DashboardStackedBars: View {
    var bars: [DailyUsageBar]
    var language: AppLanguage
    var theme: AppThemeColor
    @State private var hoveredBarID: Date?
    @State private var hoverLocation: CGPoint?
    @State private var hoverPlotSize: CGSize = .zero

    private let calloutSize = CGSize(width: 210, height: 94)

    var body: some View {
        GeometryReader { proxy in
            if bars.isEmpty {
                EmptyPanelMessage(L.text("no_usage_events", language))
                    .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                let maxValue = max(1, bars.map { $0.codexTokens + $0.claudeTokens }.max() ?? 1)
                let plotHeight = max(0, proxy.size.height - 36)
                ZStack(alignment: .top) {
                    VStack(spacing: 4) {
                        HStack(alignment: .bottom, spacing: 8) {
                            VStack(alignment: .trailing) {
                                Text(DisplayFormatters.compactTokenString(maxValue, language: language))
                                Spacer()
                                Text(DisplayFormatters.compactTokenString(maxValue / 2, language: language))
                                Spacer()
                                Text("0")
                            }
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: max(1, proxy.size.height - 24))

                            GeometryReader { plotProxy in
                                ZStack(alignment: .bottom) {
                                    VStack {
                                        Divider()
                                        Spacer()
                                        Divider()
                                        Spacer()
                                        Divider()
                                    }
                                    .opacity(0.45)

                                    HStack(alignment: .bottom, spacing: 0) {
                                        ForEach(bars) { bar in
                                            VStack(spacing: 0) {
                                                Rectangle()
                                                    .fill(theme.secondary)
                                                    .frame(height: plotHeight * CGFloat(bar.claudeTokens) / CGFloat(maxValue))
                                                Rectangle()
                                                    .fill(theme.tertiary)
                                                    .frame(height: plotHeight * CGFloat(bar.codexTokens) / CGFloat(maxValue))
                                            }
                                            .frame(width: 28, height: plotHeight, alignment: .bottom)
                                            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                                            .frame(maxWidth: .infinity, maxHeight: plotHeight, alignment: .bottom)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                }
                                .frame(width: plotProxy.size.width, height: plotHeight, alignment: .bottom)
                                .overlay {
                                    PlotHoverTrackingView { location, size in
                                        if let location {
                                            hoveredBarID = barID(at: location.x, plotWidth: size.width)
                                            hoverLocation = location
                                            hoverPlotSize = size
                                        } else {
                                            hoveredBarID = nil
                                            hoverLocation = nil
                                        }
                                    }
                                }
                            }
                            .frame(height: plotHeight)
                        }
                        HStack {
                            Text(axisDate(bars.first?.day))
                            Spacer()
                            Text(axisDate(bars[bars.count / 2].day))
                            Spacer()
                            Text(axisDate(bars.last?.day))
                        }
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 52)
                    }

                    if let hoveredBar, let hoverLocation {
                        let tooltipPosition = ChartTooltipPlacement.position(cursor: hoverLocation, calloutSize: calloutSize, plotSize: hoverPlotSize)
                        ChartHoverCallout(bar: hoveredBar, language: language, theme: theme)
                            .frame(width: calloutSize.width, height: calloutSize.height)
                            .position(x: tooltipPosition.x + 52, y: tooltipPosition.y + 4)
                            .padding(.top, 4)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                            .allowsHitTesting(false)
                    }
                }
                .animation(nil, value: hoveredBarID)
            }
        }
    }

    private var hoveredBar: DailyUsageBar? {
        guard let hoveredBarID else { return nil }
        return bars.first { $0.id == hoveredBarID }
    }

    private func barID(at x: CGFloat, plotWidth: CGFloat) -> Date? {
        guard let index = ChartTooltipPlacement.barIndex(at: x, plotWidth: plotWidth, barCount: bars.count) else { return nil }
        guard bars.indices.contains(index) else { return nil }
        return bars[index].id
    }

    private func axisDate(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = language == .chinese ? Locale(identifier: "zh_Hans") : Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }
}

private struct ChartHoverCallout: View {
    var bar: DailyUsageBar
    var language: AppLanguage
    var theme: AppThemeColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateText)
                .font(.system(size: 11, weight: .bold))
            metricRow("Codex", value: bar.codexTokens, color: theme.tertiary)
            metricRow("Claude", value: bar.claudeTokens, color: theme.secondary)
            Divider()
            HStack {
                Text(L.text("total", language))
                Spacer()
                Text("\(DisplayFormatters.compactTokenString(bar.codexTokens + bar.claudeTokens, language: language)) \(L.text("tokens", language))")
                    .monospacedDigit()
            }
        }
        .font(.system(size: 10, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 210)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
    }

    private func metricRow(_ title: String, value: Int, color: Color) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
            Spacer()
            Text("\(DisplayFormatters.compactTokenString(value, language: language)) \(L.text("tokens", language))")
                .monospacedDigit()
        }
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = language == .chinese ? Locale(identifier: "zh_Hans") : Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter.string(from: bar.day)
    }
}

private struct PlotHoverTrackingView: NSViewRepresentable {
    var onHover: (CGPoint?, CGSize) -> Void

    func makeNSView(context: Context) -> HoverTrackingNSView {
        let view = HoverTrackingNSView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: HoverTrackingNSView, context: Context) {
        nsView.onHover = onHover
    }

    final class HoverTrackingNSView: NSView {
        var onHover: ((CGPoint?, CGSize) -> Void)?
        private var trackingArea: NSTrackingArea?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = false
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            wantsLayer = false
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseMoved(with event: NSEvent) {
            onHover?(convert(event.locationInWindow, from: nil), bounds.size)
        }

        override func mouseEntered(with event: NSEvent) {
            onHover?(convert(event.locationInWindow, from: nil), bounds.size)
        }

        override func mouseExited(with event: NSEvent) {
            onHover?(nil, bounds.size)
        }
    }
}

private struct ProgressRing<Center: View>: View {
    let value: Double
    let tint: Color
    var diameter: CGFloat
    var stroke: CGFloat
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: stroke)
            Circle()
                .trim(from: 0, to: min(1, max(0, value)))
                .stroke(tint, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center()
        }
        .frame(width: diameter, height: diameter)
    }
}

private struct LegendItem: View {
    var title: String
    var color: Color
    var subtitle: String?

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 13, weight: .bold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct EmptyPanelMessage: View {
    var message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}

private struct LoadingStatusPill: View {
    var message: String

    var body: some View {
        HStack(spacing: 7) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .glassPanel(cornerRadius: 12, interactive: false)
    }
}

private struct LoadingAccountPanel: View {
    var title: String
    var subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 14, interactive: true)
    }
}

private struct CurrentLimitSummaryStrip: View {
    var summary: CurrentLimitSummary
    var resetCreditsCount: Int
    var language: AppLanguage
    var theme: AppThemeColor

    var body: some View {
        HStack(spacing: 8) {
            SummaryChip(
                title: localized("most_constrained"),
                value: summary.mostConstrainedAccount?.displayName ?? "--",
                color: theme.quotaColor(remaining: summary.mostConstrainedAccount?.mostConstrainedRemainingPercent)
            )
            SummaryChip(
                title: localized("lowest_5h"),
                value: DisplayFormatters.percentString(summary.lowestFiveHourRemaining),
                color: theme.quotaColor(remaining: summary.lowestFiveHourRemaining)
            )
            SummaryChip(
                title: localized("lowest_weekly"),
                value: DisplayFormatters.percentString(summary.lowestWeeklyRemaining),
                color: theme.quotaColor(remaining: summary.lowestWeeklyRemaining)
            )
            SummaryChip(
                title: localized("resets"),
                value: "\(resetCreditsCount)",
                color: theme.primary
            )
            SummaryChip(
                title: localized("accounts"),
                value: "\(summary.accountCount)",
                color: theme.tertiary
            )
        }
    }

    private func localized(_ key: String) -> String {
        switch (key, language) {
        case ("most_constrained", .chinese): "最紧张"
        case ("lowest_5h", .chinese): "最低 5 小时"
        case ("lowest_weekly", .chinese): "最低本周"
        case ("resets", .chinese): "重置次数"
        case ("accounts", .chinese): "账号"
        case ("most_constrained", _): "Most constrained"
        case ("lowest_5h", _): "Lowest 5H"
        case ("lowest_weekly", _): "Lowest weekly"
        case ("resets", _): "Resets"
        case ("accounts", _): "Accounts"
        default: key
        }
    }
}

private struct QuotaPressurePanel: View {
    var pressure: QuotaPressureInsight
    var language: AppLanguage
    var theme: AppThemeColor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(severityColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(localized("quota_pressure"))
                        .font(.system(size: 13, weight: .bold))
                    Text(severityTitle)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(severityColor, in: Capsule())
                }
                Text(detailLine)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let recommendedAccount = pressure.recommendedAccount {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(localized("best_account"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(recommendedAccount.displayName)
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                    if let resetCredits = recommendedAccount.resetCredits, resetCredits.hasAvailableCredits {
                        Text(resetCredits.summaryLine(language: language))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(severityColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(severityColor.opacity(0.22), lineWidth: 0.5)
        )
    }

    private var iconName: String {
        switch pressure.severity {
        case .critical: "exclamationmark.triangle.fill"
        case .warning: "gauge.with.dots.needle.67percent"
        case .ok: "checkmark.circle.fill"
        }
    }

    private var severityColor: Color {
        switch pressure.severity {
        case .critical: .red
        case .warning: .orange
        case .ok: theme.primary
        }
    }

    private var severityTitle: String {
        switch (pressure.severity, language) {
        case (.critical, .chinese): "高风险"
        case (.warning, .chinese): "注意"
        case (.ok, .chinese): "正常"
        case (.critical, _): "High risk"
        case (.warning, _): "Watch"
        case (.ok, _): "Healthy"
        }
    }

    private var detailLine: String {
        let active = pressure.activeAccount?.displayName ?? "--"
        let projected = pressure.projectedFiveHourExhaustion.map { DisplayFormatters.relativeString(for: $0) }
        let rotation = pressure.shouldTriggerRotation ? localized("rotation_ready") : localized("rotation_standby")
        if let projected {
            return "\(active) · \(localized("five_hour_exhausts")) \(projected) · \(rotation)"
        }
        return "\(active) · \(localized("five_hour_healthy")) · \(rotation)"
    }

    private func localized(_ key: String) -> String {
        switch (key, language) {
        case ("quota_pressure", .chinese): "额度压力"
        case ("best_account", .chinese): "推荐账号"
        case ("five_hour_exhausts", .chinese): "预计 5 小时额度耗尽于"
        case ("five_hour_healthy", .chinese): "5 小时额度暂无风险"
        case ("rotation_ready", .chinese): "自动轮换会触发"
        case ("rotation_standby", .chinese): "自动轮换待命"
        case ("quota_pressure", _): "Quota pressure"
        case ("best_account", _): "Best account"
        case ("five_hour_exhausts", _): "5H may exhaust"
        case ("five_hour_healthy", _): "5H quota is healthy"
        case ("rotation_ready", _): "rotation will trigger"
        case ("rotation_standby", _): "rotation on standby"
        default: key
        }
    }
}

private struct UsageAnomalyPanel: View {
    var anomalies: [UsageAnomaly]
    var language: AppLanguage
    var theme: AppThemeColor

    var body: some View {
        Panel(title: localized("usage_anomalies")) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(anomalies.prefix(3)) { anomaly in
                    HStack(spacing: 10) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.orange)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(for: anomaly))
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                            Text(detail(for: anomaly))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(String(format: "%.1fx", anomaly.multiple))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(theme.primary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private func title(for anomaly: UsageAnomaly) -> String {
        switch (anomaly.kind, language) {
        case (.dailyTokens, .chinese): "今日 Token 激增"
        case (.modelTokens, .chinese): "\(anomaly.label) 用量激增"
        case (.dailyTokens, _): "Daily token spike"
        case (.modelTokens, _): "\(anomaly.label) spike"
        }
    }

    private func detail(for anomaly: UsageAnomaly) -> String {
        let tokens = DisplayFormatters.compactTokenString(anomaly.tokens, language: language)
        let baseline = DisplayFormatters.compactTokenString(anomaly.baselineTokens, language: language)
        switch language {
        case .chinese:
            return "\(tokens) \(L.text("tokens", language))，近期基线 \(baseline)"
        case .english:
            return "\(tokens) \(L.text("tokens", language)), baseline \(baseline)"
        }
    }

    private func localized(_ key: String) -> String {
        switch (key, language) {
        case ("usage_anomalies", .chinese): "用量异常"
        case ("usage_anomalies", _): "Usage anomalies"
        default: key
        }
    }
}

private struct BudgetStatusPanel: View {
    var today: BudgetStatus
    var weekly: BudgetStatus
    var language: AppLanguage
    var theme: AppThemeColor

    var body: some View {
        VStack(spacing: 8) {
            BudgetStatusRow(title: localized("today"), status: today, language: language, theme: theme)
            BudgetStatusRow(title: localized("week"), status: weekly, language: language, theme: theme)
        }
    }

    private func localized(_ key: String) -> String {
        switch (key, language) {
        case ("today", .chinese): "今日"
        case ("week", .chinese): "本周"
        case ("today", _): "Today"
        case ("week", _): "Week"
        default: key
        }
    }
}

private struct DataSourceHealthPanel: View {
    var health: DataSourceHealthSummary
    var language: AppLanguage
    var theme: AppThemeColor
    @State private var expandedRows: Set<UsageService> = []

    var body: some View {
        if health.rows.isEmpty {
            EmptyPanelMessage(localized("no_sources"))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    HealthCountPill(title: localized("live"), value: health.liveCount, color: theme.primary)
                    HealthCountPill(title: localized("issues"), value: health.issueCount, color: health.issueCount > 0 ? .orange : theme.tertiary)
                }

                ForEach(health.rows) { row in
                    dataSourceRow(row)
                }
            }
        }
    }

    private func dataSourceRow(_ row: DataSourceHealthSummary.Row) -> some View {
        let detailText = detail(for: row)
        let isExpanded = expandedRows.contains(row.id)

        return HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color(for: row.status))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.service.rawValue)
                    .font(.system(size: 12, weight: .bold))
                Text(detailText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : 1)
                    .fixedSize(horizontal: false, vertical: isExpanded)
            }
            Spacer(minLength: 8)
            if detailText.count > Self.compactDetailLimit {
                Button {
                    toggleExpanded(row.id)
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 18, height: 18)
                }
                .tactilePlainButton()
                .foregroundStyle(.secondary)
                .help(isExpanded ? "Hide full text" : "Show full text")
                .accessibilityLabel(isExpanded ? "Hide full text" : "Show full text")
            }
            Text(statusTitle(row.status))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color(for: row.status))
                .padding(.top, 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func toggleExpanded(_ id: UsageService) {
        if expandedRows.contains(id) {
            expandedRows.remove(id)
        } else {
            expandedRows.insert(id)
        }
    }

    private static let compactDetailLimit = 86

    private func detail(for row: DataSourceHealthSummary.Row) -> String {
        let refreshed = DisplayFormatters.relativeString(for: row.refreshedAt)
        if let note = row.note, !note.isEmpty {
            return "\(refreshed) · \(note.redactedForCredentialWords)"
        }
        switch language {
        case .chinese: return "\(refreshed) 刷新"
        case .english: return "Refreshed \(refreshed)"
        }
    }

    private func statusTitle(_ status: DataSourceStatus) -> String {
        switch (status, language) {
        case (.live, .chinese): "正常"
        case (.unavailable, .chinese): "不可用"
        case (.needsAuthorization, .chinese): "需授权"
        case (.error, .chinese): "错误"
        case (.live, _): "Live"
        case (.unavailable, _): "Unavailable"
        case (.needsAuthorization, _): "Needs auth"
        case (.error, _): "Error"
        }
    }

    private func color(for status: DataSourceStatus) -> Color {
        switch status {
        case .live: theme.primary
        case .unavailable: .secondary
        case .needsAuthorization: .orange
        case .error: .red
        }
    }

    private func localized(_ key: String) -> String {
        switch (key, language) {
        case ("no_sources", .chinese): "暂无数据源状态"
        case ("live", .chinese): "正常"
        case ("issues", .chinese): "问题"
        case ("no_sources", _): "No source status"
        case ("live", _): "Live"
        case ("issues", _): "Issues"
        default: key
        }
    }
}

private struct HealthCountPill: View {
    var title: String
    var value: Int
    var color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(.thinMaterial, in: Capsule())
    }
}

private struct BudgetStatusRow: View {
    var title: String
    var status: BudgetStatus
    var language: AppLanguage
    var theme: AppThemeColor

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text(severityTitle)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(severityColor)
            }

            HStack(spacing: 10) {
                budgetMeter(label: L.text("tokens", language), fraction: status.tokenUsageFraction)
                budgetMeter(label: L.text("cost", language), fraction: status.costUsageFraction)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func budgetMeter(label: String, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(percentText(fraction))
                    .monospacedDigit()
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            ProgressView(value: min(1, max(0, fraction ?? 0)))
                .tint(color(for: fraction))
        }
    }

    private var severityTitle: String {
        switch (worstSeverity, language) {
        case (.critical, .chinese): "超出预算"
        case (.warning, .chinese): "接近预算"
        case (.ok, .chinese): "正常"
        case (.critical, _): "Over budget"
        case (.warning, _): "Near budget"
        case (.ok, _): "On track"
        }
    }

    private var worstSeverity: InsightSeverity {
        if status.tokenSeverity == .critical || status.costSeverity == .critical { return .critical }
        if status.tokenSeverity == .warning || status.costSeverity == .warning { return .warning }
        return .ok
    }

    private var severityColor: Color {
        switch worstSeverity {
        case .critical: .red
        case .warning: .orange
        case .ok: theme.primary
        }
    }

    private func color(for fraction: Double?) -> Color {
        guard let fraction else { return .secondary }
        if fraction >= 1 { return .red }
        if fraction >= 0.8 { return .orange }
        return theme.primary
    }

    private func percentText(_ fraction: Double?) -> String {
        guard let fraction else { return "--" }
        return "\(Int((fraction * 100).rounded()))%"
    }
}

private struct SummaryChip: View {
    var title: String
    var value: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(value)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AccountLimitGroupView: View {
    var account: UsageAccount
    var language: AppLanguage
    var theme: AppThemeColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(account.displayName)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                        if account.isActive {
                            Text(L.text("current", language))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(theme.primary, in: Capsule())
                        }
                    }
                    Text(accountDetailLine)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(account.service.rawValue)
                        .font(.system(size: 10, weight: .bold))
                    Text(account.accountTypeValue)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                UsageWindowGauge(title: L.text("five_hour", language), window: account.fiveHourWindow, language: language, theme: theme)
                UsageWindowGauge(title: L.text("weekly", language), window: account.weeklyWindow, language: language, theme: theme)
            }

            if let resetCredits = account.resetCredits, resetCredits.hasAvailableCredits {
                VStack(alignment: .leading, spacing: 2) {
                    Label(resetCredits.summaryLine(language: language), systemImage: "arrow.counterclockwise.circle")
                        .labelStyle(.titleAndIcon)
                    ForEach(Array(resetCredits.expirationLines(language: language).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .padding(.leading, 17)
                    }
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .padding(9)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var accountDetailLine: String {
        let identity = account.username ?? account.maskedEmail ?? account.sourceDescription
        if let lastUpdated = account.lastUpdated {
            return "\(identity) · \(DisplayFormatters.relativeString(for: lastUpdated))"
        }
        return identity
    }
}

private struct SettingsGroup<Content: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dashboardPanel()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsRow<Content: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var control: () -> Content

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            control()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, SettingsControlLayout.leadingInset)
        .padding(.trailing, SettingsControlLayout.trailingInset)
        .padding(.vertical, 12)
    }
}

private struct BudgetIntegerField: View {
    @Binding var value: Int
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 6) {
            TextField("0", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(L.text("tokens", language))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct BudgetCostField: View {
    @Binding var value: Double
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 6) {
            Text("$")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("0", value: $value, format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 86)
        }
    }
}

private extension View {
    func settingsControl(width: CGFloat) -> some View {
        frame(width: width, alignment: .trailing)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct ServiceMixRow {
    var service: UsageService
    var title: String
    var subtitle: String
    var tokens: Int
    var share: Double
    var cost: String
    var color: Color
}

private struct LimitRow: Identifiable {
    var id: String { accountID + kind }
    var accountID: String
    var kind: String
    var title: String
    var subtitle: String
    var accountName: String
    var accountDetail: String
    var percent: Double
    var color: Color

    init(account: UsageAccount, kind: String, subtitle: String, percent: Double, color: Color) {
        self.accountID = account.id
        self.kind = kind
        self.title = "\(account.service.rawValue) \(kind)"
        self.subtitle = subtitle
        self.accountName = account.displayName
        self.accountDetail = LimitRow.detailText(for: account)
        self.percent = percent
        self.color = color
    }

    private static func detailText(for account: UsageAccount) -> String {
        let identity = account.username ?? account.maskedEmail ?? account.sourceDescription
        if let plan = account.plan, !plan.isEmpty {
            return "\(identity) · \(plan)"
        }
        return identity
    }
}

private struct ModelBreakdownRow: Identifiable {
    var id: String { name }
    var name: String
    var input: Int
    var output: Int
    var cost: Decimal?
    var isHeader: Bool
    var dividerAfter: Bool
}

private extension View {
    func dashboardPanel() -> some View {
        glassPanel(cornerRadius: 12, interactive: true)
    }

    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat, interactive: Bool) -> some View {
        self
            .agentBarPanel(cornerRadius: cornerRadius)
    }
}

private extension UsageRange {
    func dashboardLabel(_ language: AppLanguage) -> String {
        guard language == .chinese else {
            switch self {
            case .today: return "Today"
            case .yesterday: return "Yesterday"
            case .thisWeek: return "Week"
            case .thisMonth: return "Month"
            case .thisYear: return "Year"
            case .last7Days: return "7 Days"
            case .last30Days: return "30 Days"
            case .all: return "All"
            case .custom: return "Custom"
            }
        }
        switch self {
        case .today: return "今天"
        case .yesterday: return "昨天"
        case .thisWeek: return "本周"
        case .thisMonth: return "本月"
        case .thisYear: return "本年"
        case .last7Days: return "7 天"
        case .last30Days: return "30 天"
        case .all: return "全部"
        case .custom: return "自定义"
        }
    }
}
