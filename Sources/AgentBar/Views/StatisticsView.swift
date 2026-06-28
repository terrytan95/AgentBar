import AppKit
import SwiftUI

struct StatisticsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var updates: AppUpdateStore
    @State private var viewMode: DashboardViewMode = .overview
    @State private var topTab: DashboardTopTab
    @State private var selectedSessionLabel: String?
    @State private var showsAccountPopover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .frame(width: 236)

            VStack(spacing: 0) {
                pageContent
                    .id(pageTransitionID)
                    .transition(pageTransition)
                    .animation(pageAnimation, value: pageTransitionID)
                appFooter
                    .padding(.horizontal, 26)
                    .frame(height: 42)
                    .background(.ultraThinMaterial)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        AgentBarDesign.panelHighlight,
                        AgentBarDesign.appBackground,
                        settings.themeColor.primary.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .tint(settings.themeColor.primary)
        .background(AgentBarDesign.appBackground)
        .onReceive(NotificationCenter.default.publisher(for: DashboardNavigation.tabRequestNotification)) { notification in
            guard let rawValue = notification.userInfo?["tab"] as? String,
                  let tab = DashboardTopTab(rawValue: rawValue)
            else { return }
            setTopTab(tab)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarBrand
                .padding(.top, 16)
                .padding(.bottom, 34)

            sidebarGroup(title: L.text("usage_statistics", store.language)) {
                sidebarItem(L.text("overview", store.language), systemImage: "rectangle.split.2x2", active: topTab == .usage && viewMode == .overview) {
                    setPage(tab: .usage, viewMode: .overview)
                }
                sidebarItem(L.text("resets", store.language), systemImage: "arrow.counterclockwise.circle", active: topTab == .usage && viewMode == .resets) {
                    setPage(tab: .usage, viewMode: .resets)
                }
                sidebarItem(L.text("audit", store.language), systemImage: "chart.bar.doc.horizontal", active: topTab == .usage && viewMode == .audit) {
                    setPage(tab: .usage, viewMode: .audit)
                }
                sidebarItem(L.text("settings", store.language), systemImage: "gearshape", active: topTab == .settings) {
                    setPage(tab: .settings)
                }
            }

            Spacer()

            sidebarAccountSelector
                .padding(.bottom, 18)
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AgentBarDesign.hairline)
                .frame(width: 1)
        }
    }

    private var sidebarBrand: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppLogo.image())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("AgentBar")
                .font(.system(size: 20, weight: .bold))
        }
    }

    private var sidebarAccountSelector: some View {
        let account = store.activeAccount ?? currentCodexAccount
        return Button {
            showsAccountPopover.toggle()
        } label: {
            HStack(spacing: 10) {
                AccountAvatar(text: account?.displayName ?? "A", color: settings.themeColor.primary, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account?.displayName ?? "--")
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                    Text(account?.workspaceLine(language: store.language) ?? L.text("current_account", store.language))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .agentBarPanel(cornerRadius: 10)
        .popover(isPresented: $showsAccountPopover, arrowEdge: .bottom) {
            SidebarAccountPopover(account: account, language: store.language, theme: settings.themeColor)
        }
    }

    private var appFooter: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 10, height: 10)
                    .shadow(color: .green.opacity(0.36), radius: 5)
                Text("数据每分钟自动更新")
                Spacer()
                Text(footerDateTimeText(timeline.date))
                    .monospacedDigit()
                Text(timeZoneText)
                Image(systemName: "shield.checkered")
                Text("数据安全保护中")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
        }
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.text("settings", store.language))
                .font(.system(size: 24, weight: .bold))
            Text(L.text("general_settings_subtitle", store.language))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeZoneText: String {
        let seconds = TimeZone.current.secondsFromGMT()
        let sign = seconds >= 0 ? "+" : "-"
        let absolute = abs(seconds)
        let hours = absolute / 3_600
        let minutes = (absolute % 3_600) / 60
        let offset = minutes == 0 ? "\(sign)\(hours)" : String(format: "%@%02d:%02d", sign, hours, minutes)
        return "\(store.language == .chinese ? "时区" : "TZ"): \(TimeZone.current.identifier) UTC\(offset)"
    }

    private func footerDateTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = store.language == .chinese ? Locale(identifier: "zh_Hans") : Locale(identifier: "en_US")
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func setTopTab(_ tab: DashboardTopTab) {
        setPage(tab: tab)
    }

    private func setPage(tab: DashboardTopTab, viewMode: DashboardViewMode? = nil) {
        withAnimation(pageAnimation) {
            topTab = tab
            if let viewMode {
                self.viewMode = viewMode
            }
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        if topTab == .usage {
            usageContent
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                settingsHeader
                    .padding(.top, 24)
                    .padding(.horizontal, 26)
                settingsContent
                    .padding(.top, 12)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 28)
            }
        }
    }

    private var pageTransitionID: String {
        switch topTab {
        case .usage:
            return "usage-\(viewMode)"
        case .settings:
            return DashboardTopTab.settings.rawValue
        }
    }

    private var pageAnimation: Animation? {
        AgentBarDesign.smoothAnimation(reduceMotion: reduceMotion, duration: 0.10)
    }

    private var pageTransition: AnyTransition {
        .opacity
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
            .foregroundStyle(active ? settings.themeColor.primary : (enabled ? Color.primary.opacity(0.86) : Color.secondary.opacity(0.72)))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(active ? settings.themeColor.primary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(active ? settings.themeColor.primary.opacity(0.24) : Color.clear, lineWidth: 1)
            }
            .shadow(color: active ? settings.themeColor.primary.opacity(0.18) : .clear, radius: 10, y: 4)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.86)
        .tactilePlainButton(enabled: enabled)
    }

    private var usageContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                switch viewMode {
                case .overview:
                    dashboardContent
                case .resets:
                    resetsContent
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
            .padding(.horizontal, 26)
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
        .agentBarPanel(cornerRadius: 10)
        .help(L.text("refresh", store.language))
    }

    @ViewBuilder
    private var dashboardContent: some View {
        let projection = dashboardOverviewProjection

        VStack(alignment: .leading, spacing: 16) {
            dashboardOverviewHeader

            if !store.hasLoadedAccountInformation {
                LoadingAccountPanel(
                    title: L.text("loading_account_info", store.language),
                    subtitle: L.text("loading_account_info_subtitle", store.language)
                )
            }

            GeometryReader { proxy in
                LazyVGrid(columns: kpiColumns(for: proxy.size.width), spacing: 14) {
                    DashboardKPI(
                        title: L.text("total_tokens", store.language),
                        value: DisplayFormatters.compactTokenString(summary.totalTokens, language: store.language),
                        delta: DisplayFormatters.changePercentString(periodChange.tokenPercent),
                        subtitle: "较昨日",
                        systemImage: "cylinder.split.1x2.fill",
                        accent: settings.themeColor.primary,
                        theme: settings.themeColor
                    )
                    DashboardKPI(
                        title: L.text("total_cost", store.language),
                        value: costText(summary.estimatedCostUSD),
                        delta: DisplayFormatters.changePercentString(periodChange.costPercent),
                        subtitle: "较昨日",
                        systemImage: "dollarsign",
                        accent: .green,
                        theme: settings.themeColor
                    )
                    DashboardKPI(
                        title: "OpenAI 概览",
                        value: serviceCostText(.codex),
                        delta: serviceShareText(.codex),
                        subtitle: "占总花费比例",
                        systemImage: "sparkles",
                        marker: settings.themeColor.tertiary,
                        accent: settings.themeColor.tertiary,
                        theme: settings.themeColor
                    )
                }
            }
            .frame(height: 116)

            QuotaPressurePanel(pressure: projection.quotaPressure, language: store.language, theme: settings.themeColor)

            dailyUsagePanel

            Panel(title: quotaCapacityLocalized("quota_capacity_history")) {
                QuotaCapacityHistoryPanel(history: store.quotaCapacityHistory, language: store.language, theme: settings.themeColor)
            }
            .help(quotaCapacityLocalized("quota_capacity_history_tooltip"))

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    Panel(title: L.text("by_service", store.language)) {
                        serviceMixRows
                    }
                    Panel(title: L.text("by_model", store.language)) {
                        modelRows
                    }
                }
                Panel(title: usageLocalized("top_usage")) {
                    TopUsagePanel(
                        breakdown: projection.topUsage,
                        selectedSessionLabel: selectedSessionLabel,
                        language: store.language,
                        theme: settings.themeColor
                    ) { label in
                        selectedSessionLabel = label
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            Panel(title: L.text("current_limits", store.language)) {
                currentLimitsRows
            }
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

            dashboardRefreshButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dailyUsagePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text(store.selectedRange.chartTitle(store.language))
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                dashboardRangePicker
            }

            HStack(spacing: 14) {
                LegendItem(title: "Token（万）", color: settings.themeColor.primary)
                LegendItem(title: "花费（美元）", color: .orange)
                Spacer()
            }

            DashboardStackedBars(bars: displayBars, language: store.language, theme: settings.themeColor)
                .frame(height: 230)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .agentBarPanel()
    }

    private var dashboardRangePicker: some View {
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
        .agentBarPanel(cornerRadius: 12)
    }

    private var resetsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.text("resets", store.language))
                        .font(.system(size: 20, weight: .bold))
                    Text(L.text("reset_intro", store.language))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(isOn: $settings.detailedResetCreditsEnabled) {
                    Label(L.text("expiry_dates", store.language), systemImage: settings.detailedResetCreditsEnabled ? "hourglass.circle.fill" : "hourglass")
                }
                .toggleStyle(.button)
                .help(L.text("expiry_dates_help", store.language))
                .onChange(of: settings.detailedResetCreditsEnabled) { _, enabled in
                    if enabled {
                        store.refresh(force: true, showManualFeedback: true)
                    }
                }
                dashboardRefreshButton
            }

            GeometryReader { proxy in
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: proxy.size.width < 820 ? 2 : 4), spacing: 14) {
                    SummaryChip(title: L.text("resets", store.language), value: "\(totalResetCreditsCount)", color: .green, systemImage: "checkmark")
                    SummaryChip(title: L.text("next_expiry", store.language), value: nextResetExpiry.map { DisplayFormatters.shortDateTimeString(for: $0, language: store.language) } ?? "--", color: resetExpiryColor(nextResetExpiry), systemImage: "clock")
                    SummaryChip(title: L.text("five_hour_left", store.language), value: DisplayFormatters.percentString(store.activeAccount?.fiveHourWindow?.remainingPercent), color: quotaMeterColor(store.activeAccount?.fiveHourWindow?.remainingPercent), progress: store.activeAccount?.fiveHourWindow?.remainingPercent)
                    SummaryChip(title: L.text("weekly_left", store.language), value: DisplayFormatters.percentString(store.activeAccount?.weeklyWindow?.remainingPercent), color: quotaMeterColor(store.activeAccount?.weeklyWindow?.remainingPercent), progress: store.activeAccount?.weeklyWindow?.remainingPercent)
                }
            }
            .frame(height: 90)

            ResetAdvicePanel(advice: resetSpendAdvice, theme: settings.themeColor)

            HStack(alignment: .top, spacing: 14) {
                Panel(title: L.text("expiry_watch", store.language)) {
                    resetExpiryRows
                }
                Panel(title: L.text("current_windows", store.language)) {
                    currentLimitsRows
                }
            }
        }
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
                if !codexAccounts.isEmpty {
                    SettingsAccountDropdown(
                        accounts: store.sortedAccounts(codexAccounts),
                        currentAccount: currentCodexAccount,
                        language: store.language,
                        onRemove: store.removeAccount
                    )
                    .padding(12)
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

            SettingsGroup(title: healthLocalized("account_health"), subtitle: healthLocalized("account_health_subtitle")) {
                AccountHealthCenterPanel(
                    health: accountHealthCenter,
                    language: store.language,
                    theme: settings.themeColor,
                    onLogin: openHealthLogin,
                    onRemove: removeHealthAccount,
                    onRefresh: { store.refresh(force: true, showManualFeedback: true) }
                )
                .padding(12)
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
                SettingsRow(title: quotaCapacityLocalized("quota_capacity_frequency"), subtitle: quotaCapacityLocalized("quota_capacity_frequency_subtitle")) {
                    Picker("", selection: $settings.quotaCapacityHistoryInterval) {
                        Text("15m").tag(TimeInterval(900))
                        Text("30m").tag(TimeInterval(1_800))
                        Text("1h").tag(TimeInterval(3_600))
                        Text("2h").tag(TimeInterval(7_200))
                        Text("6h").tag(TimeInterval(21_600))
                    }
                    .labelsHidden()
                    .settingsControl(width: SettingsControlLayout.compactPickerWidth)
                }
                SettingsRow(title: L.text("quota_reset_notifications", store.language), subtitle: L.text("quota_reset_notifications_subtitle", store.language)) {
                    Toggle("", isOn: $settings.quotaResetNotificationsEnabled).labelsHidden()
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
                            Text(theme.title(language: store.language)).tag(theme)
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

    private var selectedRangePoints: [UsagePoint] {
        guard let interval = store.selectedRange.dateInterval(now: Date(), calendar: .current, customStart: store.customStart, customEnd: store.customEnd) else {
            return filteredPoints
        }
        return filteredPoints.filter { interval.contains($0.date) }
    }

    private var codexAccounts: [UsageAccount] {
        store.accounts.filter { $0.service == .codex }
    }

    private var currentCodexAccount: UsageAccount? {
        codexAccounts.first(where: \.isActive) ?? codexAccounts.first
    }

    private var claudeAccounts: [UsageAccount] {
        store.accounts.filter { $0.service == .claudeCode }
    }

    private var hasClaudeData: Bool {
        !claudeAccounts.isEmpty || store.points.contains { $0.service == .claudeCode }
    }

    private func kpiColumns(for width: CGFloat) -> [GridItem] {
        let count = width < 760 ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    private var displayBars: [DailyUsageBar] {
        let bars = summary.dailyBars
        guard !bars.isEmpty else { return [] }
        return Array(bars.suffix(24))
    }

    private func serviceCostText(_ service: UsageService) -> String {
        let costs = selectedRangePoints.filter { $0.service == service }.compactMap(\.estimatedCostUSD)
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
            HStack(spacing: 18) {
                ProgressRing(value: rows.first?.share ?? 0, tint: rows.first?.color ?? settings.themeColor.primary, diameter: 118, stroke: 16) {
                    VStack(spacing: 2) {
                        Text(DisplayFormatters.compactTokenString(summary.totalTokens, language: store.language))
                            .font(.system(size: 18, weight: .bold))
                            .monospacedDigit()
                        Text(L.text("total_tokens", store.language))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(spacing: 10) {
                    ForEach(rows, id: \.service) { row in
                        HStack(spacing: 8) {
                            LegendItem(title: row.title, color: row.color)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(Int((row.share * 100).rounded()))%")
                                    .font(.system(size: 12, weight: .bold))
                                Text(DisplayFormatters.compactTokenString(row.tokens, language: store.language))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                    } label: {
                        Label("查看全部服务", systemImage: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .tactilePlainButton()
                    .foregroundStyle(settings.themeColor.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    ForEach(currentLimitDisplayGroups) { group in
                        AccountLimitDisplayGroupView(
                            group: group,
                            language: store.language,
                            theme: settings.themeColor,
                            switchingAccountID: store.switchingAccountID,
                            onSwitch: store.switchActiveAccount,
                            onLogin: { account in store.openLogin(for: account) }
                        )
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

    private var nextResetExpiry: Date? {
        store.accounts
            .flatMap { $0.resetCredits?.resets ?? [] }
            .compactMap(\.expiresAt)
            .filter { $0 > Date() }
            .sorted()
            .first
    }

    private var resetSpendAdvice: ResetSpendAdvice {
        ResetSpendAdvice.make(
            fiveHour: store.activeAccount?.fiveHourWindow,
            weekly: store.activeAccount?.weeklyWindow,
            resetCount: totalResetCreditsCount,
            nextExpiry: nextResetExpiry,
            language: store.language
        )
    }

    @ViewBuilder
    private var resetExpiryRows: some View {
        if !settings.detailedResetCreditsEnabled {
            EmptyPanelMessage(L.text("enable_expiry_dates", store.language))
        } else {
            let groups = resetExpiryDisplayGroups
            if groups.isEmpty {
                EmptyPanelMessage(totalResetCreditsCount > 0 ? L.text("no_detailed_expiry_dates", store.language) : L.text("no_banked_resets", store.language))
            } else {
                VStack(spacing: 8) {
                    ForEach(groups) { group in
                        ResetExpiryDisplayGroupView(group: group, language: store.language, theme: settings.themeColor)
                    }
                }
            }
        }
    }

    private var dashboardOverviewProjection: DashboardOverviewProjection {
        UsageInsights.dashboardOverviewProjection(
            accounts: store.accounts,
            points: filteredPoints,
            snapshots: store.snapshots,
            selectedSessionLabel: selectedSessionLabel,
            rotationThresholdRemainingPercent: settings.codexRotationThresholdRemainingPercent,
            autoRotationEnabled: settings.autoCodexAccountRotationEnabled,
            language: store.language
        )
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

    private var accountHealthCenter: AccountHealthCenter {
        UsageInsights.accountHealthCenter(accounts: store.accounts, dataSourceHealth: dataSourceHealth, language: store.language)
    }

    private func openHealthLogin(_ accountID: String) {
        guard let account = store.accounts.first(where: { $0.id == accountID }) else { return }
        store.openLogin(for: account)
    }

    private func removeHealthAccount(_ accountID: String) {
        guard let account = store.accounts.first(where: { $0.id == accountID }) else { return }
        store.removeAccount(account)
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

    private func usageLocalized(_ key: String) -> String {
        switch (key, store.language) {
        case ("top_usage", .chinese): "高消耗定位"
        case ("session_drilldown", .chinese): "会话明细"
        case ("top_usage", _): "Top usage"
        case ("session_drilldown", _): "Session drilldown"
        default: key
        }
    }

    private func healthLocalized(_ key: String) -> String {
        switch (key, store.language) {
        case ("account_health", .chinese): "账号健康"
        case ("account_health_subtitle", .chinese): "集中处理重新登录、数据源异常和无效账号。"
        case ("account_health", _): "Account health"
        case ("account_health_subtitle", _): "Handle relogin, source issues, and stale accounts in one place."
        default: key
        }
    }

    private func quotaCapacityLocalized(_ key: String) -> String {
        switch (key, store.language) {
        case ("quota_capacity_history", .chinese): "额度容量估算"
        case ("quota_capacity_frequency", .chinese): "额度容量采样频率"
        case ("quota_capacity_frequency_subtitle", .chinese): "按此间隔记录 5H/本周额度推算历史。"
        case ("quota_capacity_history_tooltip", .chinese): "根据最近采样估算 5H 和本周额度窗口的总 Token 容量，用来观察容量变化趋势并判断当前使用节奏。"
        case ("quota_capacity_history", _): "Quota capacity estimate"
        case ("quota_capacity_frequency", _): "Quota capacity sampling"
        case ("quota_capacity_frequency_subtitle", _): "Record estimated 5H and weekly capacity history on this cadence."
        case ("quota_capacity_history_tooltip", _): "Estimates total token capacity for the 5H and weekly quota windows from recent samples, so you can track capacity trends and judge usage pace."
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

    private var currentLimitDisplayGroups: [UsageAccountDisplayGroup] {
        currentLimitAccounts.displayGroupsByIdentity(sortMode: settings.accountSortMode)
    }

    private var resetExpiryDisplayGroups: [UsageAccountDisplayGroup] {
        store.accounts
            .filter { !($0.resetCredits?.resets ?? []).isEmpty }
            .displayGroupsByIdentity(sortMode: settings.accountSortMode)
    }

    @ViewBuilder
    private var modelRows: some View {
        let rows = modelBreakdownRows
        if rows.isEmpty {
            EmptyPanelMessage(L.text("no_model_data", store.language))
        } else {
            let dataRows = rows.filter { !$0.isHeader }
            let maximum = max(1, dataRows.map { $0.input + $0.output }.max() ?? 1)
            VStack(spacing: 9) {
                ForEach(dataRows.prefix(6)) { row in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(row.name)
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                            Spacer()
                            Text(DisplayFormatters.compactTokenString(row.input + row.output, language: store.language))
                                .font(.system(size: 11, weight: .bold))
                                .monospacedDigit()
                            Text("\(Int((Double(row.input + row.output) / Double(maximum) * 100).rounded()))%")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .trailing)
                        }
                        ProgressView(value: Double(row.input + row.output) / Double(maximum))
                            .tint(serviceColor(row.service))
                    }
                }
                Button {
                } label: {
                    Label("查看全部模型", systemImage: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .tactilePlainButton()
                .foregroundStyle(settings.themeColor.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var modelBreakdownRows: [ModelBreakdownRow] {
        UsageService.allCases.flatMap { service -> [ModelBreakdownRow] in
            let servicePoints = selectedRangePoints.filter { $0.service == service }
            guard !servicePoints.isEmpty else { return [] }
            let rows = Dictionary(grouping: servicePoints, by: \.model).map { model, points in
                let tokens = points.reduce(TokenTotals.zero) { $0 + $1.tokens }
                let costValues = points.compactMap(\.estimatedCostUSD)
                let cost = costValues.isEmpty ? nil : costValues.reduce(Decimal(0), +)
                let output = tokens.output + tokens.reasoningOutput
                return ModelBreakdownRow(
                    service: service,
                    name: model,
                    input: tokens.input,
                    output: output,
                    cost: cost,
                    isHeader: false,
                    dividerAfter: false
                )
            }
            .sorted { lhs, rhs in
                let lhsCost = lhs.cost ?? 0
                let rhsCost = rhs.cost ?? 0
                if lhsCost != rhsCost { return lhsCost > rhsCost }
                return lhs.input + lhs.output > rhs.input + rhs.output
            }

            return [ModelBreakdownRow(service: service, name: serviceTitle(service), input: 0, output: 0, cost: nil, isHeader: true, dividerAfter: false)] + rows
        }
    }

    private func serviceTitle(_ service: UsageService) -> String {
        service == .codex ? "Codex" : "Claude"
    }

    private func serviceSubtitle(_ service: UsageService) -> String {
        service == .codex ? "OpenAI" : "Anthropic"
    }

    private func serviceColor(_ service: UsageService) -> Color {
        service == .codex ? settings.themeColor.tertiary : settings.themeColor.secondary
    }

    private func resetText(_ date: Date?) -> String {
        guard let date else { return L.text("reset_time_unknown", store.language) }
        return "\(DisplayFormatters.relativeString(for: date, language: store.language)) \(L.text("resets_after", store.language))"
    }

    private func statusColor(_ percent: Double?, fallback: Color) -> Color {
        guard let percent else { return .secondary }
        if percent < 15 { return .red }
        if percent < 35 { return .orange }
        return fallback
    }

    private func resetExpiryColor(_ date: Date?) -> Color {
        guard let date else { return .secondary }
        let seconds = date.timeIntervalSinceNow
        if seconds <= 86_400 { return .red }
        if seconds <= 3 * 86_400 { return .orange }
        return settings.themeColor.primary
    }

    private func quotaMeterColor(_ remaining: Double?) -> Color {
        guard let remaining else { return settings.themeColor.tertiary }
        if remaining < 15 { return .red }
        if remaining < 35 { return .yellow }
        return .blue
    }
}

enum DashboardTopTab: String, Hashable {
    case usage
    case settings
}

private enum DashboardViewMode: Hashable {
    case overview
    case resets
    case audit
}

private struct ResetSpendAdvice {
    var title: String
    var message: String
    var detail: String
    var systemImage: String
    var color: Color

    static func make(fiveHour: UsageWindow?, weekly: UsageWindow?, resetCount: Int, nextExpiry: Date?, language: AppLanguage, now: Date = Date()) -> ResetSpendAdvice {
        if resetCount > 0, let nextExpiry, nextExpiry.timeIntervalSince(now) <= 86_400 {
            return ResetSpendAdvice(title: localized("use_it_or_lose_it", language), message: localized("expires_today_message", language), detail: localized("expiry_warning", language), systemImage: "exclamationmark.octagon.fill", color: .red)
        }
        guard let weekly else {
            return ResetSpendAdvice(title: localized("waiting_on_meters", language), message: localized("waiting_on_meters_message", language), detail: localized("refresh_after_sign_in", language), systemImage: "questionmark.circle", color: .secondary)
        }
        let weeklyRemaining = weekly.remainingPercent
        let weeklyReset = weekly.resetsAt?.timeIntervalSince(now)
        if resetCount == 0 {
            return ResetSpendAdvice(title: localized("no_reset_cushion", language), message: localized("no_reset_cushion_message", language), detail: weeklyLeftDetail(weeklyRemaining, language), systemImage: "exclamationmark.triangle.fill", color: .secondary)
        }
        if let fiveHour, let fiveReset = fiveHour.resetsAt?.timeIntervalSince(now), fiveHour.remainingPercent <= 12, weeklyRemaining >= 25, fiveReset <= 90 * 60 {
            return ResetSpendAdvice(title: localized("let_5h_refill", language), message: localized("let_5h_refill_message", language), detail: fiveHourResetDetail(fiveHour.resetsAt ?? now, language), systemImage: "hourglass", color: .blue)
        }
        if let fiveHour, fiveHour.remainingPercent <= 12, weeklyRemaining >= 50 {
            return ResetSpendAdvice(title: localized("deadline_call", language), message: localized("deadline_call_message", language), detail: localized("five_hour_nearly_empty", language), systemImage: "bolt.badge.clock", color: .orange)
        }
        if let weeklyReset, resetCount >= 2, weeklyRemaining <= 15, weeklyReset >= 4 * 86_400 {
            return ResetSpendAdvice(title: localized("go_burn_tokens", language), message: localized("go_burn_tokens_message", language), detail: weeklyLeftDetail(weeklyRemaining, language), systemImage: "bolt.fill", color: .green)
        }
        if let weeklyReset, weeklyRemaining <= 20, weeklyReset >= 2 * 86_400 {
            return ResetSpendAdvice(title: localized("green_light_with_brakes", language), message: localized("green_light_with_brakes_message", language), detail: weeklyResetDetail(weekly.resetsAt ?? now, language), systemImage: "bolt.badge.clock", color: .orange)
        }
        if let weeklyReset, weeklyRemaining >= 35, weeklyReset <= 3 * 86_400 {
            return ResetSpendAdvice(title: localized("hold_that_reset", language), message: localized("hold_that_reset_message", language), detail: weeklyLeftDetail(weeklyRemaining, language), systemImage: "shield.fill", color: .blue)
        }
        return ResetSpendAdvice(title: localized("cruise_mode", language), message: localized("cruise_mode_message", language), detail: weeklyLeftDetail(weeklyRemaining, language), systemImage: "gauge.with.dots.needle.50percent", color: .cyan)
    }

    private static func weeklyLeftDetail(_ remaining: Double, _ language: AppLanguage) -> String {
        switch language {
        case .chinese: "\(DisplayFormatters.percentString(remaining)) 本周剩余"
        case .english: "\(DisplayFormatters.percentString(remaining)) weekly left"
        }
    }

    private static func fiveHourResetDetail(_ date: Date, _ language: AppLanguage) -> String {
        switch language {
        case .chinese: "5 小时额度 \(DisplayFormatters.relativeString(for: date, language: language)) 重置"
        case .english: "5H resets \(DisplayFormatters.relativeString(for: date, language: language))"
        }
    }

    private static func weeklyResetDetail(_ date: Date, _ language: AppLanguage) -> String {
        switch language {
        case .chinese: "距离本周重置 \(DisplayFormatters.relativeString(for: date, language: language))"
        case .english: "\(DisplayFormatters.relativeString(for: date, language: language)) to weekly reset"
        }
    }

    private static func localized(_ key: String, _ language: AppLanguage) -> String {
        switch (key, language) {
        case ("use_it_or_lose_it", .chinese): "用掉，否则失效"
        case ("expires_today_message", .chinese): "有一张储备重置今天过期。如有重要任务排队，建议过期前使用。"
        case ("expiry_warning", .chinese): "过期提醒"
        case ("waiting_on_meters", .chinese): "等待额度数据"
        case ("waiting_on_meters_message", .chinese): "已看到重置储备，但 Codex 用量窗口还没加载。"
        case ("refresh_after_sign_in", .chinese): "Codex 登录后刷新"
        case ("no_reset_cushion", .chinese): "没有重置缓冲"
        case ("no_reset_cushion_message", .chinese): "当前没有可用储备重置，请留意本周额度。"
        case ("let_5h_refill", .chinese): "等 5 小时额度恢复"
        case ("let_5h_refill_message", .chinese): "本周余量还可以，短窗口也快恢复，先保留重置。"
        case ("deadline_call", .chinese): "按截止期限判断"
        case ("deadline_call_message", .chinese): "短窗口紧张但本周余量充足；只有真实工作被挡住时才用重置。"
        case ("five_hour_nearly_empty", .chinese): "5 小时额度将尽"
        case ("go_burn_tokens", .chinese): "可以消耗一些额度"
        case ("go_burn_tokens_message", .chinese): "你有储备重置，本周额度偏低，距离刷新还有几天。"
        case ("green_light_with_brakes", .chinese): "可以用，但别浪费"
        case ("green_light_with_brakes_message", .chinese): "如果 Codex 阻塞真实工作，使用重置是合理的；不要只为清空仪表而消耗。"
        case ("hold_that_reset", .chinese): "保留这次重置"
        case ("hold_that_reset_message", .chinese): "本周余量健康，下次刷新也比较近。"
        case ("cruise_mode", .chinese): "正常使用"
        case ("cruise_mode_message", .chinese): "继续工作。大批量运行前再检查一次。"
        case ("use_it_or_lose_it", _): "Use it or lose it"
        case ("expires_today_message", _): "A banked reset expires today. If useful work is queued, spend it before it disappears."
        case ("expiry_warning", _): "Expiry warning"
        case ("waiting_on_meters", _): "Waiting on meters"
        case ("waiting_on_meters_message", _): "Reset stash is visible, but Codex usage windows are not loaded yet."
        case ("refresh_after_sign_in", _): "Refresh after Codex signs in"
        case ("no_reset_cushion", _): "No reset cushion"
        case ("no_reset_cushion_message", _): "No banked reset is available, so keep an eye on the weekly meter."
        case ("let_5h_refill", _): "Let the 5H tank refill"
        case ("let_5h_refill_message", _): "Weekly room is still decent and the short window is close. Save the reset."
        case ("deadline_call", _): "Deadline call"
        case ("deadline_call_message", _): "The short window is tight but weekly runway is healthy. Spend a reset only if real work is blocked."
        case ("five_hour_nearly_empty", _): "5H nearly empty"
        case ("go_burn_tokens", _): "Go burn some tokens"
        case ("go_burn_tokens_message", _): "You have resets banked, weekly room is thin, and refresh is days away."
        case ("green_light_with_brakes", _): "Green light, with brakes"
        case ("green_light_with_brakes_message", _): "If Codex blocks real work, spending a reset makes sense. Do not burn it just to tidy the meter."
        case ("hold_that_reset", _): "Hold that reset"
        case ("hold_that_reset_message", _): "Weekly room is healthy and the next refresh is close."
        case ("cruise_mode", _): "Cruise mode"
        case ("cruise_mode_message", _): "Keep working. Re-check before a big run."
        default: key
        }
    }
}

private struct ResetAdvicePanel: View {
    var advice: ResetSpendAdvice
    var theme: AppThemeColor

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: advice.systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(advice.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(advice.title)
                        .font(.system(size: 15, weight: .bold))
                    Text(advice.detail)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(advice.color, in: Capsule())
                }
                Text(advice.message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(advice.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(advice.color.opacity(0.22), lineWidth: 0.5)
        }
    }
}

private struct DashboardKPI: View {
    var title: String
    var value: String
    var delta: String
    var subtitle: String
    var systemImage: String
    var marker: Color?
    var accent: Color
    var theme: AppThemeColor

    init(title: String, value: String, delta: String, subtitle: String, systemImage: String, marker: Color? = nil, accent: Color, theme: AppThemeColor) {
        self.title = title
        self.value = value
        self.delta = delta
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.marker = marker
        self.accent = accent
        self.theme = theme
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(accent.opacity(0.12))
                .offset(x: 6, y: 14)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 22, height: 22)
                        .background(accent.opacity(0.12), in: Circle())
                    if let marker {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(marker)
                            .frame(width: 7, height: 7)
                    }
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                }
                Text(value)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                HStack(spacing: 8) {
                    Text(delta)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.green.opacity(0.12), in: Capsule())
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(
            LinearGradient(colors: [AgentBarDesign.panelHighlight, accent.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .agentBarPanel(cornerRadius: 16)
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
        .agentBarPanel()
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
        .agentBarPanel()
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

    private let calloutSize = CGSize(width: 238, height: 126)

    var body: some View {
        GeometryReader { proxy in
            if bars.isEmpty {
                EmptyPanelMessage(L.text("no_usage_events", language))
                    .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                let tokenMax = max(1, bars.map(tokenValue).max() ?? 0)
                let costMax = max(0.0001, bars.map(costValue).max() ?? 0)
                let plotHeight = max(0, proxy.size.height - 30)
                let leftAxisWidth: CGFloat = 52
                let rightAxisWidth: CGFloat = 56
                ZStack(alignment: .top) {
                    VStack(spacing: 4) {
                        HStack(alignment: .bottom, spacing: 8) {
                            VStack(alignment: .trailing) {
                                Text(tokenAxisText(tokenMax))
                                Spacer()
                                Text(tokenAxisText(tokenMax / 2))
                                Spacer()
                                Text("0")
                            }
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: leftAxisWidth - 8, height: max(1, proxy.size.height - 24))

                            GeometryReader { plotProxy in
                                ZStack {
                                    VStack {
                                        Divider()
                                        Spacer()
                                        Divider()
                                        Spacer()
                                        Divider()
                                    }
                                    .opacity(0.45)

                                    chartArea(
                                        size: CGSize(width: plotProxy.size.width, height: plotHeight),
                                        values: bars.map(tokenValue),
                                        maximum: tokenMax,
                                        color: theme.primary,
                                        showsFill: true
                                    )
                                    chartArea(
                                        size: CGSize(width: plotProxy.size.width, height: plotHeight),
                                        values: bars.map(costValue),
                                        maximum: costMax,
                                        color: .orange,
                                        showsFill: false
                                    )
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

                            VStack(alignment: .leading) {
                                Text(costAxisText(costMax))
                                Spacer()
                                Text(costAxisText(costMax / 2))
                                Spacer()
                                Text("$0")
                            }
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: rightAxisWidth, height: max(1, proxy.size.height - 24))
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
                        .padding(.leading, leftAxisWidth)
                        .padding(.trailing, rightAxisWidth + 8)
                    }

                    if let hoveredBar, let hoverLocation {
                        let tooltipPosition = ChartTooltipPlacement.position(cursor: hoverLocation, calloutSize: calloutSize, plotSize: hoverPlotSize)
                        ChartHoverCallout(bar: hoveredBar, language: language, theme: theme)
                            .frame(width: calloutSize.width, height: calloutSize.height)
                            .position(x: tooltipPosition.x + leftAxisWidth, y: tooltipPosition.y + 4)
                            .padding(.top, 4)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                            .allowsHitTesting(false)
                    }
                }
                .animation(nil, value: hoveredBarID)
            }
        }
    }

    private func chartArea(size: CGSize, values: [Double], maximum: Double, color: Color, showsFill: Bool) -> some View {
        let points = plotPoints(size: size, values: values, maximum: maximum)
        return ZStack {
            if showsFill {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: size.height))
                    points.forEach { path.addLine(to: $0) }
                    if let last = points.last {
                        path.addLine(to: CGPoint(x: last.x, y: size.height))
                        path.closeSubpath()
                    }
                }
                .fill(
                    LinearGradient(colors: [color.opacity(0.32), color.opacity(0.05)], startPoint: .top, endPoint: .bottom)
                )
            }
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                points.dropFirst().forEach { path.addLine(to: $0) }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            .shadow(color: color.opacity(0.32), radius: 4, y: 2)

            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(Color.white)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(color, lineWidth: 2))
                    .position(point)
            }
        }
    }

    private func plotPoints(size: CGSize, values: [Double], maximum: Double) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let step = values.count == 1 ? 0 : size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) * step,
                y: size.height - (size.height * CGFloat(value / max(maximum, 0.0001)))
            )
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

    private func tokenValue(_ bar: DailyUsageBar) -> Double {
        Double(bar.codexTokens + bar.claudeTokens)
    }

    private func costValue(_ bar: DailyUsageBar) -> Double {
        (bar.codexCostUSD as NSDecimalNumber).doubleValue + (bar.claudeCostUSD as NSDecimalNumber).doubleValue
    }

    private func tokenAxisText(_ value: Double) -> String {
        DisplayFormatters.compactTokenString(Int(value.rounded()), language: language)
    }

    private func costAxisText(_ value: Double) -> String {
        DisplayFormatters.costString(Decimal(value))
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
            metricRow("Codex", tokens: bar.codexTokens, cost: bar.codexCostUSD, color: theme.tertiary)
            metricRow("Claude", tokens: bar.claudeTokens, cost: bar.claudeCostUSD, color: theme.secondary)
            Divider()
            HStack {
                Text(L.text("total", language))
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(tokenText(bar.codexTokens + bar.claudeTokens))
                    Text(DisplayFormatters.costString(bar.codexCostUSD + bar.claudeCostUSD))
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
                .font(.system(size: 10, weight: .bold))
            }
        }
        .font(.system(size: 10, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 238)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
    }

    private func metricRow(_ title: String, tokens: Int, cost: Decimal, color: Color) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(tokenText(tokens))
                Text(DisplayFormatters.costString(cost))
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .font(.system(size: 10, weight: .semibold))
        }
    }

    private func tokenText(_ value: Int) -> String {
        "\(DisplayFormatters.compactTokenString(value, language: language)) \(L.text("tokens", language))"
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
            onHover?(swiftUILocation(for: event), bounds.size)
        }

        override func mouseEntered(with event: NSEvent) {
            onHover?(swiftUILocation(for: event), bounds.size)
        }

        override func mouseExited(with event: NSEvent) {
            onHover?(nil, bounds.size)
        }

        private func swiftUILocation(for event: NSEvent) -> CGPoint {
            ChartTooltipPlacement.swiftUILocation(
                fromAppKit: convert(event.locationInWindow, from: nil),
                plotHeight: bounds.height
            )
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
        .agentBarPanel(cornerRadius: 12)
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
        .agentBarPanel(cornerRadius: 14)
    }
}

private struct CurrentLimitSummaryStrip: View {
    var summary: CurrentLimitSummary
    var resetCreditsCount: Int
    var language: AppLanguage
    var theme: AppThemeColor

    var body: some View {
        HStack(spacing: 8) {
            MiniSummaryChip(
                title: localized("most_constrained"),
                value: summary.mostConstrainedAccount?.displayNameWithWorkspace(language: language) ?? "--",
                color: theme.quotaColor(remaining: summary.mostConstrainedAccount?.mostConstrainedRemainingPercent)
            )
            MiniSummaryChip(
                title: localized("lowest_5h"),
                value: DisplayFormatters.percentString(summary.lowestFiveHourRemaining),
                color: theme.quotaColor(remaining: summary.lowestFiveHourRemaining)
            )
            MiniSummaryChip(
                title: localized("lowest_weekly"),
                value: DisplayFormatters.percentString(summary.lowestWeeklyRemaining),
                color: theme.quotaColor(remaining: summary.lowestWeeklyRemaining)
            )
            MiniSummaryChip(
                title: localized("resets"),
                value: "\(resetCreditsCount)",
                color: theme.primary
            )
            MiniSummaryChip(
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
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(severityColor)
                .frame(width: 48, height: 48)
                .background(severityColor.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(localized("quota_pressure"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(severityColor)
                    Text(severityTitle)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(severityColor, in: Capsule())
                }
                Text(detailLine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.76))
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
                    ForEach(recommendedAccount.workspaceLines(language: language), id: \.self) { line in
                        Text(line)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let resetCredits = recommendedAccount.resetCredits, resetCredits.hasAvailableCredits {
                        Text(resetCredits.summaryLine(language: language))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            HStack(spacing: 6) {
                Text(localized("view_details"))
                Image(systemName: "chevron.right")
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(severityColor)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [severityColor.opacity(0.16), AgentBarDesign.panelHighlight, severityColor.opacity(0.06)], startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(severityColor.opacity(0.38), lineWidth: 1)
        )
        .shadow(color: severityColor.opacity(0.10), radius: 16, y: 8)
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
        let projected = pressure.projectedFiveHourExhaustion.map { DisplayFormatters.relativeString(for: $0, language: language) }
        let rotation = pressure.shouldTriggerRotation ? localized("rotation_ready") : localized("rotation_standby")
        if pressure.recommendationReason != nil, pressure.severity != .ok {
            return recommendationReason
        }
        if let projected {
            return "\(active) · \(localized("five_hour_exhausts")) \(projected) · \(rotation)"
        }
        return "\(active) · \(localized("five_hour_healthy")) · \(rotation)"
    }

    private var recommendationReason: String {
        guard let active = pressure.activeAccount, let recommended = pressure.recommendedAccount else {
            return pressure.recommendationReason ?? ""
        }
        let activeFive = DisplayFormatters.percentString(active.fiveHourWindow?.remainingPercent)
        let activeWeekly = DisplayFormatters.percentString(active.weeklyWindow?.remainingPercent)
        let recommendedFive = DisplayFormatters.percentString(recommended.fiveHourWindow?.remainingPercent)
        let recommendedWeekly = DisplayFormatters.percentString(recommended.weeklyWindow?.remainingPercent)
        switch language {
        case .chinese:
            return "当前 5H \(activeFive)，本周 \(activeWeekly)；\(recommended.displayName) 5H \(recommendedFive)，本周 \(recommendedWeekly)"
        case .english:
            return pressure.recommendationReason ?? "active 5H \(activeFive), weekly \(activeWeekly); \(recommended.displayName) 5H \(recommendedFive), weekly \(recommendedWeekly)"
        }
    }

    private func localized(_ key: String) -> String {
        switch (key, language) {
        case ("quota_pressure", .chinese): "额度压力"
        case ("view_details", .chinese): "查看详情"
        case ("best_account", .chinese): "推荐账号"
        case ("five_hour_exhausts", .chinese): "预计 5 小时额度耗尽于"
        case ("five_hour_healthy", .chinese): "5 小时额度暂无风险"
        case ("rotation_ready", .chinese): "自动轮换会触发"
        case ("rotation_standby", .chinese): "自动轮换待命"
        case ("quota_pressure", _): "Quota pressure"
        case ("view_details", _): "View details"
        case ("best_account", _): "Best account"
        case ("five_hour_exhausts", _): "5H may exhaust"
        case ("five_hour_healthy", _): "5H quota is healthy"
        case ("rotation_ready", _): "rotation will trigger"
        case ("rotation_standby", _): "rotation on standby"
        default: key
        }
    }
}

private struct QuotaETAPanel: View {
    var eta: QuotaETA
    var language: AppLanguage
    var theme: AppThemeColor

    var body: some View {
        Panel(title: localized("quota_eta")) {
            HStack(spacing: 10) {
                ForEach(eta.windows) { window in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("\(window.minutes)m")
                                .font(.system(size: 11, weight: .bold))
                            Spacer()
                            Text(DisplayFormatters.compactTokenString(window.tokens, language: language))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Divider()
                        etaLine(title: "5H", minutes: window.minutesUntilFiveHourExhaustion, color: theme.primary)
                        etaLine(title: "WK", minutes: window.minutesUntilWeeklyExhaustion, color: theme.tertiary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private func etaLine(title: String, minutes: Double?, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
            Spacer()
            Text(durationText(minutes))
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
        }
    }

    private func durationText(_ minutes: Double?) -> String {
        guard let minutes else { return "--" }
        if minutes < 1 { return localized("now") }
        if minutes < 60 { return "\(Int(ceil(minutes)))m" }
        let whole = Int(ceil(minutes))
        return "\(whole / 60)h \(whole % 60)m"
    }

    private func localized(_ key: String) -> String {
        switch (key, language) {
        case ("quota_eta", .chinese): "额度 ETA"
        case ("now", .chinese): "现在"
        case ("quota_eta", _): "Quota ETA"
        case ("now", _): "now"
        default: key
        }
    }
}

private struct QuotaCapacityHistoryPanel: View {
    var history: QuotaCapacityHistory
    var language: AppLanguage
    var theme: AppThemeColor

    private var chartSamples: [QuotaCapacitySample] {
        Array(history.samples.suffix(48))
    }

    var body: some View {
        if chartSamples.contains(where: { $0.estimatedFiveHourTotalTokens != nil || $0.estimatedWeeklyTotalTokens != nil }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    SummaryChip(
                        title: "5H",
                        value: tokenText(history.latestEstimate?.estimatedFiveHourTotalTokens),
                        color: theme.primary
                    )
                    SummaryChip(
                        title: localized("weekly"),
                        value: tokenText(history.latestEstimate?.estimatedWeeklyTotalTokens),
                        color: theme.tertiary
                    )
                    SummaryChip(
                        title: localized("samples"),
                        value: "\(history.samples.count)",
                        color: theme.secondary
                    )
                }

                QuotaCapacityLineChart(samples: chartSamples, language: language, theme: theme)
                    .frame(height: 188)

                HStack(spacing: 14) {
                    Spacer()
                    LegendItem(title: "5H", color: theme.primary)
                    LegendItem(title: localized("weekly"), color: theme.tertiary)
                }
            }
        } else {
            EmptyPanelMessage(localized("waiting"))
        }
    }

    private func tokenText(_ value: Int?) -> String {
        value.map { DisplayFormatters.compactTokenString($0, language: language) } ?? "--"
    }

    private func localized(_ key: String) -> String {
        switch (key, language) {
        case ("weekly", .chinese): "本周"
        case ("samples", .chinese): "样本"
        case ("waiting", .chinese): "等待至少两次同一额度窗口内的采样和 token 消耗后生成估算。"
        case ("weekly", _): "Weekly"
        case ("samples", _): "Samples"
        case ("waiting", _): "Waiting for two samples in the same quota window with token usage."
        default: key
        }
    }
}

private struct QuotaCapacityLineChart: View {
    var samples: [QuotaCapacitySample]
    var language: AppLanguage
    var theme: AppThemeColor
    @State private var hoveredSampleID: Date?
    @State private var hoverLocation: CGPoint?
    @State private var hoverPlotSize: CGSize = .zero

    private let calloutSize = CGSize(width: 218, height: 94)

    private var maxValue: Int {
        max(1, samples.flatMap { [$0.estimatedFiveHourTotalTokens, $0.estimatedWeeklyTotalTokens].compactMap { $0 } }.max() ?? 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let axisWidth: CGFloat = 52
            let labelHeight: CGFloat = 22
            let plotSize = CGSize(width: max(1, proxy.size.width - axisWidth), height: max(1, proxy.size.height - labelHeight))

            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .trailing) {
                        Text(tokenText(maxValue))
                        Spacer()
                        Text(tokenText(maxValue / 2))
                        Spacer()
                        Text("0")
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: axisWidth - 8, height: plotSize.height)

                    ZStack {
                        VStack {
                            Divider()
                            Spacer()
                            Divider()
                            Spacer()
                            Divider()
                        }
                        .opacity(0.45)

                        line(for: \.estimatedFiveHourTotalTokens, color: theme.primary, in: plotSize)
                        line(for: \.estimatedWeeklyTotalTokens, color: theme.tertiary, in: plotSize)
                    }
                    .frame(width: plotSize.width, height: plotSize.height)
                    .overlay {
                        PlotHoverTrackingView { location, size in
                            if let location {
                                hoveredSampleID = sampleID(at: location.x, plotWidth: size.width)
                                hoverLocation = location
                                hoverPlotSize = size
                            } else {
                                hoveredSampleID = nil
                                hoverLocation = nil
                            }
                        }
                    }
                    .overlay {
                        if let hoveredSample, let hoverLocation {
                            let tooltipPosition = ChartTooltipPlacement.position(
                                cursor: hoverLocation,
                                calloutSize: calloutSize,
                                plotSize: hoverPlotSize
                            )
                            QuotaCapacityHoverCallout(sample: hoveredSample, language: language, theme: theme)
                                .frame(width: calloutSize.width, height: calloutSize.height)
                                .position(tooltipPosition)
                                .allowsHitTesting(false)
                        }
                    }
                }

                HStack {
                    Text(dateText(samples.first?.capturedAt))
                    Spacer()
                    Text(dateText(samples.last?.capturedAt))
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, axisWidth)
            }
        }
    }

    private var hoveredSample: QuotaCapacitySample? {
        guard let hoveredSampleID else { return nil }
        return samples.first { $0.id == hoveredSampleID }
    }

    private func sampleID(at x: CGFloat, plotWidth: CGFloat) -> Date? {
        guard let index = ChartTooltipPlacement.barIndex(at: x, plotWidth: plotWidth, barCount: samples.count) else { return nil }
        guard samples.indices.contains(index) else { return nil }
        return samples[index].id
    }

    private func line(for keyPath: KeyPath<QuotaCapacitySample, Int?>, color: Color, in size: CGSize) -> some View {
        let points = plottedPoints(for: keyPath, in: size)
        return ZStack {
            Path { path in
                for (index, point) in points.enumerated() {
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .position(point)
            }
        }
    }

    private func plottedPoints(for keyPath: KeyPath<QuotaCapacitySample, Int?>, in size: CGSize) -> [CGPoint] {
        guard !samples.isEmpty else { return [] }
        let xDivisor = CGFloat(max(1, samples.count - 1))
        return samples.enumerated().compactMap { index, sample in
            guard let value = sample[keyPath: keyPath] else { return nil }
            let x = CGFloat(index) / xDivisor * size.width
            let y = size.height - (CGFloat(value) / CGFloat(maxValue) * size.height)
            return CGPoint(x: x, y: y)
        }
    }

    private func tokenText(_ value: Int) -> String {
        DisplayFormatters.compactTokenString(value, language: language)
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = language == .chinese ? Locale(identifier: "zh_Hans") : Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("MMM d HH")
        return formatter.string(from: date)
    }
}

private struct QuotaCapacityHoverCallout: View {
    var sample: QuotaCapacitySample
    var language: AppLanguage
    var theme: AppThemeColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateText(sample.capturedAt))
                .font(.system(size: 11, weight: .bold))
            metricRow("5H", value: sample.estimatedFiveHourTotalTokens, color: theme.primary)
            metricRow(localized("weekly"), value: sample.estimatedWeeklyTotalTokens, color: theme.tertiary)
            Divider()
            HStack {
                Text(localized("sample_usage"))
                Spacer()
                Text(DisplayFormatters.compactTokenString(sample.tokensSincePreviousSample, language: language))
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
            }
        }
        .font(.system(size: 10, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
    }

    private func metricRow(_ title: String, value: Int?, color: Color) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
            Spacer()
            Text(value.map { DisplayFormatters.compactTokenString($0, language: language) } ?? "--")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
        }
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language == .chinese ? Locale(identifier: "zh_Hans") : Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("yMMMd HH:mm")
        return formatter.string(from: date)
    }

    private func localized(_ key: String) -> String {
        switch (key, language) {
        case ("weekly", .chinese): "本周"
        case ("sample_usage", .chinese): "样本消耗"
        case ("weekly", _): "Weekly"
        case ("sample_usage", _): "Sample usage"
        default: key
        }
    }
}

private struct RapidUsageAlertPanel: View {
    var alert: RapidUsageAlert
    var language: AppLanguage
    var theme: AppThemeColor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.orange)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(localized("rapid_burn"))
                    .font(.system(size: 13, weight: .bold))
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int((alert.todayShare * 100).rounded()))%")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(theme.primary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.orange.opacity(0.22), lineWidth: 0.5)
        )
    }

    private var detail: String {
        let recent = DisplayFormatters.compactTokenString(alert.recentTokens, language: language)
        let total = DisplayFormatters.compactTokenString(alert.todayTokens, language: language)
        return switch language {
        case .chinese: "最近 10 分钟 \(recent) / 今日 \(total) tokens"
        case .english: "\(recent) of \(total) tokens in the last 10 minutes"
        }
    }

    private func localized(_ key: String) -> String {
        switch (key, language) {
        case ("rapid_burn", .chinese): "快速消耗提醒"
        case ("rapid_burn", _): "Rapid usage burn"
        default: key
        }
    }
}

private struct TopUsagePanel: View {
    var breakdown: TopUsageBreakdown
    var selectedSessionLabel: String?
    var language: AppLanguage
    var theme: AppThemeColor
    var onSelectSession: (String) -> Void

    var body: some View {
        if breakdown.sessions.isEmpty && breakdown.projects.isEmpty && breakdown.days.isEmpty && breakdown.models.isEmpty {
            EmptyPanelMessage(L.text("no_usage_data", language))
        } else {
            VStack(spacing: 12) {
                topSection(title: localized("sessions"), rows: breakdown.sessions, color: theme.primary, showsLastUsedAt: true, isSelectable: true)
                topSection(title: localized("projects"), rows: breakdown.projects, color: theme.tertiary)
                topSection(title: localized("days"), rows: breakdown.days, color: theme.secondary)
                topSection(title: localized("models"), rows: breakdown.models, color: theme.primary)
            }
        }
    }

    @ViewBuilder
    private func topSection(title: String, rows: [TopUsageRow], color: Color, showsLastUsedAt: Bool = false, isSelectable: Bool = false) -> some View {
        if rows.isEmpty {
            EmptyPanelMessage(L.text("no_usage_data", language))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                ForEach(rows.prefix(3)) { row in
                    Button {
                        if isSelectable {
                            onSelectSession(row.label)
                        }
                    } label: {
                        topRow(row, color: color, showsLastUsedAt: showsLastUsedAt, isSelected: isSelectable && selectedSessionLabel == row.label)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isSelectable)
                    .pointingHandCursor(enabled: isSelectable)
                }
            }
        }
    }

    private func topRow(_ row: TopUsageRow, color: Color, showsLastUsedAt: Bool, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if showsLastUsedAt, let lastUsedAt = row.lastUsedAt {
                    Text("\(localized("latest")) \(DisplayFormatters.relativeString(for: lastUsedAt, language: language))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(DisplayFormatters.compactTokenString(row.tokens, language: language))
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                if let estimatedCostUSD = row.estimatedCostUSD {
                    Text(DisplayFormatters.costString(estimatedCostUSD))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Text("\(Int((row.share * 100).rounded()))%")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, isSelected ? 7 : 0)
        .padding(.vertical, isSelected ? 5 : 0)
        .background(isSelected ? color.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
    }

    private func localized(_ key: String) -> String {
        switch (key, language) {
        case ("sessions", .chinese): "会话"
        case ("projects", .chinese): "项目"
        case ("days", .chinese): "日期"
        case ("models", .chinese): "模型"
        case ("latest", .chinese): "最新"
        case ("sessions", _): "Sessions"
        case ("projects", _): "Projects"
        case ("days", _): "Days"
        case ("models", _): "Models"
        case ("latest", _): "Latest"
        default: key
        }
    }
}

private struct SessionDrilldownPanel: View {
    var detail: SessionDrilldown?
    var language: AppLanguage
    var theme: AppThemeColor

    var body: some View {
        if let detail {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detail.title)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                        Text(subtitle(for: detail))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(DisplayFormatters.compactTokenString(detail.totalTokens, language: language))
                            .font(.system(size: 14, weight: .bold))
                            .monospacedDigit()
                        Text(detail.estimatedCostUSD.map(DisplayFormatters.costString) ?? L.text("no_cost_data", language))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(detail.models) { row in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.primary)
                            .frame(width: 7, height: 7)
                        Text(row.label)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        Text(DisplayFormatters.compactTokenString(row.tokens, language: language))
                            .font(.system(size: 12, weight: .bold))
                            .monospacedDigit()
                        Text("\(Int((row.share * 100).rounded()))%")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        } else {
            EmptyPanelMessage(localized("select_session"))
        }
    }

    private func subtitle(for detail: SessionDrilldown) -> String {
        let project = detail.projectName ?? localized("unknown_project")
        let latest = detail.lastUsedAt.map { DisplayFormatters.relativeString(for: $0, language: language) } ?? "--"
        return "\(project) · \(localized("latest")) \(latest)"
    }

    private func localized(_ key: String) -> String {
        switch (key, language) {
        case ("select_session", .chinese): "选择一个高消耗会话查看模型分布。"
        case ("unknown_project", .chinese): "未知项目"
        case ("latest", .chinese): "最新"
        case ("select_session", _): "Select a top session to inspect model usage."
        case ("unknown_project", _): "Unknown project"
        case ("latest", _): "Latest"
        default: key
        }
    }
}

private struct AccountHealthCenterPanel: View {
    var health: AccountHealthCenter
    var language: AppLanguage
    var theme: AppThemeColor
    var onLogin: (String) -> Void
    var onRemove: (String) -> Void
    var onRefresh: () -> Void

    var body: some View {
        if health.rows.isEmpty {
            EmptyPanelMessage(localized("healthy"))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(health.rows) { row in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: iconName(for: row))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(color(for: row))
                            .frame(width: 16)
                            .padding(.top, 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                            Text(row.detail)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(row.workspaceLines, id: \.self) { line in
                                Text(line)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        actions(for: row)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private func actions(for row: AccountHealthCenter.Row) -> some View {
        switch row.kind {
        case .login:
            if let accountID = row.accountID {
                HStack(spacing: 6) {
                    Button(localized("login")) {
                        onLogin(accountID)
                    }
                    .controlSize(.small)
                    .pointingHandCursor()
                    Button(role: .destructive) {
                        onRemove(accountID)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(.red)
                    .help(localized("remove"))
                    .pointingHandCursor()
                }
            }
        case .dataSource:
            Button(localized("refresh")) {
                onRefresh()
            }
            .controlSize(.small)
            .pointingHandCursor()
        }
    }

    private func iconName(for row: AccountHealthCenter.Row) -> String {
        switch row.kind {
        case .login: "person.crop.circle.badge.exclamationmark"
        case .dataSource: "externaldrive.badge.exclamationmark"
        }
    }

    private func color(for row: AccountHealthCenter.Row) -> Color {
        switch row.severity {
        case .critical: .red
        case .warning: .orange
        case .ok: theme.primary
        }
    }

    private func localized(_ key: String) -> String {
        switch (key, language) {
        case ("healthy", .chinese): "账号和数据源暂无需要处理的问题。"
        case ("login", .chinese): "登录"
        case ("remove", .chinese): "删除账号"
        case ("refresh", .chinese): "刷新"
        case ("healthy", _): "No account or source issue needs action."
        case ("login", _): "Login"
        case ("remove", _): "Remove account"
        case ("refresh", _): "Refresh"
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
        let cost = anomaly.estimatedCostUSD.map { " · \(DisplayFormatters.costString($0))" } ?? ""
        switch language {
        case .chinese:
            return "\(tokens) \(L.text("tokens", language))\(cost)，近期基线 \(baseline)"
        case .english:
            return "\(tokens) \(L.text("tokens", language))\(cost), baseline \(baseline)"
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
                .help(L.text(isExpanded ? "hide_full_text" : "show_full_text", language))
                .accessibilityLabel(L.text(isExpanded ? "hide_full_text" : "show_full_text", language))
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
        let refreshed = DisplayFormatters.relativeString(for: row.refreshedAt, language: language)
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

private struct ResetExpiryRowData: Identifiable {
    var account: String
    var index: Int
    var expiresAt: Date?

    var id: String { "\(account)-\(index)-\(expiresAt?.timeIntervalSince1970 ?? 0)" }
}

private struct ResetExpiryRow: View {
    var row: ResetExpiryRowData
    var language: AppLanguage
    var theme: AppThemeColor

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(row.account) · \(L.text("reset", language)) \(row.index)")
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(badge)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var detail: String {
        guard let expiresAt = row.expiresAt else { return L.text("expiry_date_unavailable", language) }
        return "\(DisplayFormatters.shortDateTimeString(for: expiresAt, language: language)) · \(DisplayFormatters.relativeString(for: expiresAt, language: language))"
    }

    private var badge: String {
        guard let expiresAt = row.expiresAt else { return L.text("unknown", language) }
        let seconds = expiresAt.timeIntervalSinceNow
        if seconds <= 0 { return L.text("expired", language) }
        if seconds <= 86_400 { return L.text("today", language) }
        if seconds <= 3 * 86_400 { return L.text("soon", language) }
        if seconds <= 7 * 86_400 { return L.text("this_week", language) }
        return L.text("available", language)
    }

    private var iconName: String {
        guard let expiresAt = row.expiresAt else { return "checkmark.seal.fill" }
        return expiresAt.timeIntervalSinceNow <= 86_400 ? "exclamationmark.octagon.fill" : "checkmark.seal.fill"
    }

    private var color: Color {
        guard let expiresAt = row.expiresAt else { return .secondary }
        let seconds = expiresAt.timeIntervalSinceNow
        if seconds <= 86_400 { return .red }
        if seconds <= 3 * 86_400 { return .orange }
        return theme.primary
    }
}

private struct ResetExpiryDisplayGroupView: View {
    var group: UsageAccountDisplayGroup
    var language: AppLanguage
    var theme: AppThemeColor

    var body: some View {
        if group.isGrouped {
            VStack(alignment: .leading, spacing: 6) {
                displayGroupHeader
                ForEach(group.accounts) { account in
                    ForEach(rows(for: account)) { row in
                        ResetExpiryRow(row: row, language: language, theme: theme)
                            .padding(.leading, 12)
                    }
                }
            }
        } else if let account = group.accounts.first {
            ForEach(rows(for: account)) { row in
                ResetExpiryRow(row: row, language: language, theme: theme)
            }
        }
    }

    private var displayGroupHeader: some View {
        HStack(spacing: 6) {
            Text(group.title)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
            Text("\(group.accounts.count) \(L.text("workspaces", language))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 2)
    }

    private func rows(for account: UsageAccount) -> [ResetExpiryRowData] {
        (account.resetCredits?.resets ?? []).enumerated().map { index, reset in
            ResetExpiryRowData(account: account.displayNameWithWorkspace(language: language), index: index + 1, expiresAt: reset.expiresAt)
        }
    }
}

private struct AccountAvatar: View {
    var text: String
    var color: Color
    var size: CGFloat

    var body: some View {
        Text(initial)
            .font(.system(size: max(12, size * 0.42), weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [color, color.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Circle()
            )
            .shadow(color: color.opacity(0.24), radius: 8, y: 4)
    }

    private var initial: String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).first ?? "A").uppercased()
    }
}

private struct SidebarAccountPopover: View {
    var account: UsageAccount?
    var language: AppLanguage
    var theme: AppThemeColor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let account {
                HStack(spacing: 10) {
                    AccountAvatar(text: account.displayName, color: theme.primary, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.displayName)
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)
                        Text(account.accountTypeLine(language: language))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                infoRow(L.text("current_account", language), account.isActive ? localized("yes") : localized("no"))
                if let username = account.username, !username.isEmpty {
                    infoRow("Username", username)
                }
                if let maskedEmail = account.maskedEmail, !maskedEmail.isEmpty {
                    infoRow("Email", maskedEmail)
                }
                ForEach(account.workspaceLines(language: language, limit: 8), id: \.self) { line in
                    infoRow(L.text("workspace", language), line.replacingOccurrences(of: "\(L.text("workspace", language)): ", with: ""))
                }
                infoRow("5H", windowText(account.fiveHourWindow))
                infoRow(language == .chinese ? "本周" : "Weekly", windowText(account.weeklyWindow))
                if let resetCredits = account.resetCredits {
                    infoRow(L.text("resets", language), resetCredits.summaryLine(language: language))
                }
                infoRow(L.text("total_tokens", language), DisplayFormatters.compactTokenString(account.tokens.total, language: language))
                infoRow(L.text("cost", language), account.estimatedCostUSD.map(DisplayFormatters.costString) ?? L.text("no_cost_data", language))
                infoRow(L.text("last_activity", language), account.lastActivityLine(language: language).replacingOccurrences(of: "\(L.text("last_activity", language)): ", with: ""))
                infoRow(language == .chinese ? "数据源" : "Source", account.sourceDescription)
            } else {
                Text(L.text("current_account", language))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 318, alignment: .leading)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func windowText(_ window: UsageWindow?) -> String {
        guard let window else { return "--" }
        let reset = window.resetsAt.map { DisplayFormatters.relativeString(for: $0, language: language) } ?? "--"
        return "\(DisplayFormatters.percentString(window.remainingPercent)) · \(reset)"
    }

    private func localized(_ key: String) -> String {
        switch (key, language) {
        case ("yes", .chinese): "是"
        case ("no", .chinese): "否"
        case ("yes", _): "Yes"
        case ("no", _): "No"
        default: key
        }
    }
}

private struct SummaryChip: View {
    var title: String
    var value: String
    var color: Color
    var systemImage: String? = nil
    var progress: Double? = nil

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color.opacity(0.14))
                .frame(width: 46, height: 46)
                .overlay {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(color)
                    } else {
                        Circle()
                            .stroke(color.opacity(0.18), lineWidth: 5)
                        Circle()
                            .trim(from: 0, to: min(1, max(0, (progress ?? 0) / 100)))
                            .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .agentBarPanel(cornerRadius: 14)
    }
}

private struct MiniSummaryChip: View {
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

private struct AccountLimitDisplayGroupView: View {
    var group: UsageAccountDisplayGroup
    var language: AppLanguage
    var theme: AppThemeColor
    var switchingAccountID: String?
    var onSwitch: (UsageAccount) -> Void
    var onLogin: (UsageAccount) -> Void

    var body: some View {
        if group.isGrouped {
            VStack(alignment: .leading, spacing: 6) {
                displayGroupHeader
                ForEach(group.accounts) { account in
                    AccountLimitGroupView(
                        account: account,
                        language: language,
                        theme: theme,
                        isSwitching: switchingAccountID == account.id,
                        onSwitch: { onSwitch(account) },
                        onLogin: { onLogin(account) }
                    )
                    .padding(.leading, 12)
                }
            }
        } else if let account = group.accounts.first {
            AccountLimitGroupView(
                account: account,
                language: language,
                theme: theme,
                isSwitching: switchingAccountID == account.id,
                onSwitch: { onSwitch(account) },
                onLogin: { onLogin(account) }
            )
        }
    }

    private var displayGroupHeader: some View {
        HStack(spacing: 6) {
            Text(group.title)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
            Text("\(group.accounts.count) \(L.text("workspaces", language))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 2)
    }
}

private struct AccountLimitGroupView: View {
    var account: UsageAccount
    var language: AppLanguage
    var theme: AppThemeColor
    var isSwitching: Bool
    var onSwitch: () -> Void
    var onLogin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                AccountAvatar(text: account.displayName, color: account.isActive ? theme.primary : theme.secondary, size: 34)
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
                    ForEach(account.workspaceLines(language: language), id: \.self) { line in
                        Text(line)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if account.needsLogin {
                    Button {
                        onLogin()
                    } label: {
                        Label(L.text("login_account", language), systemImage: "person.crop.circle.badge.exclamationmark")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.red)
                    .pointingHandCursor()
                } else if !account.isActive {
                    Button {
                        onSwitch()
                    } label: {
                        if isSwitching {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(L.text("use_account", language), systemImage: "arrow.triangle.2.circlepath")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(theme.primary)
                    .disabled(isSwitching)
                    .pointingHandCursor(enabled: !isSwitching)
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(account.service.rawValue)
                            .font(.system(size: 10, weight: .bold))
                        Text(account.accountTypeValue(language: language))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let warning = account.loginWarningLine(language: language) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
        .padding(11)
        .background(account.needsLogin ? Color.red.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(account.needsLogin ? Color.red.opacity(0.70) : (account.isActive ? theme.primary.opacity(0.25) : Color.primary.opacity(0.06)), lineWidth: account.needsLogin ? 1.5 : 1)
        }
    }

    private var accountDetailLine: String {
        let identity = account.username ?? account.maskedEmail ?? account.sourceDescription
        if let lastUpdated = account.lastUpdated {
            return "\(identity) · \(DisplayFormatters.relativeString(for: lastUpdated, language: language))"
        }
        return identity
    }
}

private struct SettingsAccountDropdown: View {
    var accounts: [UsageAccount]
    var currentAccount: UsageAccount?
    var language: AppLanguage
    var onRemove: (UsageAccount) -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    SettingsAccountSummary(account: currentAccount, language: language)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(accounts) { account in
                        SettingsAccountDeleteRow(account: account, language: language) {
                            onRemove(account)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsAccountSummary: View {
    var account: UsageAccount?
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(L.text("current_account", language))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(account?.displayName ?? "--")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if let workspaceLine = account?.workspaceLine(language: language) {
                    Text(workspaceLine)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

private struct SettingsAccountDeleteRow: View {
    var account: UsageAccount
    var language: AppLanguage
    var onRemove: () -> Void
    @State private var isConfirmingRemoval = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if account.isActive {
                        Text(L.text("current", language))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(accountIdentityLine)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ForEach(account.workspaceLines(language: language), id: \.self) { line in
                    Text(line)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button(role: .destructive) {
                isConfirmingRemoval = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(.red)
            .help(L.text("remove_account", language))
            .pointingHandCursor()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .confirmationDialog(L.text("remove_account", language), isPresented: $isConfirmingRemoval) {
            Button(L.text("remove_account", language), role: .destructive) {
                onRemove()
            }
        } message: {
            Text(L.text("remove_account_confirmation", language))
        }
    }

    private var accountIdentityLine: String {
        account.username ?? account.maskedEmail ?? account.sourceDescription
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
            .agentBarPanel()
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

private struct CodexRotationThresholdControl: View {
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

            Stepper("", value: $threshold, in: 1...100, step: 1)
                .labelsHidden()
        }
        .disabled(!isEnabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L.text("codex_rotation_threshold", language))
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
    var id: String { "\(service.rawValue)-\(isHeader ? "header" : name)" }
    var service: UsageService
    var name: String
    var input: Int
    var output: Int
    var cost: Decimal?
    var isHeader: Bool
    var dividerAfter: Bool
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
