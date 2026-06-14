import SwiftUI

struct StatisticsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject private var settings: SettingsStore
    @State private var serviceFilter: DashboardServiceFilter = .all
    @State private var viewMode: DashboardViewMode = .overview
    @State private var topTab: DashboardTopTab = .usage

    init(store: UsageStore) {
        self.store = store
        self.settings = store.settings
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 216)

            VStack(spacing: 0) {
                topChrome

                if topTab == .usage {
                    ScrollView(.vertical, showsIndicators: false) {
                        dashboardContent
                            .padding(.top, 12)
                            .padding(.horizontal, 22)
                            .padding(.bottom, 26)
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
        }
        .background(.regularMaterial)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            sidebarGroup(title: L.text("service", store.language)) {
                sidebarItem(L.text("all", store.language), active: serviceFilter == .all, tint: nil) {
                    serviceFilter = .all
                }
                sidebarItem(L.text("openai", store.language), active: serviceFilter == .codex, tint: DashboardStyle.codex) {
                    serviceFilter = .codex
                }
                if hasClaudeData {
                    sidebarItem(L.text("anthropic", store.language), active: serviceFilter == .claude, tint: DashboardStyle.claude) {
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
            .frame(height: 30)
            .background(active ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.86)
        .glassPanel(cornerRadius: 8, interactive: enabled)
    }

    private var topChrome: some View {
        VStack(spacing: 9) {
            DashboardTopTabBar(selection: $topTab, language: store.language)
                .padding(.top, 12)

            if topTab == .usage {
                HStack {
                    if store.isLoadingAccountInformation && store.hasLoadedAccountInformation {
                        LoadingStatusPill(message: L.text("refreshing_accounts", store.language))
                    }
                    Spacer()
                    DashboardRangeBar(selection: $store.selectedRange, language: store.language)

                    Button {
                        store.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .help(L.text("refresh", store.language))
                    .disabled(store.isRefreshing)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(.thinMaterial)
    }

    @ViewBuilder
    private var dashboardContent: some View {
        dashboardContentStack
    }

    private var dashboardContentStack: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !store.hasLoadedAccountInformation {
                LoadingAccountPanel(
                    title: L.text("loading_account_info", store.language),
                    subtitle: L.text("loading_account_info_subtitle", store.language)
                )
            }

            LazyVGrid(columns: kpiColumns, spacing: 12) {
                DashboardKPI(title: L.text("total_tokens", store.language), value: DisplayFormatters.compactTokenString(summary.totalTokens), delta: "↓ 23.6%", accent: .primary)
                DashboardKPI(title: L.text("total_cost", store.language), value: costText(summary.estimatedCostUSD), delta: "↓ 4.0%", accent: .primary)
                DashboardKPI(title: "OpenAI", value: serviceCostText(.codex), delta: serviceShareText(.codex), marker: DashboardStyle.codex, accent: DashboardStyle.codex)
                if hasClaudeData {
                    DashboardKPI(title: "Anthropic", value: serviceCostText(.claudeCode), delta: serviceShareText(.claudeCode), marker: DashboardStyle.claude, accent: DashboardStyle.claude)
                }
            }

            Panel(title: L.text("daily_usage", store.language)) {
                DashboardStackedBars(bars: displayBars, language: store.language)
                    .frame(height: 206)
                HStack(spacing: 14) {
                    Spacer()
                    LegendItem(title: "Codex", color: DashboardStyle.codex)
                    if hasClaudeData {
                        LegendItem(title: "Claude", color: DashboardStyle.claude)
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
                Panel(title: L.text("current_limits", store.language)) {
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
                    .frame(width: 180)
                }
            }

            SettingsGroup(title: L.text("refresh", store.language), subtitle: L.text("refresh_settings_subtitle", store.language)) {
                SettingsRow(title: L.text("refresh_interval", store.language), subtitle: L.text("refresh_interval_subtitle", store.language)) {
                    Picker("", selection: $settings.refreshInterval) {
                        Text("15s").tag(TimeInterval(15))
                        Text("30s").tag(TimeInterval(30))
                        Text("60s").tag(TimeInterval(60))
                        Text("5m").tag(TimeInterval(300))
                    }
                    .labelsHidden()
                    .frame(width: 120)
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
                    .frame(width: 140)
                }
            }
        }
        .frame(maxWidth: 860, alignment: .topLeading)
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
        return DisplayFormatters.costString(costs.reduce(0, +))
    }

    private func serviceShareText(_ service: UsageService) -> String {
        let total = max(1, summary.serviceBreakdown.values.reduce(0, +))
        let value = summary.serviceBreakdown[service, default: 0]
        return "\(Int((Double(value) / Double(total) * 100).rounded()))% \(L.text("share", store.language))"
    }

    private func costText(_ value: Double?) -> String {
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
                            Text(DisplayFormatters.compactTokenString(row.tokens) + " \(L.text("tokens", store.language))")
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
            let color = service == .codex ? DashboardStyle.codex : DashboardStyle.claude
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
                        AccountLimitGroupView(account: account, language: store.language)
                    }
                }
            }
            .frame(maxHeight: 360)
        }
    }

    private var currentLimitAccounts: [UsageAccount] {
        store.accounts.filter { account in
            account.fiveHourWindow != nil || account.weeklyWindow != nil
        }
        .sortedByActiveThenName()
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
                        Text("\(L.text("input_abbrev", store.language)) \(DisplayFormatters.compactTokenString(row.input))")
                        Text("\(L.text("output_abbrev", store.language)) \(DisplayFormatters.compactTokenString(row.output))")
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
                cost: costValues.isEmpty ? nil : costValues.reduce(0, +),
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

private enum DashboardTopTab: Hashable {
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

private enum DashboardStyle {
    static let codex = Color(red: 0.43, green: 0.43, blue: 0.46)
    static let claude = Color(red: 0.80, green: 0.47, blue: 0.34)
}

private struct DashboardTopTabBar: View {
    @Binding var selection: DashboardTopTab
    var language: AppLanguage

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
            selection = tab
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .frame(width: 70, height: 24)
                .foregroundStyle(selection == tab ? Color.white : Color.primary.opacity(0.74))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selection == tab ? Color.accentColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct DashboardRangeBar: View {
    @Binding var selection: UsageRange
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 2) {
            ForEach(UsageRange.allCases) { range in
                Button {
                    selection = range
                } label: {
                    Text(range.dashboardLabel(language))
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .frame(width: width(for: range), height: 24)
                        .foregroundStyle(selection == range ? Color.white : Color.primary.opacity(0.72))
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selection == range ? Color.accentColor : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .frame(height: 30)
        .glassPanel(cornerRadius: 12, interactive: true)
    }

    private func width(for range: UsageRange) -> CGFloat {
        switch range {
        case .last30Days, .custom:
            return language == .english ? 62 : 50
        case .thisMonth, .thisWeek, .thisYear, .yesterday:
            return language == .english ? 58 : 44
        default:
            return language == .english ? 50 : 40
        }
    }
}

private struct DashboardKPI: View {
    var title: String
    var value: String
    var delta: String
    var marker: Color?
    var accent: Color

    init(title: String, value: String, delta: String, marker: Color? = nil, accent: Color) {
        self.title = title
        self.value = value
        self.delta = delta
        self.marker = marker
        self.accent = accent
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
                    .foregroundStyle(.green)
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

private struct DashboardStackedBars: View {
    var bars: [DailyUsageBar]
    var language: AppLanguage

    var body: some View {
        GeometryReader { proxy in
            if bars.isEmpty {
                EmptyPanelMessage(L.text("no_usage_events", language))
                    .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                let maxValue = max(1, bars.map { $0.codexTokens + $0.claudeTokens }.max() ?? 1)
                HStack(alignment: .bottom, spacing: 15) {
                    ForEach(bars) { bar in
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(DashboardStyle.claude)
                                .frame(height: proxy.size.height * 0.82 * CGFloat(bar.claudeTokens) / CGFloat(maxValue))
                            Rectangle()
                                .fill(DashboardStyle.codex)
                                .frame(height: proxy.size.height * 0.82 * CGFloat(bar.codexTokens) / CGFloat(maxValue))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                        .frame(maxWidth: 28)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
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
                                .background(Color.accentColor, in: Capsule())
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
                UsageWindowGauge(title: L.text("five_hour", language), window: account.fiveHourWindow)
                UsageWindowGauge(title: L.text("weekly", language), window: account.weeklyWindow)
            }

            HStack {
                Text(account.plan?.uppercased() ?? account.status.label)
                Spacer()
                Text(DisplayFormatters.tokenString(account.tokens.total))
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
            .dashboardPanel()
        }
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
    var cost: Double?
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
                    .fill(.regularMaterial)
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
