import AppKit
import SwiftUI

struct StatisticsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var updates: AppUpdateStore
    @State private var serviceFilter: DashboardServiceFilter = .all
    @State private var viewMode: DashboardViewMode = .overview
    @State private var topTab: DashboardTopTab
    @State private var currentLimitsTopInContent: CGFloat = 0

    private static let dashboardContentTopPadding: CGFloat = 12
    private static let dashboardContentBottomPadding: CGFloat = 26
    private static let currentLimitsMinHeight: CGFloat = 240
    private static let dashboardContentCoordinateSpace = "dashboardContent"

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
                topChrome

                if topTab == .usage {
                    GeometryReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            dashboardContent(viewportHeight: proxy.size.height)
                                .coordinateSpace(name: Self.dashboardContentCoordinateSpace)
                                .padding(.top, Self.dashboardContentTopPadding)
                                .padding(.horizontal, 22)
                                .padding(.bottom, Self.dashboardContentBottomPadding)
                        }
                    }
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
            sidebarGroup(title: L.text("service", store.language)) {
                sidebarItem(L.text("all", store.language), active: serviceFilter == .all, tint: nil) {
                    serviceFilter = .all
                }
                sidebarItem(L.text("openai", store.language), active: serviceFilter == .codex, service: .codex, tint: settings.themeColor.tertiary) {
                    serviceFilter = .codex
                }
                if hasClaudeData {
                    sidebarItem(L.text("anthropic", store.language), active: serviceFilter == .claude, tint: settings.themeColor.secondary) {
                        serviceFilter = .claude
                    }
                }
            }

            sidebarGroup(title: L.text("view", store.language)) {
                sidebarItem(L.text("overview", store.language), systemImage: "rectangle.split.2x2", active: viewMode == .overview) {
                    viewMode = .overview
                }
                sidebarItem(L.text("timeline", store.language), systemImage: "chart.line.uptrend.xyaxis", active: viewMode == .timeline, enabled: false) {}
                sidebarItem(L.text("details", store.language), systemImage: "list.bullet", active: viewMode == .details, enabled: false) {}
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 58)
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
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.86)
        .glassPanel(cornerRadius: 8, interactive: enabled)
    }

    private var topChrome: some View {
        VStack(spacing: 9) {
            DashboardTopTabBar(selection: $topTab, language: store.language, theme: settings.themeColor)
                .padding(.top, 12)

            if topTab == .usage {
                HStack {
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
                        .frame(width: 130)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .glassPanel(cornerRadius: 12, interactive: true)

                    dashboardRefreshButton
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(.thinMaterial)
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
                ZStack {
                    if store.isManualRefreshFeedbackVisible {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: 12, height: 12)
            }
            .foregroundStyle(settings.themeColor.primary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(L.text("refresh", store.language)))
        }
        .buttonStyle(.plain)
        .glassPanel(cornerRadius: 10, interactive: true)
        .help(L.text("refresh", store.language))
    }

    @ViewBuilder
    private func dashboardContent(viewportHeight: CGFloat) -> some View {
        dashboardContentStack(currentLimitsHeight: currentLimitsHeight(viewportHeight: viewportHeight))
            .onPreferenceChange(CurrentLimitsTopPreferenceKey.self) { top in
                guard abs(currentLimitsTopInContent - top) > 0.5 else { return }
                currentLimitsTopInContent = max(0, top)
            }
    }

    private func currentLimitsHeight(viewportHeight: CGFloat) -> CGFloat {
        let availableHeight = viewportHeight
            - Self.dashboardContentTopPadding
            - currentLimitsTopInContent
            - Self.dashboardContentBottomPadding
        return max(Self.currentLimitsMinHeight, availableHeight.rounded(.down))
    }

    private func dashboardContentStack(currentLimitsHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !store.hasLoadedAccountInformation {
                LoadingAccountPanel(
                    title: L.text("loading_account_info", store.language),
                    subtitle: L.text("loading_account_info_subtitle", store.language)
                )
            }

            LazyVGrid(columns: kpiColumns, spacing: 12) {
                DashboardKPI(title: L.text("total_tokens", store.language), value: DisplayFormatters.compactTokenString(summary.totalTokens, language: store.language), delta: "↓ 23.6%", accent: .primary, theme: settings.themeColor)
                DashboardKPI(title: L.text("total_cost", store.language), value: costText(summary.estimatedCostUSD), delta: "↓ 4.0%", accent: .primary, theme: settings.themeColor)
                DashboardKPI(title: "OpenAI", value: serviceCostText(.codex), delta: serviceShareText(.codex), marker: settings.themeColor.tertiary, accent: settings.themeColor.tertiary, theme: settings.themeColor)
                if hasClaudeData {
                    DashboardKPI(title: "Anthropic", value: serviceCostText(.claudeCode), delta: serviceShareText(.claudeCode), marker: settings.themeColor.secondary, accent: settings.themeColor.secondary, theme: settings.themeColor)
                }
            }

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

            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 14) {
                    Panel(title: L.text("by_service", store.language)) {
                        serviceMixRows
                    }
                    Panel(title: L.text("by_model", store.language)) {
                        modelRows
                    }
                }
                .frame(minWidth: 360, maxWidth: .infinity, alignment: .top)

                FillToBottomPanel(
                    title: L.text("current_limits", store.language),
                    height: currentLimitsHeight
                ) {
                    currentLimitsRows
                }
                .frame(minWidth: 360, maxWidth: .infinity, alignment: .top)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: CurrentLimitsTopPreferenceKey.self,
                            value: proxy.frame(in: .named(Self.dashboardContentCoordinateSpace)).minY
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
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
                        Button(L.text("login_claude", store.language)) {
                            store.openLogin(for: .claudeCode)
                        }
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
                SettingsRow(title: L.text("check_for_updates", store.language), subtitle: updates.status.localizedMessage(language: store.language)) {
                    HStack(spacing: 10) {
                        Button(L.text("check_for_updates", store.language)) {
                            Task { await updates.checkForUpdates() }
                        }
                        .disabled(!updates.canCheckForUpdates)
                        if updates.status.isBusy {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .settingsControl(width: SettingsControlLayout.widePickerWidth)
                }
                if updates.canInstallDownloadedUpdate {
                    SettingsRow(title: L.text("install_and_restart", store.language), subtitle: L.text("update_install_subtitle", store.language)) {
                        Button(L.text("install_and_restart", store.language)) {
                            updates.installDownloadedUpdate()
                        }
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

    private var filteredPoints: [UsagePoint] {
        store.points.filter { point in
            switch serviceFilter {
            case .all: true
            case .codex: point.service == .codex
            case .claude: point.service == .claudeCode
            }
        }
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

    private var kpiColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: hasClaudeData ? 4 : 3)
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
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(accounts) { account in
                        AccountLimitGroupView(account: account, language: store.language, theme: settings.themeColor)
                    }
                }
            }
        }
    }

    private var currentLimitAccounts: [UsageAccount] {
        store.accounts.filter { account in
            account.fiveHourWindow != nil || account.weeklyWindow != nil
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

private enum DashboardServiceFilter: Hashable {
    case all
    case codex
    case claude
}

private enum DashboardViewMode: Hashable {
    case overview
    case timeline
    case details
}

private struct DashboardTopTabBar: View {
    @Binding var selection: DashboardTopTab
    var language: AppLanguage
    var theme: AppThemeColor

    var body: some View {
        HStack(spacing: 3) {
            tabButton(.usage, title: L.text("usage_statistics", language))
            tabButton(.settings, title: L.text("settings", language))
        }
        .padding(3)
        .frame(height: 30)
        .glassPanel(cornerRadius: 12, interactive: true)
    }

    private func tabButton(_ tab: DashboardTopTab, title: String) -> some View {
        Button {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                selection = tab
            }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .frame(width: 70, height: 24)
                .foregroundStyle(selection == tab ? Color.white : Color.primary.opacity(0.74))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selection == tab ? theme.primary : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
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

private struct FillToBottomPanel<Content: View>: View {
    var title: String
    var height: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .dashboardPanel()
    }
}

private struct CurrentLimitsTopPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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

                                    HStack(alignment: .bottom, spacing: 15) {
                                        ForEach(bars) { bar in
                                            ZStack(alignment: .bottom) {
                                                VStack(spacing: 0) {
                                                    Rectangle()
                                                        .fill(theme.secondary)
                                                        .frame(height: plotHeight * CGFloat(bar.claudeTokens) / CGFloat(maxValue))
                                                    Rectangle()
                                                        .fill(theme.tertiary)
                                                        .frame(height: plotHeight * CGFloat(bar.codexTokens) / CGFloat(maxValue))
                                                }
                                                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                                                .frame(maxWidth: 28)
                                            }
                                            .frame(width: 32, height: plotHeight, alignment: .bottom)
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
        let barWidth: CGFloat = 32
        let spacing: CGFloat = 15
        let totalWidth = CGFloat(bars.count) * barWidth + CGFloat(max(0, bars.count - 1)) * spacing
        let leading = max(0, (plotWidth - totalWidth) / 2)
        let relativeX = x - leading
        guard relativeX >= 0, relativeX <= totalWidth else { return nil }
        let stride = barWidth + spacing
        let index = Int(relativeX / stride)
        guard bars.indices.contains(index) else { return nil }
        let barStart = CGFloat(index) * stride
        guard relativeX >= barStart, relativeX <= barStart + barWidth else { return nil }
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

private struct AccountLimitGroupView: View {
    var account: UsageAccount
    var language: AppLanguage
    var theme: AppThemeColor

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
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
                    Text(account.username ?? account.maskedEmail ?? account.sourceDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(account.service.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                UsageWindowGauge(title: L.text("five_hour", language), window: account.fiveHourWindow, language: language, theme: theme)
                UsageWindowGauge(title: L.text("weekly", language), window: account.weeklyWindow, language: language, theme: theme)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(account.lastActivityLine(language: language))
                Text(account.accountTypeLine(language: language))
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.86))
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
