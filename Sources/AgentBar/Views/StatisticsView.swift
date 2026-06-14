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

            ZStack(alignment: .top) {
                if topTab == .usage {
                    ScrollView(.vertical, showsIndicators: false) {
                        dashboardContent
                            .padding(.top, 86)
                            .padding(.horizontal, 22)
                            .padding(.bottom, 26)
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        settingsContent
                            .padding(.top, 86)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 28)
                    }
                }

                topChrome
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            sidebarGroup(title: "Service", chinese: "服务") {
                sidebarItem("All", chinese: "全部", active: serviceFilter == .all, tint: nil) {
                    serviceFilter = .all
                }
                sidebarItem("OpenAI", chinese: "OpenAI", active: serviceFilter == .codex, tint: DashboardStyle.codex) {
                    serviceFilter = .codex
                }
                if hasClaudeData {
                    sidebarItem("Anthropic", chinese: "Anthropic", active: serviceFilter == .claude, tint: DashboardStyle.claude) {
                        serviceFilter = .claude
                    }
                }
            }

            sidebarGroup(title: "View", chinese: "视图") {
                sidebarItem("Overview", chinese: "概览", systemImage: "rectangle.split.2x2", active: viewMode == .overview) {
                    viewMode = .overview
                }
                sidebarItem("Timeline", chinese: "时间线", systemImage: "chart.line.uptrend.xyaxis", active: viewMode == .timeline, enabled: false) {}
                sidebarItem("Details", chinese: "明细", systemImage: "list.bullet", active: viewMode == .details, enabled: false) {}
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 58)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func sidebarGroup<Content: View>(title: String, chinese: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(chinese)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
            content()
        }
    }

    private func sidebarItem(
        _ english: String,
        chinese: String,
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
                Text(chinese)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(active ? .white : (enabled ? Color.primary.opacity(0.82) : Color.secondary.opacity(0.42)))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(active ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
    }

    private var topChrome: some View {
        VStack(spacing: 34) {
            Picker("", selection: $topTab) {
                Text("用量统计").tag(DashboardTopTab.usage)
                Text("设置").tag(DashboardTopTab.settings)
            }
            .pickerStyle(.segmented)
            .frame(width: 168)
            .controlSize(.small)
            .padding(.top, 10)

            if topTab == .usage {
                HStack {
                    Spacer()
                    Picker("", selection: $store.selectedRange) {
                        ForEach(UsageRange.allCases) { range in
                            Text(range.dashboardLabel).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 584)
                    .controlSize(.small)

                    Button {
                        store.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(L.text("refresh", store.language))
                }
                .padding(.horizontal, 22)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var dashboardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: kpiColumns, spacing: 12) {
                DashboardKPI(title: "总 Tokens", value: DisplayFormatters.compactTokenString(summary.totalTokens), delta: "↓ 23.6%", accent: .primary)
                DashboardKPI(title: "总花费", value: DisplayFormatters.costString(summary.estimatedCostUSD), delta: "↓ 4.0%", accent: .primary)
                DashboardKPI(title: "OpenAI", value: serviceCostText(.codex), delta: serviceShareText(.codex), marker: DashboardStyle.codex, accent: DashboardStyle.codex)
                if hasClaudeData {
                    DashboardKPI(title: "Anthropic", value: serviceCostText(.claudeCode), delta: serviceShareText(.claudeCode), marker: DashboardStyle.claude, accent: DashboardStyle.claude)
                }
            }

            Panel(title: "每日用量") {
                DashboardStackedBars(bars: displayBars)
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
                Panel(title: "按服务") {
                    serviceMixRows
                }
                Panel(title: "当前限额") {
                    currentLimitsRows
                }
            }

            Panel(title: "按模型") {
                modelRows
            }
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(title: "账号", subtitle: "自动检测本机账号；无安全数据源时不显示占位账号。") {
                SettingsRow(title: "Codex", subtitle: "\(codexAccounts.count) accounts detected") {
                    Toggle("", isOn: $settings.showCodexInMenuBar).labelsHidden()
                }
                SettingsRow(title: "Claude Code", subtitle: hasClaudeData ? "Available" : "No safe local source") {
                    Toggle("", isOn: $settings.showClaudeInMenuBar).labelsHidden()
                }
            }

            SettingsGroup(title: "菜单栏", subtitle: "控制菜单栏状态项显示。") {
                SettingsRow(title: "显示内容", subtitle: "Choose the value next to the icon.") {
                    Picker("", selection: $settings.menuBarDisplayMode) {
                        Text(L.text("lowest_remaining", store.language)).tag(MenuBarDisplayMode.lowestRemaining)
                        Text(L.text("total_tokens", store.language)).tag(MenuBarDisplayMode.totalTokens)
                        Text(L.text("codex_only", store.language)).tag(MenuBarDisplayMode.codexRemaining)
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
            }

            SettingsGroup(title: "刷新", subtitle: "后台轮询用量的频率。") {
                SettingsRow(title: L.text("refresh_interval", store.language), subtitle: "Applies to local read-only data sync.") {
                    Picker("", selection: $settings.refreshInterval) {
                        Text("15s").tag(TimeInterval(15))
                        Text("30s").tag(TimeInterval(30))
                        Text("60s").tag(TimeInterval(60))
                        Text("5m").tag(TimeInterval(300))
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                SettingsRow(title: L.text("login_item", store.language), subtitle: settings.loginItemMessage ?? "Open AgentBar at login.") {
                    Toggle("", isOn: $settings.launchAtLogin).labelsHidden()
                }
            }

            SettingsGroup(title: "通用", subtitle: "Language and app behavior.") {
                SettingsRow(title: L.text("language", store.language), subtitle: "Interface language.") {
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
        guard !costs.isEmpty else { return "N/A" }
        return DisplayFormatters.costString(costs.reduce(0, +))
    }

    private func serviceShareText(_ service: UsageService) -> String {
        let total = max(1, summary.serviceBreakdown.values.reduce(0, +))
        let value = summary.serviceBreakdown[service, default: 0]
        return "\(Int((Double(value) / Double(total) * 100).rounded()))% 占比"
    }

    @ViewBuilder
    private var serviceMixRows: some View {
        let rows = serviceRows
        if rows.isEmpty {
            EmptyPanelMessage("No usage data")
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
                            Text(DisplayFormatters.compactTokenString(row.tokens) + " Tokens")
                            Spacer()
                            Text("\(Int((row.share * 100).rounded()))% 占比")
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
        let limitRows = currentLimitRows
        if limitRows.isEmpty {
            EmptyPanelMessage("No quota windows")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(limitRows) { row in
                    HStack(spacing: 12) {
                        ProgressRing(value: row.percent / 100, tint: row.color, diameter: 38, stroke: 5) {
                            Text("\(Int(row.percent.rounded()))")
                                .font(.system(size: 10, weight: .bold))
                                .monospacedDigit()
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.system(size: 13, weight: .bold))
                            Text(row.subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var currentLimitRows: [LimitRow] {
        store.accounts.flatMap { account -> [LimitRow] in
            let color = account.service == .codex ? DashboardStyle.codex : DashboardStyle.claude
            return [
                account.fiveHourWindow.map {
                    LimitRow(title: "\(account.service.rawValue) 5H", subtitle: resetText($0.resetsAt), percent: $0.remainingPercent, color: statusColor($0.remainingPercent, fallback: color))
                },
                account.weeklyWindow.map {
                    LimitRow(title: "\(account.service.rawValue) WK", subtitle: resetText($0.resetsAt), percent: $0.remainingPercent, color: statusColor($0.remainingPercent, fallback: color))
                }
            ].compactMap { $0 }
        }
        .prefix(6)
        .map { $0 }
    }

    @ViewBuilder
    private var modelRows: some View {
        let rows = modelBreakdownRows
        if rows.isEmpty {
            EmptyPanelMessage("No model data")
        } else {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    HStack {
                        Text(row.name)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("入 \(DisplayFormatters.compactTokenString(row.input))")
                        Text("出 \(DisplayFormatters.compactTokenString(row.output))")
                            .frame(width: 96, alignment: .trailing)
                        Text(DisplayFormatters.costString(row.cost))
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
        guard let date else { return "重置时间未知" }
        return "\(DisplayFormatters.relativeString(for: date)) 后重置"
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

    var body: some View {
        GeometryReader { proxy in
            if bars.isEmpty {
                EmptyPanelMessage("No usage events")
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
    var id: String { title + subtitle }
    var title: String
    var subtitle: String
    var percent: Double
    var color: Color
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
        background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}

private extension UsageRange {
    var dashboardLabel: String {
        switch self {
        case .today: "今天"
        case .yesterday: "昨天"
        case .thisWeek: "本周"
        case .thisMonth: "本月"
        case .thisYear: "本年"
        case .last7Days: "7 天"
        case .last30Days: "30 天"
        case .all: "全部"
        case .custom: "自定义"
        }
    }
}
