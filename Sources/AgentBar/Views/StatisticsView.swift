import AppKit
import SwiftUI

private let settingsControlLeadingInset: CGFloat = 14
private let settingsControlTrailingInset: CGFloat = 14
private let settingsControlWidePickerWidth: CGFloat = 180
private let settingsControlMediumPickerWidth: CGFloat = 140
private let settingsControlCompactPickerWidth: CGFloat = 120

private enum SettingsSection: String, CaseIterable, Identifiable {
    case accounts
    case menuBar
    case usage
    case general

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        let key = switch self {
        case .accounts: "settings_section_accounts"
        case .menuBar: "settings_section_menu_bar"
        case .usage: "settings_section_usage"
        case .general: "settings_section_general"
        }
        return L.text(key, language)
    }
}

struct StatisticsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var updates: AppUpdateStore
    @ObservedObject private var codexOverlay = CodexSidebarQuotaOverlayController.shared
    @ObservedObject private var quotaWidgetHotKey = QuotaWidgetHotKeyController.shared
    @State private var viewMode: DashboardViewMode = .overview
    @State private var topTab: DashboardTopTab
    @State private var showsSidebarNavigation = true
    @State private var selectedSessionLabel: String?
    @State private var showsAccountPopover = false
    @State private var showsQuotaWidgetOnboarding = false
    @State private var settingsSection: SettingsSection = .accounts
    @State private var showsAdvancedRefreshSettings = false
    @State private var dismissedUpdateVersion: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

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
        Group {
            if showsSidebarNavigation {
                HStack(spacing: 0) {
                    sidebar
                        .frame(width: 236)
                    contentColumn
                }
            } else {
                VStack(spacing: 0) {
                    topNavigationBar
                    contentColumn
                }
            }
        }
        .tint(AgentBarPalette.primary)
        .background(
            settings.useTranslucentAppearance
                ? Color.clear
                : AgentBarDesign.appBackground
        )
        .onAppear {
            if let tab = DashboardNavigation.consumePendingTab() {
                setTopTab(tab)
            }
            if DashboardNavigation.consumePendingEfficiencyCoach() {
                setPage(tab: .usage, viewMode: .efficiency)
            }
            if !settings.didCompleteQuotaWidgetOnboarding {
                showsQuotaWidgetOnboarding = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: DashboardNavigation.tabRequestNotification)) { notification in
            guard let rawValue = notification.userInfo?["tab"] as? String,
                  let tab = DashboardTopTab(rawValue: rawValue)
            else { return }
            setTopTab(tab)
            _ = DashboardNavigation.consumePendingTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: DashboardNavigation.efficiencyCoachRequestNotification)) { _ in
            setPage(tab: .usage, viewMode: .efficiency)
            _ = DashboardNavigation.consumePendingEfficiencyCoach()
        }
        .sheet(isPresented: $showsQuotaWidgetOnboarding) {
            QuotaWidgetOnboardingView(
                settings: settings,
                overlay: codexOverlay,
                language: store.language
            )
        }
    }

    private var contentColumn: some View {
        VStack(spacing: 0) {
            pageContent
                .id(pageTransitionID)
                .transition(pageTransition)
                .animation(pageAnimation, value: pageTransitionID)
            appFooter
                .padding(.horizontal, 26)
                .frame(height: 42)
                .background(
                    settings.useTranslucentAppearance
                        ? Color.clear
                        : AgentBarDesign.panelHighlight
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .agentBarGlassSurface(
            isEnabled: settings.useTranslucentAppearance,
            opaqueBackground: AnyShapeStyle(
                LinearGradient(
                    colors: [
                        AgentBarDesign.panelHighlight,
                        AgentBarDesign.appBackground,
                        AgentBarPalette.primary.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            ),
            cornerRadius: 0
        )
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
                sidebarItem(store.language == .chinese ? "效率指南" : "Efficiency Guide", systemImage: "sparkles", active: topTab == .usage && viewMode == .efficiency) {
                    setPage(tab: .usage, viewMode: .efficiency)
                }
                sidebarItem(L.text("live_tasks", store.language), systemImage: "bolt.horizontal.circle", active: topTab == .usage && viewMode == .liveTasks) {
                    setPage(tab: .usage, viewMode: .liveTasks)
                }
                sidebarItem(L.text("project_billing", store.language), systemImage: "folder", active: topTab == .usage && viewMode == .projects) {
                    setPage(tab: .usage, viewMode: .projects)
                }
                sidebarItem(L.text("quota_and_resets", store.language), systemImage: "arrow.counterclockwise.circle", active: topTab == .usage && viewMode == .resets) {
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

            if let release = sidebarUpdateRelease {
                sidebarUpdateCard(release)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
            }

            sidebarAccountSelector
                .padding(.bottom, 18)
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .agentBarGlassSurface(
            isEnabled: settings.useTranslucentAppearance,
            opaqueBackground: AnyShapeStyle(AgentBarDesign.cardBackground),
            cornerRadius: 0
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(sidebarSeparatorColor)
                .frame(width: 1)
        }
        .animation(
            AgentBarDesign.smoothAnimation(reduceMotion: reduceMotion),
            value: sidebarUpdateRelease?.version
        )
    }

    private var sidebarSeparatorColor: Color {
        colorScheme == .dark ? AgentBarDesign.hairline : Color(nsColor: .separatorColor).opacity(0.18)
    }

    private var sidebarUpdateRelease: AppUpdateRelease? {
        guard let release = updates.downloadedUpdate?.release,
              dismissedUpdateVersion != release.version
        else { return nil }
        return release
    }

    private func sidebarUpdateCard(_ release: AppUpdateRelease) -> some View {
        let displayVersion = release.version.hasPrefix("v") || release.version.hasPrefix("V")
            ? String(release.version.dropFirst())
            : release.version
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.agentBar(size: 28, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, AgentBarPalette.primary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L.text("new_version_available", store.language))
                        .font(.agentBar(size: 9, weight: .bold))
                        .foregroundStyle(AgentBarPalette.primary)
                    Text("AgentBar \(displayVersion)")
                        .font(.agentBar(size: 12, weight: .bold))
                        .lineLimit(1)
                    Text("\(L.text("current_version", store.language)) \(AppVersion.currentComparableVersion)")
                        .font(.agentBar(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    dismissedUpdateVersion = release.version
                } label: {
                    Image(systemName: "xmark")
                        .font(.agentBar(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .tactilePlainButton(pressedScale: 0.94)
                .accessibilityLabel(L.text("dismiss_update", store.language))
            }

            Button {
                updates.installDownloadedUpdate()
            } label: {
                Text(L.text("install_update", store.language))
                    .font(.agentBar(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(AgentBarPalette.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .tactilePlainButton(enabled: updates.canInstallDownloadedUpdate)
            .disabled(!updates.canInstallDownloadedUpdate)

            Link(destination: release.pageURL) {
                HStack(spacing: 4) {
                    Text(String(format: L.text("view_release_notes", store.language), release.version))
                    Image(systemName: "arrow.up.right")
                        .font(.agentBar(size: 8, weight: .bold))
                }
                .font(.agentBar(size: 10, weight: .semibold))
                .foregroundStyle(AgentBarPalette.primary)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape.fill(AgentBarPalette.primary.opacity(colorScheme == .dark ? 0.14 : 0.06))
        }
        .overlay {
            shape.strokeBorder(AgentBarPalette.primary.opacity(colorScheme == .dark ? 0.28 : 0.20), lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.06), radius: 8, y: 2)
    }

    private var sidebarBrand: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppLogo.image())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("AgentBar")
                .font(.agentBarDisplay(size: 20, weight: .bold))
            Spacer()
            navigationLayoutButton(systemImage: "menubar.rectangle", helpKey: "show_top_menu_bar") {
                showsSidebarNavigation = false
            }
        }
    }

    private var topNavigationBar: some View {
        ZStack {
            HStack {
                navigationLayoutButton(systemImage: "sidebar.left", helpKey: "show_sidebar_menu_bar") {
                    showsSidebarNavigation = true
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                topNavigationItem(L.text("overview", store.language), systemImage: "rectangle.split.2x2", active: topTab == .usage && viewMode == .overview) {
                    setPage(tab: .usage, viewMode: .overview)
                }
                topNavigationItem(store.language == .chinese ? "效率指南" : "Efficiency Guide", systemImage: "sparkles", active: topTab == .usage && viewMode == .efficiency) {
                    setPage(tab: .usage, viewMode: .efficiency)
                }
                topNavigationItem(L.text("live_tasks", store.language), systemImage: "bolt.horizontal.circle", active: topTab == .usage && viewMode == .liveTasks) {
                    setPage(tab: .usage, viewMode: .liveTasks)
                }
                topNavigationItem(L.text("project_billing", store.language), systemImage: "folder", active: topTab == .usage && viewMode == .projects) {
                    setPage(tab: .usage, viewMode: .projects)
                }
                topNavigationItem(L.text("quota_and_resets", store.language), systemImage: "arrow.counterclockwise.circle", active: topTab == .usage && viewMode == .resets) {
                    setPage(tab: .usage, viewMode: .resets)
                }
                topNavigationItem(L.text("audit", store.language), systemImage: "chart.bar.doc.horizontal", active: topTab == .usage && viewMode == .audit) {
                    setPage(tab: .usage, viewMode: .audit)
                }
                topNavigationItem(L.text("settings", store.language), systemImage: "gearshape", active: topTab == .settings) {
                    setPage(tab: .settings)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(AgentBarDesign.cardBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(topNavigationSeparatorColor)
                .frame(height: 1)
        }
    }

    private var topNavigationSeparatorColor: Color {
        colorScheme == .dark ? AgentBarDesign.hairline : Color(nsColor: .separatorColor).opacity(0.72)
    }

    private func navigationLayoutButton(systemImage: String, helpKey: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.agentBar(size: 14, weight: .semibold))
                .foregroundStyle(AgentBarPalette.primary)
                .frame(width: 30, height: 30)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .tactilePlainButton()
        .background(AgentBarPalette.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(L.text(helpKey, store.language))
    }

    private func topNavigationItem(_ title: String, systemImage: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.agentBar(size: 12, weight: .semibold))
                Text(title)
                    .font(.agentBar(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(active ? AgentBarPalette.primary : Color.primary.opacity(0.86))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .background(active ? AgentBarPalette.primary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .tactilePlainButton()
    }

    private var sidebarAccountSelector: some View {
        let account = store.activeAccount ?? currentCodexAccount
        return Button {
            showsAccountPopover.toggle()
        } label: {
            HStack(spacing: 10) {
                AccountAvatar(text: account?.providerAccountDisplayName ?? "A", color: AgentBarPalette.primary, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account?.providerAccountDisplayName ?? "--")
                        .font(.agentBar(size: 12, weight: .bold))
                        .lineLimit(1)
                    Text(account?.workspaceLine(language: store.language) ?? L.text("current_account", store.language))
                        .font(.agentBar(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.agentBar(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .tactilePlainButton(pressedScale: 1)
        .agentBarPanel(cornerRadius: 10)
        .popover(isPresented: $showsAccountPopover, arrowEdge: .bottom) {
            SidebarAccountPopover(account: account, language: store.language)
        }
    }

    private var appFooter: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 10, height: 10)
                    .shadow(color: .green.opacity(0.36), radius: 5)
                Text(L.text("auto_update_status", store.language))
                Spacer()
                Text(footerDateTimeText(timeline.date))
                    .monospacedDigit()
                Text(timeZoneText)
                Image(systemName: "shield.checkered")
                Text(L.text("secure_status", store.language))
            }
            .font(.agentBar(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
        }
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.text("settings", store.language))
                    .font(.agentBar(size: 24, weight: .bold))
                Text(L.text("settings_page_subtitle", store.language))
                    .font(.agentBar(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            if let error = settings.settingsPersistenceError {
                Label(
                    error.localizedMessage(language: store.language),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.agentBar(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(10)
                .frame(maxWidth: 620, alignment: .leading)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            Picker("", selection: $settingsSection) {
                ForEach(SettingsSection.allCases) { section in
                    Text(section.title(store.language)).tag(section)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(L.text("settings_navigation", store.language))
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
                .font(.agentBar(size: 11, weight: .semibold))
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
                        .font(.agentBar(size: 13, weight: .semibold))
                        .frame(width: 14)
                } else if service == .codex {
                    Image(nsImage: AppLogo.image())
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint ?? Color.secondary)
                        .frame(width: 8, height: 8)
                }
                Text(title)
                    .font(.agentBar(size: 13, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(active ? AgentBarPalette.primary : (enabled ? Color.primary.opacity(0.86) : Color.secondary.opacity(0.72)))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(active ? AgentBarPalette.primary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(active ? AgentBarPalette.primary.opacity(0.24) : Color.clear, lineWidth: 1)
            }
            .shadow(color: active ? AgentBarPalette.primary.opacity(0.18) : .clear, radius: 10, y: 4)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.86)
        .tactilePlainButton(enabled: enabled)
    }

    private var usageContent: some View {
        Group {
            if viewMode == .efficiency {
                EfficiencyCoachView(store: store)
                    .padding(.top, Self.dashboardContentTopPadding)
                    .padding(.horizontal, 26)
                    .padding(.bottom, Self.dashboardContentBottomPadding)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        if store.isLoadingSessionData {
                            LoadingAccountPanel(
                                title: L.text("loading_session_data", store.language),
                                subtitle: L.text("loading_session_data_subtitle", store.language)
                            )
                        }
                        switch viewMode {
                        case .overview:
                            dashboardContent
                        case .efficiency:
                            EmptyView()
                        case .liveTasks:
                            LiveTaskCenterView(store: store)
                        case .projects:
                            ProjectBillingView(store: store)
                        case .resets:
                            resetsContent
                        case .audit:
                            AuditView(
                                store: store,
                                points: filteredPoints,
                                selectedSessionLabel: selectedSessionLabel,
                                dataSourceHealth: dataSourceHealth,
                                onClearSessionSelection: { selectedSessionLabel = nil }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.top, Self.dashboardContentTopPadding)
                    .padding(.horizontal, 26)
                    .padding(.bottom, Self.dashboardContentBottomPadding)
                }
            }
        }
    }

    private var dashboardRefreshButton: some View {
        Button {
            store.refresh(force: true, showManualFeedback: true)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .font(.agentBar(size: 14, weight: .bold))
                Text(L.text("refresh", store.language))
                    .font(.agentBar(size: 13, weight: .bold))
                if store.isManualRefreshFeedbackVisible {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(AgentBarPalette.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 40, maxHeight: 40)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(L.text("refresh", store.language)))
        }
        .tactilePlainButton()
        .agentBarPanel(cornerRadius: 12)
        .help(L.text("refresh", store.language))
    }

    @ViewBuilder
    private var dashboardContent: some View {
        let quotaPressure = UsageInsights.quotaPressure(
            accounts: store.accounts,
            points: filteredPoints,
            rotationThresholdRemainingPercent: settings.codexRotationThresholdRemainingPercent,
            autoRotationEnabled: settings.autoCodexAccountRotationEnabled
        )
        let topUsage = UsageInsights.topUsage(
            points: filteredPoints,
            limit: settings.topUsageRowCount
        )

        VStack(alignment: .leading, spacing: 16) {
            dashboardOverviewHeader

            if !store.hasLoadedAccountInformation {
                LoadingAccountPanel(
                    title: L.text("loading_account_info", store.language),
                    subtitle: L.text("loading_account_info_subtitle", store.language)
                )
            }

            HStack(alignment: .top, spacing: 0) {
                DashboardKPI(
                    title: L.text("total_tokens", store.language),
                    value: DisplayFormatters.compactTokenString(summary.totalTokens, language: store.language),
                    delta: DisplayFormatters.changePercentString(periodChange.tokenPercent),
                    subtitle: L.text("compared_to_yesterday", store.language),
                    systemImage: "cylinder.split.1x2.fill",
                    accent: AgentBarPalette.primary
                )
                .frame(maxWidth: .infinity)

                Divider()
                    .padding(.vertical, 22)

                DashboardKPI(
                    title: L.text("total_cost", store.language),
                    value: costText(summary.estimatedCostUSD),
                    delta: DisplayFormatters.changePercentString(periodChange.costPercent),
                    subtitle: L.text("compared_to_yesterday", store.language),
                    systemImage: "dollarsign",
                    accent: .green
                )
                .frame(maxWidth: .infinity)

                Divider()
                    .padding(.vertical, 22)

                ServiceQuotaOverview(
                    summaries: serviceQuotaSummaries,
                    language: store.language
                )
                .frame(minWidth: 330)
            }
            .frame(height: 164)
            .background(
                LinearGradient(
                    colors: [AgentBarDesign.panelHighlight, AgentBarPalette.primary.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .agentBarPanel(cornerRadius: 16)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    dailyUsagePanel

                    Panel(title: yearActivityLocalized("year_activity")) {
                        YearActivityPanel(bars: yearActivityBars, language: store.language)
                    }
                }

                if settings.showQuotaPressureSection {
                    QuotaPressurePanel(
                        pressure: quotaPressure,
                        history: store.quotaCapacityHistory,
                        language: store.language
                    )
                    .frame(width: 230)
                    .frame(maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

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
                        breakdown: topUsage,
                        language: store.language,
                    ) { label in
                        selectedSessionLabel = label
                        setPage(tab: .usage, viewMode: .audit)
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
                    .font(.agentBar(size: 20, weight: .bold))
                Text("\(L.text("daily_usage_for", store.language)) · \(store.selectedRange.dashboardLabel(store.language))")
                    .font(.agentBar(size: 12, weight: .semibold))
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
                    .font(.agentBar(size: 14, weight: .bold))
                Spacer()
                dashboardRangePicker
            }

            HStack(spacing: 14) {
                LegendItem(title: L.text("tokens_ten_thousands", store.language), color: AgentBarPalette.primary)
                LegendItem(title: L.text("cost_usd", store.language), color: .orange)
                Spacer()
            }

            DashboardStackedBars(bars: displayBars, language: store.language, isHourly: displayBarsAreHourly)
                .frame(height: 230)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .agentBarPanel()
    }

    private var dashboardRangePicker: some View {
        UsageRangeControls(
            range: $store.selectedRange,
            customStart: $store.customStart,
            customEnd: $store.customEnd,
            language: store.language
        )
    }

    private var resetsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.text("quota_and_resets", store.language))
                        .font(.agentBar(size: 20, weight: .bold))
                    Text(L.text("reset_intro", store.language))
                        .font(.agentBar(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                dashboardRefreshButton
            }

            GeometryReader { proxy in
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 14),
                        count: proxy.size.width < 820 || codexAccounts.isEmpty ? 2 : 4
                    ),
                    spacing: 14
                ) {
                    SummaryChip(title: L.text("total_tokens", store.language), value: DisplayFormatters.compactTokenString(summary.totalTokens, language: store.language), color: AgentBarPalette.primary, systemImage: "cylinder.split.1x2.fill")
                    SummaryChip(title: L.text("total_cost", store.language), value: costText(summary.estimatedCostUSD), color: .green, systemImage: "dollarsign")
                    if !codexAccounts.isEmpty {
                        SummaryChip(title: L.text("resets", store.language), value: "\(totalResetCreditsCount)", color: .green, systemImage: "checkmark")
                        SummaryChip(title: L.text("next_expiry", store.language), value: nextResetExpiry.map { DisplayFormatters.shortDateTimeString(for: $0, language: store.language) } ?? "--", color: resetExpiryColor(nextResetExpiry), systemImage: "clock")
                    }
                }
            }
            .frame(height: 78)

            ResetAdvicePanel(advice: resetSpendAdvice)

            if codexAccounts.isEmpty {
                Panel(title: L.text("by_service", store.language)) {
                    serviceMixRows
                }
            } else {
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
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch settingsSection {
        case .accounts:
            accountsSettingsContent
        case .menuBar:
            menuBarSettingsContent
        case .usage:
            usageSettingsContent
        case .general:
            generalSettingsContent
        }
    }

    private var accountsSettingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.text("account_providers", store.language))
                        .font(.agentBar(size: 15, weight: .bold))
                    Text(L.text("account_providers_subtitle", store.language))
                        .font(.agentBar(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.62))
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
                    spacing: 12
                ) {
                    ProviderSettingsCard(
                        service: .codex,
                        subtitle: "\(codexAccounts.count) \(L.text("accounts_loaded", store.language))",
                        statusColor: providerStatusColor(for: .codex),
                        actionTitle: L.text("login_codex_terminal", store.language)
                    ) {
                        store.openLogin(for: .codex)
                    }
                    ProviderSettingsCard(
                        service: .claudeCode,
                        subtitle: hasClaudeData ? L.text("available", store.language) : L.text("no_safe_local_source", store.language),
                        statusColor: providerStatusColor(for: .claudeCode),
                        actionTitle: L.text("login_claude_terminal", store.language)
                    ) {
                        store.openLogin(for: .claudeCode)
                    }
                    ProviderSettingsCard(
                        service: .xaiAPI,
                        subtitle: xaiProviderSubtitle,
                        statusColor: providerStatusColor(for: .xaiAPI),
                        actionTitle: L.text("login_grok_terminal", store.language)
                    ) {
                        store.openLogin(for: .xaiAPI)
                    }
                    ProviderSettingsCard(
                        service: .cursorAgent,
                        subtitle: cursorProviderSubtitle,
                        statusColor: providerStatusColor(for: .cursorAgent),
                        actionTitle: L.text("login_cursor_terminal", store.language)
                    ) {
                        store.openLogin(for: .cursorAgent)
                    }
                }
            }

            if !codexAccounts.isEmpty {
                SettingsGroup(title: L.text("manage_loaded_accounts", store.language), subtitle: L.text("manage_loaded_accounts_subtitle", store.language)) {
                    SettingsAccountDropdown(
                        accounts: store.sortedAccounts(codexAccounts),
                        currentAccount: currentCodexAccount,
                        language: store.language,
                        onRemove: store.removeAccount
                    )
                    .padding(12)
                }
            }

            SettingsGroup(title: L.text("account_behavior", store.language), subtitle: L.text("account_behavior_subtitle", store.language)) {
                SettingsRow(title: L.text("account_sort", store.language), subtitle: L.text("account_sort_subtitle", store.language)) {
                    Picker("", selection: $settings.accountSortMode) {
                        ForEach(AccountSortMode.allCases) { mode in
                            Text(mode.title(store.language)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .settingsControl(width: settingsControlWidePickerWidth)
                    .accessibilityLabel(L.text("account_sort", store.language))
                }
                SettingsRow(title: L.text("statistics_scope", store.language), subtitle: L.text("statistics_scope_subtitle", store.language)) {
                    Picker("", selection: $settings.showAggregatedAccountData) {
                        Text(L.text("current_service", store.language)).tag(false)
                        Text(L.text("all_services", store.language)).tag(true)
                    }
                    .labelsHidden()
                    .settingsControl(width: settingsControlWidePickerWidth)
                    .accessibilityLabel(L.text("statistics_scope", store.language))
                }
                SettingsToggleRow(
                    title: L.text("reuse_cliproxyapi_auth", store.language),
                    subtitle: L.text("reuse_cliproxyapi_auth_subtitle", store.language),
                    isOn: $settings.reuseCLIProxyAPIAuthEnabled
                )
                .onChange(of: settings.reuseCLIProxyAPIAuthEnabled) { _, _ in
                    store.refresh(force: true)
                }
                if settings.reuseCLIProxyAPIAuthEnabled {
                    SettingsRow(
                        title: L.text("cliproxyapi_auth_directory", store.language),
                        subtitle: L.text("cliproxyapi_auth_directory_subtitle", store.language)
                    ) {
                        TextField("~/.cli-proxy-api", text: $settings.cliProxyAPIAuthDirectory)
                            .textFieldStyle(.roundedBorder)
                            .settingsControl(width: settingsControlWidePickerWidth)
                            .accessibilityLabel(L.text("cliproxyapi_auth_directory", store.language))
                            .onSubmit {
                                store.refresh(force: true)
                            }
                    }
                    SettingsRow(
                        title: L.text("cliproxyapi_security", store.language),
                        subtitle: L.text("cliproxyapi_security_subtitle", store.language)
                    ) {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(L.text("cliproxyapi_security", store.language))
                    }
                }
                SettingsToggleRow(
                    title: L.text("auto_codex_rotation", store.language),
                    subtitle: L.text("auto_codex_rotation_subtitle", store.language),
                    isOn: $settings.autoCodexAccountRotationEnabled
                )
                if settings.autoCodexAccountRotationEnabled {
                    SettingsRow(title: L.text("codex_rotation_threshold", store.language), subtitle: L.text("codex_rotation_threshold_subtitle", store.language)) {
                        CodexRotationThresholdControl(
                            threshold: $settings.codexRotationThresholdRemainingPercent,
                            language: store.language
                        )
                        .settingsControl(width: settingsControlWidePickerWidth)
                    }
                }
            }

            SettingsGroup(title: healthLocalized("account_health"), subtitle: healthLocalized("account_health_subtitle")) {
                if accountHealthCenter.rows.isEmpty {
                    SettingsRow(title: L.text("healthy_status", store.language), subtitle: L.text("healthy", store.language)) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel(L.text("healthy_status", store.language))
                    }
                } else {
                    AccountHealthCenterPanel(
                        health: accountHealthCenter,
                        language: store.language,
                        onLogin: openHealthLogin,
                        onRemove: removeHealthAccount,
                        onRefresh: { store.refresh(force: true, showManualFeedback: true) }
                    )
                    .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var menuBarSettingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.text("menu_bar", store.language))
                        .font(.agentBar(size: 15, weight: .bold))
                    Text(L.text("menu_bar_settings_subtitle", store.language))
                        .font(.agentBar(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.62))
                }

                SettingsRow(
                    title: L.text("menu_bar_preview", store.language),
                    subtitle: L.text("menu_bar_preview_subtitle", store.language),
                    showsDivider: false
                ) {
                    MenuBarStatusPreview(
                        title: store.menuBarTitle,
                        enabledServices: store.menuBarEnabledServices,
                        showsProviderStatus: settings.showOtherServiceStatusInMenuBar
                    )
                    .accessibilityLabel("\(L.text("menu_bar_preview", store.language)): \(store.menuBarTitle)")
                }
                .agentBarPanel()

                SettingsRow(
                    title: L.text("show_other_service_status", store.language),
                    subtitle: L.text("show_other_service_status_subtitle", store.language),
                    showsDivider: false
                ) {
                    Toggle("", isOn: $settings.showOtherServiceStatusInMenuBar)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel(L.text("show_other_service_status", store.language))
                }
                .agentBarPanel()

                VStack(alignment: .leading, spacing: 3) {
                    Text(L.text("menu_bar_included_services", store.language))
                        .font(.agentBar(size: 13, weight: .semibold))
                    Text(L.text("menu_bar_included_services_subtitle", store.language))
                        .font(.agentBar(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.62))
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
                    spacing: 12
                ) {
                    MenuBarProviderToggleCard(
                        service: .codex,
                        hasData: hasMenuBarData(for: .codex),
                        language: store.language,
                        isOn: $settings.showCodexInMenuBar
                    )
                    MenuBarProviderToggleCard(
                        service: .claudeCode,
                        hasData: hasMenuBarData(for: .claudeCode),
                        language: store.language,
                        isOn: $settings.showClaudeInMenuBar
                    )
                    MenuBarProviderToggleCard(
                        service: .xaiAPI,
                        hasData: hasMenuBarData(for: .xaiAPI),
                        language: store.language,
                        isOn: $settings.showGrokInMenuBar
                    )
                    MenuBarProviderToggleCard(
                        service: .cursorAgent,
                        hasData: hasMenuBarData(for: .cursorAgent),
                        language: store.language,
                        isOn: $settings.showCursorAgentInMenuBar
                    )
                }

                SettingsRow(
                    title: L.text("display_value", store.language),
                    subtitle: L.text("display_value_subtitle", store.language),
                    showsDivider: false
                ) {
                    Picker("", selection: $settings.menuBarDisplayMode) {
                        Text(L.text("active_account_windows", store.language)).tag(MenuBarDisplayMode.activeAccountWindows)
                        Text(L.text("lowest_remaining", store.language)).tag(MenuBarDisplayMode.lowestRemaining)
                        Text(L.text("total_tokens", store.language)).tag(MenuBarDisplayMode.totalTokens)
                        Text(L.text("codex_only", store.language)).tag(MenuBarDisplayMode.codexRemaining)
                    }
                    .labelsHidden()
                    .settingsControl(width: settingsControlWidePickerWidth)
                    .accessibilityLabel(L.text("display_value", store.language))
                }
                .agentBarPanel()
            }

            SettingsGroup(title: L.text("codex_sidebar", store.language), subtitle: L.text("codex_sidebar_settings_subtitle", store.language)) {
                SettingsToggleRow(
                    title: L.text("codex_sidebar_quota", store.language),
                    subtitle: L.text("codex_sidebar_quota_subtitle", store.language),
                    isOn: $settings.showCodexSidebarQuotaOverlay
                )
                .onChange(of: settings.showCodexSidebarQuotaOverlay) { _, enabled in
                    if enabled && !settings.codexSidebarQuotaOverlayIndependent {
                        codexOverlay.requestAccessibilityPermission()
                    }
                }

                SettingsRow(
                    title: L.text("quota_widget_shortcut", store.language),
                    subtitle: L.text(
                        quotaWidgetHotKey.registrationFailed
                            ? "quota_widget_shortcut_conflict"
                            : "quota_widget_shortcut_subtitle",
                        store.language
                    )
                ) {
                    QuotaWidgetHotKeyRecorder(
                        hotKey: $settings.quotaWidgetHotKey,
                        emptyText: L.text("quota_widget_shortcut_set", store.language),
                        recordingText: L.text("quota_widget_shortcut_recording", store.language)
                    )
                    .frame(width: 150, height: 30)
                }

                SettingsToggleRow(
                    title: L.text("codex_sidebar_independent", store.language),
                    subtitle: L.text("codex_sidebar_independent_subtitle", store.language),
                    isOn: $settings.codexSidebarQuotaOverlayIndependent
                )
                .disabled(!settings.showCodexSidebarQuotaOverlay)
                .onChange(of: settings.codexSidebarQuotaOverlayIndependent) { _, independent in
                    if !independent && settings.showCodexSidebarQuotaOverlay {
                        codexOverlay.requestAccessibilityPermission()
                    }
                }

                if settings.showCodexSidebarQuotaOverlay
                    && !settings.codexSidebarQuotaOverlayIndependent
                    && !codexOverlay.hasAccessibilityPermission {
                    SettingsRow(
                        title: L.text("accessibility_permission_required", store.language),
                        subtitle: L.text("accessibility_permission_subtitle", store.language)
                    ) {
                        Button {
                            codexOverlay.openAccessibilitySettings()
                        } label: {
                            Label(L.text("open_system_settings", store.language), systemImage: "gear")
                        }
                        .pointingHandCursor()
                    }
                }

                SettingsRow(
                    title: L.text("quota_onboarding_reopen", store.language),
                    subtitle: L.text("quota_onboarding_reopen_subtitle", store.language)
                ) {
                    Button {
                        showsQuotaWidgetOnboarding = true
                    } label: {
                        Label(L.text("quota_onboarding_open", store.language), systemImage: "questionmark.circle")
                    }
                    .pointingHandCursor()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var usageSettingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(title: L.text("popover_overview", store.language), subtitle: L.text("popover_overview_subtitle", store.language)) {
                SettingsToggleRow(
                    title: L.text("show_popover_overview", store.language),
                    subtitle: L.text("show_popover_overview_subtitle", store.language),
                    isOn: $settings.showPopoverOverviewSection
                )
                if settings.showPopoverOverviewSection {
                    PopoverMetricPicker(settings: settings, language: store.language)
                        .padding(.horizontal, settingsControlLeadingInset)
                        .padding(.vertical, 10)
                }
            }

            SettingsGroup(title: L.text("overview", store.language), subtitle: L.text("overview_sections_subtitle", store.language)) {
                SettingsToggleRow(
                    title: L.text("quota_pressure", store.language),
                    subtitle: L.text("quota_pressure_section_subtitle", store.language),
                    isOn: $settings.showQuotaPressureSection
                )
                SettingsRow(
                    title: L.text("top_usage_row_count", store.language),
                    subtitle: L.text("top_usage_row_count_subtitle", store.language)
                ) {
                    Picker("", selection: $settings.topUsageRowCount) {
                        ForEach(1...SettingsStore.maximumTopUsageRowCount, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .labelsHidden()
                    .settingsControl(width: settingsControlCompactPickerWidth)
                    .accessibilityLabel(L.text("top_usage_row_count", store.language))
                }
            }

            SettingsGroup(title: budgetLocalized("budgets"), subtitle: budgetLocalized("budget_subtitle")) {
                SettingsRow(title: L.text("daily_budget", store.language), subtitle: L.text("budget_zero_disables_alerts", store.language)) {
                    HStack(spacing: 16) {
                        BudgetIntegerField(
                            value: $settings.dailyTokenBudget,
                            language: store.language,
                            label: budgetLocalized("daily_token_budget")
                        )
                        BudgetCostField(
                            value: $settings.dailyCostBudgetUSD,
                            language: store.language,
                            label: budgetLocalized("daily_cost_budget")
                        )
                    }
                }
                SettingsRow(title: L.text("weekly_budget", store.language), subtitle: L.text("budget_zero_disables_alerts", store.language)) {
                    HStack(spacing: 16) {
                        BudgetIntegerField(
                            value: $settings.weeklyTokenBudget,
                            language: store.language,
                            label: budgetLocalized("weekly_token_budget")
                        )
                        BudgetCostField(
                            value: $settings.weeklyCostBudgetUSD,
                            language: store.language,
                            label: budgetLocalized("weekly_cost_budget")
                        )
                    }
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
                    .settingsControl(width: settingsControlCompactPickerWidth)
                    .accessibilityLabel(L.text("refresh_interval", store.language))
                }
                DisclosureGroup(isExpanded: $showsAdvancedRefreshSettings) {
                    SettingsRow(title: quotaCapacityLocalized("quota_capacity_frequency"), subtitle: quotaCapacityLocalized("quota_capacity_frequency_subtitle")) {
                        Picker("", selection: $settings.quotaCapacityHistoryInterval) {
                            Text("15m").tag(TimeInterval(900))
                            Text("30m").tag(TimeInterval(1_800))
                            Text("1h").tag(TimeInterval(3_600))
                            Text("2h").tag(TimeInterval(7_200))
                            Text("6h").tag(TimeInterval(21_600))
                        }
                        .labelsHidden()
                        .settingsControl(width: settingsControlCompactPickerWidth)
                        .accessibilityLabel(quotaCapacityLocalized("quota_capacity_frequency"))
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L.text("advanced_refresh", store.language))
                            .font(.agentBar(size: 13, weight: .semibold))
                        Text(L.text("advanced_refresh_subtitle", store.language))
                            .font(.agentBar(size: 11))
                            .foregroundStyle(Color.primary.opacity(0.62))
                    }
                }
                .padding(.horizontal, settingsControlLeadingInset)
                .padding(.vertical, 12)
            }

            SettingsGroup(title: L.text("notifications", store.language), subtitle: L.text("notifications_subtitle", store.language)) {
                SettingsToggleRow(
                    title: L.text("quota_reset_notifications", store.language),
                    subtitle: L.text("quota_reset_notifications_subtitle", store.language),
                    isOn: $settings.quotaResetNotificationsEnabled
                )
                SettingsToggleRow(
                    title: L.text("task_completion_notifications", store.language),
                    subtitle: L.text("task_completion_notifications_subtitle", store.language),
                    isOn: $settings.taskCompletionNotificationsEnabled
                )
                SettingsToggleRow(
                    title: L.text("access_token_expiry_notifications", store.language),
                    subtitle: L.text("access_token_expiry_notifications_subtitle", store.language),
                    isOn: $settings.accessTokenExpiryNotificationsEnabled
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var generalSettingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(title: L.text("general", store.language), subtitle: L.text("general_settings_subtitle", store.language)) {
                SettingsRow(title: L.text("language", store.language), subtitle: L.text("language_subtitle", store.language)) {
                    Picker("", selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .labelsHidden()
                    .settingsControl(width: settingsControlMediumPickerWidth)
                    .accessibilityLabel(L.text("language", store.language))
                }
                SettingsRow(title: L.text("appearance", store.language), subtitle: L.text("appearance_subtitle", store.language)) {
                    Picker("", selection: $settings.useDarkAppearance) {
                        Text(L.text("follow_system", store.language)).tag(false)
                        Text(L.text("dark_theme", store.language)).tag(true)
                    }
                    .labelsHidden()
                    .settingsControl(width: settingsControlMediumPickerWidth)
                    .accessibilityLabel(L.text("appearance", store.language))
                }
                SettingsToggleRow(
                    title: L.text("translucent", store.language),
                    subtitle: L.text("translucent_subtitle", store.language),
                    isOn: $settings.useTranslucentAppearance
                )
                SettingsToggleRow(
                    title: L.text("login_item", store.language),
                    subtitle: settings.loginItemMessage ?? L.text("open_at_login_subtitle", store.language),
                    isOn: $settings.launchAtLogin
                )
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
                        .settingsControl(width: settingsControlWidePickerWidth)
                    }
                }
                if updates.canInstallDownloadedUpdate {
                    SettingsRow(title: L.text("install_and_restart", store.language), subtitle: updates.status.localizedMessage(language: store.language)) {
                        Button(L.text("install_and_restart", store.language)) {
                            updates.installDownloadedUpdate()
                        }
                        .pointingHandCursor()
                        .settingsControl(width: settingsControlWidePickerWidth)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var summary: UsageSummary {
        store.summary
    }

    private var periodChange: UsagePeriodChange {
        store.periodChange
    }

    private var filteredPoints: [UsagePoint] {
        usageDataDisplayPoints
    }

    private var selectedRangePoints: [UsagePoint] {
        store.selectedRangePoints
    }

    private var usageDataDisplayPoints: [UsagePoint] {
        store.usageDataDisplayPoints
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

    private var xaiAccounts: [UsageAccount] {
        store.accounts.filter { $0.service == .xaiAPI }
    }

    private var hasXAIData: Bool {
        !xaiAccounts.isEmpty || store.points.contains { $0.service == .xaiAPI }
    }

    private var cursorAccounts: [UsageAccount] {
        store.accounts.filter { $0.service == .cursorAgent }
    }

    private var hasCursorData: Bool {
        !cursorAccounts.isEmpty
    }

    private func hasMenuBarData(for service: UsageService) -> Bool {
        store.snapshots[service]?.status == .live
            || store.accounts.contains { $0.service == service }
            || store.points.contains { $0.service == service }
    }

    private var xaiProviderSubtitle: String {
        if let snapshot = store.snapshots[.xaiAPI] {
            return "\(snapshot.status.label(language: store.language)) · \(L.text("grok_subscription_usage", store.language))"
        }
        return L.text("grok_cli_not_logged_in", store.language)
    }

    private var cursorProviderSubtitle: String {
        if let snapshot = store.snapshots[.cursorAgent] {
            return "\(snapshot.status.label(language: store.language)) · \(L.text("cursor_subscription_usage", store.language))"
        }
        return L.text("cursor_agent_not_logged_in", store.language)
    }

    private func providerStatusColor(for service: UsageService) -> Color {
        guard let status = store.snapshots[service]?.status else {
            if service == .codex, !codexAccounts.isEmpty { return AgentBarPalette.primary }
            if service == .claudeCode, hasClaudeData { return .green }
            return .secondary
        }
        switch status {
        case .live:
            return .green
        case .unavailable:
            return .secondary
        case .needsAuthorization:
            return .orange
        }
    }

    private var serviceQuotaSummaries: [ServiceQuotaSummary] {
        UsageService.allCases.compactMap { service in
            let loggedInAccounts = store.accounts.filter {
                $0.service == service && $0.status == .live && !$0.needsLogin
            }
            let remaining = loggedInAccounts.compactMap(\.mostConstrainedRemainingPercent)
            guard !remaining.isEmpty else { return nil }
            return ServiceQuotaSummary(
                service: service,
                accountCount: loggedInAccounts.count,
                remainingPercent: remaining.reduce(0, +) / Double(remaining.count),
                color: serviceColor(service)
            )
        }
    }

    private var displayBars: [DailyUsageBar] {
        if displayBarsAreHourly {
            return UsageStatistics.hourlyBars(points: selectedRangePoints, range: store.selectedRange)
        }
        let bars = summary.dailyBars
        guard !bars.isEmpty else { return [] }
        return Array(bars.suffix(24))
    }

    private var displayBarsAreHourly: Bool {
        store.selectedRange == .today || store.selectedRange == .yesterday
    }

    private var yearActivityBars: [DailyUsageBar] {
        store.yearActivityBars
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
                    VStack(spacing: 12) {
                        HStack(alignment: .center, spacing: 12) {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(row.color)
                                .frame(width: 34, height: 34)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .font(.agentBar(size: 13, weight: .bold))
                                Text(rows.count == 1 ? L.text("only_service", store.language) : row.subtitle)
                                    .font(.agentBar(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(spacing: 2) {
                                Text(DisplayFormatters.compactTokenString(row.tokens, language: store.language))
                                    .font(.agentBarMono(size: 18, weight: .bold))
                                    .monospacedDigit()
                                Text(L.text("total_tokens", store.language))
                                    .font(.agentBar(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(Int((row.share * 100).rounded()))%")
                                    .font(.agentBarMono(size: 15, weight: .bold))
                                    .monospacedDigit()
                                Text(L.text("service_share", store.language))
                                    .font(.agentBar(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ProgressView(value: row.share)
                            .tint(row.color)
                    }
                }
            }
        }
    }

    private var serviceRows: [ServiceMixRow] {
        let total = max(1, summary.serviceBreakdown.values.reduce(0, +))
        return UsageService.allCases.compactMap { service in
            let tokens = summary.serviceBreakdown[service, default: 0]
            guard tokens > 0 ||
                (service == .codex && !codexAccounts.isEmpty) ||
                (service == .claudeCode && hasClaudeData) ||
                (service == .xaiAPI && hasXAIData)
            else { return nil }
            return ServiceMixRow(
                service: service,
                title: serviceTitle(service),
                subtitle: serviceProvider(service),
                tokens: tokens,
                share: Double(tokens) / Double(total),
                color: serviceColor(service)
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
                )

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(currentLimitDisplayGroups) { group in
                        AccountLimitDisplayGroupView(
                            group: group,
                            language: store.language,
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
        guard !codexAccounts.isEmpty else {
            return ResetSpendAdvice(
                title: L.text(hasClaudeData ? "local_usage_available" : "no_usage_sources", store.language),
                message: L.text(hasClaudeData ? "claude_quota_unavailable_message" : "no_usage_sources_message", store.language),
                detail: hasClaudeData ? "Claude Code" : "AgentBar",
                systemImage: hasClaudeData ? "chart.bar.fill" : "questionmark.circle",
                color: hasClaudeData ? AgentBarPalette.secondary : .secondary
            )
        }
        return ResetSpendAdvice.make(
            fiveHour: store.activeAccount?.fiveHourWindow,
            weekly: store.activeAccount?.weeklyWindow,
            resetCount: totalResetCreditsCount,
            nextExpiry: nextResetExpiry,
            language: store.language
        )
    }

    @ViewBuilder
    private var resetExpiryRows: some View {
        let rows = resetExpiryRowData
        if rows.isEmpty {
            EmptyPanelMessage(totalResetCreditsCount > 0 ? L.text("no_detailed_expiry_dates", store.language) : L.text("no_banked_resets", store.language))
        } else {
            VStack(spacing: 8) {
                ForEach(rows) { row in
                    ResetExpiryRow(row: row, language: store.language)
                }
            }
        }
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
        L.text(key, store.language)
    }

    private func usageLocalized(_ key: String) -> String {
        L.text(key, store.language)
    }

    private func yearActivityLocalized(_ key: String) -> String {
        L.text(key, store.language)
    }

    private func healthLocalized(_ key: String) -> String {
        L.text(key, store.language)
    }

    private func quotaCapacityLocalized(_ key: String) -> String {
        L.text(key, store.language)
    }

    private var currentLimitAccounts: [UsageAccount] {
        store.accounts.filter { account in
            account.fiveHourWindow != nil ||
                account.weeklyWindow != nil ||
                account.resetCredits?.hasAvailableCredits == true ||
                account.cursorSubscriptionUsage != nil
        }
        .sorted(using: settings.accountSortMode)
    }

    private var currentLimitDisplayGroups: [UsageAccountDisplayGroup] {
        currentLimitAccounts.displayGroupsByIdentity(sortMode: settings.accountSortMode)
    }

    private var resetExpiryRowData: [ResetExpiryRowData] {
        store.accounts
            .flatMap { account in
                (account.resetCredits?.resets ?? []).enumerated().map { index, reset in
                    ResetExpiryRowData(
                        id: "\(account.id)-\(index)-\(reset.expiresAt?.timeIntervalSince1970 ?? 0)",
                        account: account.displayNameWithWorkspace(language: store.language),
                        index: index + 1,
                        expiresAt: reset.expiresAt
                    )
                }
            }
            .sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
    }

    @ViewBuilder
    private var modelRows: some View {
        let rows = modelBreakdownRows
        if rows.isEmpty {
            EmptyPanelMessage(L.text("no_model_data", store.language))
        } else {
            let dataRows = rows.filter { !$0.isHeader }
            let maximum = max(1, dataRows.map { $0.input + $0.output }.max() ?? 1)
            VStack(spacing: 0) {
                ForEach(dataRows) { row in
                    let total = row.input + row.output
                    let share = Double(total) / Double(maximum)

                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(serviceColor(row.service))
                            .frame(width: 8, height: 8)
                        Text(row.name)
                            .font(.agentBar(size: 12, weight: .bold))
                            .lineLimit(1)
                        Spacer()
                        Text(DisplayFormatters.compactTokenString(total, language: store.language))
                            .font(.agentBarMono(size: 11, weight: .bold))
                            .monospacedDigit()
                        Text("\(Int((share * 100).rounded()))%")
                            .font(.agentBar(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 42)
                    .background(alignment: .leading) {
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(serviceColor(row.service).opacity(0.09))
                                .frame(width: proxy.size.width * CGFloat(share))
                        }
                    }
                    Divider()
                }
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
        switch service {
        case .codex: "Codex"
        case .claudeCode: "Claude"
        case .xaiAPI: "Grok"
        case .cursorAgent: "Cursor Agent"
        }
    }

    private func serviceProvider(_ service: UsageService) -> String {
        switch service {
        case .codex: "OpenAI"
        case .claudeCode: "Anthropic"
        case .xaiAPI: "xAI · \(L.text("subscription_quota", store.language))"
        case .cursorAgent: "Cursor · \(L.text("subscription_quota", store.language))"
        }
    }

    private func serviceColor(_ service: UsageService) -> Color {
        switch service {
        case .codex: AgentBarPalette.tertiary
        case .claudeCode: AgentBarPalette.secondary
        case .xaiAPI: .purple
        case .cursorAgent: AgentBarPalette.primary
        }
    }

    private func resetExpiryColor(_ date: Date?) -> Color {
        guard let date else { return .secondary }
        let seconds = date.timeIntervalSinceNow
        if seconds <= 86_400 { return .red }
        if seconds <= 3 * 86_400 { return .orange }
        return AgentBarPalette.primary
    }

    private func quotaMeterColor(_ remaining: Double?) -> Color {
        guard let remaining else { return AgentBarPalette.tertiary }
        if remaining < 15 { return .red }
        if remaining < 35 { return .yellow }
        return AgentBarPalette.primary
    }
}

enum DashboardTopTab: String, Hashable {
    case usage
    case settings
}

private enum DashboardViewMode: Hashable {
    case overview
    case efficiency
    case liveTasks
    case projects
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
            return ResetSpendAdvice(title: localized("let_5h_refill", language), message: localized("let_5h_refill_message", language), detail: fiveHourResetDetail(fiveHour.resetsAt ?? now, language), systemImage: "hourglass", color: AgentBarPalette.primary)
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
            return ResetSpendAdvice(title: localized("hold_that_reset", language), message: localized("hold_that_reset_message", language), detail: weeklyLeftDetail(weeklyRemaining, language), systemImage: "shield.fill", color: AgentBarPalette.primary)
        }
        return ResetSpendAdvice(title: localized("cruise_mode", language), message: localized("cruise_mode_message", language), detail: weeklyLeftDetail(weeklyRemaining, language), systemImage: "gauge.with.dots.needle.50percent", color: AgentBarPalette.secondary)
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
        L.text(key, language)
    }
}

private struct ResetAdvicePanel: View {
    var advice: ResetSpendAdvice

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: advice.systemImage)
                .font(.agentBar(size: 18, weight: .bold))
                .foregroundStyle(advice.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(advice.title)
                        .font(.agentBar(size: 15, weight: .bold))
                    Text(advice.detail)
                        .font(.agentBar(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(advice.color, in: Capsule())
                }
                Text(advice.message)
                    .font(.agentBar(size: 12, weight: .medium))
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
    var accent: Color

    var body: some View {
        ZStack(alignment: .trailing) {
            Image(systemName: systemImage)
                .font(.agentBar(size: 48, weight: .bold))
                .foregroundStyle(accent.opacity(0.12))
                .offset(x: 6, y: 14)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.agentBar(size: 13, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 22, height: 22)
                        .background(accent.opacity(0.12), in: Circle())
                    Text(title)
                        .font(.agentBar(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                }
                Text(value)
                    .font(.agentBar(size: 28, weight: .bold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                HStack(spacing: 8) {
                    Text(delta)
                        .font(.agentBar(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.green.opacity(0.12), in: Capsule())
                    Text(subtitle)
                        .font(.agentBar(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct ServiceQuotaOverview: View {
    var summaries: [ServiceQuotaSummary]
    var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(
                    language == .chinese ? "各服务额度剩余" : "Remaining quota by service",
                    systemImage: "gauge.with.dots.needle.50percent"
                )
                .font(.agentBar(size: 13, weight: .bold))

                Spacer(minLength: 8)

                Text(language == .chinese ? "仅统计已登录账号" : "Logged-in accounts only")
                    .font(.agentBar(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if summaries.isEmpty {
                Text(language == .chinese ? "暂无已登录账户额度数据" : "No logged-in quota data")
                    .font(.agentBar(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                VStack(spacing: 7) {
                    ForEach(summaries) { summary in
                        VStack(spacing: 3) {
                            HStack(spacing: 7) {
                                Text(serviceName(summary.service))
                                    .font(.agentBar(size: 11, weight: .bold))
                                Text(accountCount(summary.accountCount))
                                    .font(.agentBar(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(remainingText(summary.remainingPercent))
                                    .font(.agentBarMono(size: 11, weight: .bold))
                                    .monospacedDigit()
                            }
                            ProgressView(value: summary.remainingPercent, total: 100)
                                .tint(summary.color)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func serviceName(_ service: UsageService) -> String {
        switch service {
        case .codex: "OpenAI"
        case .claudeCode: "Claude Code"
        case .xaiAPI: "Grok"
        case .cursorAgent: "Cursor"
        }
    }

    private func accountCount(_ count: Int) -> String {
        language == .chinese ? "\(count) 已登录" : "\(count) signed in"
    }

    private func remainingText(_ remaining: Double) -> String {
        let value = Int(min(100, max(0, remaining)).rounded())
        return language == .chinese ? "约 \(value)%" : "~\(value)%"
    }
}

private struct Panel<Content: View>: View {
    var title: String
    var helpText: String? = nil
    @ViewBuilder var content: () -> Content
    @State private var showsHelpPopover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.agentBar(size: 14, weight: .bold))
                if let helpText {
                    Button {
                        showsHelpPopover.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.agentBar(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .tactilePlainButton()
                    .popover(isPresented: $showsHelpPopover, arrowEdge: .top) {
                        Text(helpText)
                            .font(.agentBar(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .frame(width: 300, alignment: .leading)
                    }
                    .accessibilityLabel(Text(helpText))
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .agentBarPanel()
    }
}

private struct DashboardStackedBars: View {
    var bars: [DailyUsageBar]
    var language: AppLanguage
    var isHourly = false
    @State private var hoveredBarID: Date?
    @State private var hoverLocation: CGPoint?
    @State private var hoverPlotSize: CGSize = .zero

    private let calloutSize = CGSize(width: 238, height: 146)

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
                            .font(.agentBar(size: 9, weight: .medium))
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
                                        color: AgentBarPalette.primary,
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
                            .font(.agentBar(size: 9, weight: .medium))
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
                        .font(.agentBar(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, leftAxisWidth)
                        .padding(.trailing, rightAxisWidth + 8)
                    }

                    if let hoveredBar, let hoverLocation {
                        let tooltipPosition = chartTooltipPosition(cursor: hoverLocation, calloutSize: calloutSize, plotSize: hoverPlotSize)
                        ChartHoverCallout(bar: hoveredBar, language: language, isHourly: isHourly)
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
        Canvas(rendersAsynchronously: true) { context, canvasSize in
            let drawingSize = canvasSize == .zero ? size : canvasSize
            let points = plotPoints(size: drawingSize, values: values, maximum: maximum)
            guard let first = points.first else { return }

            if showsFill {
                var fillPath = Path()
                fillPath.move(to: CGPoint(x: first.x, y: drawingSize.height))
                points.forEach { fillPath.addLine(to: $0) }
                if let last = points.last {
                    fillPath.addLine(to: CGPoint(x: last.x, y: drawingSize.height))
                    fillPath.closeSubpath()
                }
                context.fill(
                    fillPath,
                    with: .linearGradient(
                        Gradient(colors: [color.opacity(0.32), color.opacity(0.05)]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: drawingSize.height)
                    )
                )
            }

            var linePath = Path()
            linePath.move(to: first)
            points.dropFirst().forEach { linePath.addLine(to: $0) }

            var shadowContext = context
            shadowContext.addFilter(.shadow(color: color.opacity(0.32), radius: 4, x: 0, y: 2))
            shadowContext.stroke(linePath, with: .color(color), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

            for point in points {
                let rect = CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)
                let dot = Path(ellipseIn: rect)
                context.fill(dot, with: .color(.white))
                context.stroke(dot, with: .color(color), lineWidth: 2)
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
        guard let index = chartSlotIndex(at: x, plotWidth: plotWidth, count: bars.count) else { return nil }
        guard bars.indices.contains(index) else { return nil }
        return bars[index].id
    }

    private func axisDate(_ date: Date?) -> String {
        guard let date else { return "" }
        return DisplayFormatters.localizedDateString(for: date, template: isHourly ? "HH:mm" : "MMM d", language: language)
    }

    private func tokenValue(_ bar: DailyUsageBar) -> Double {
        Double(bar.codexTokens + bar.claudeTokens + bar.xaiTokens)
    }

    private func costValue(_ bar: DailyUsageBar) -> Double {
        (bar.codexCostUSD as NSDecimalNumber).doubleValue +
            (bar.claudeCostUSD as NSDecimalNumber).doubleValue +
            (bar.xaiCostUSD as NSDecimalNumber).doubleValue
    }

    private func tokenAxisText(_ value: Double) -> String {
        DisplayFormatters.compactTokenString(Int(value.rounded()), language: language)
    }

    private func costAxisText(_ value: Double) -> String {
        DisplayFormatters.costString(Decimal(value))
    }
}

private struct YearActivityPanel: View {
    var bars: [DailyUsageBar]
    var language: AppLanguage
    @State private var hoveredBarID: Date?
    @State private var hoverLocation: CGPoint?
    @Environment(\.colorScheme) private var colorScheme

    private let spacing: CGFloat = 4
    private let dayLabelWidth: CGFloat = 34
    private let calloutSize = CGSize(width: 238, height: 126)
    private var calendar: Calendar { .current }

    var body: some View {
        if bars.isEmpty {
            EmptyPanelMessage(L.text("no_usage_events", language))
        } else {
            heatmapBody
        }
    }

    private var heatmapBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            summaryHeader

            GeometryReader { proxy in
                let cells = activityCells
                let maximumTokens = maxTokens
                let columns = max(1, Int(ceil(Double(cells.count) / 7.0)))
                let availableWidth = max(1, proxy.size.width - dayLabelWidth - 10)
                let cellSize = max(7, min(18, (availableWidth - CGFloat(max(0, columns - 1)) * spacing) / CGFloat(columns)))
                let gridWidth = CGFloat(columns) * cellSize + CGFloat(max(0, columns - 1)) * spacing
                let gridHeight = cellSize * 7 + spacing * 6

                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .leading) {
                        ForEach(monthMarkers) { marker in
                            Text(marker.title)
                                .font(.agentBar(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .leading)
                                .offset(x: CGFloat(marker.column) * (cellSize + spacing))
                        }
                    }
                    .frame(width: gridWidth, height: 14, alignment: .leading)
                    .padding(.leading, dayLabelWidth + 10)

                    HStack(alignment: .top, spacing: 10) {
                        weekdayLabels(cellSize: cellSize)
                            .frame(width: dayLabelWidth, height: gridHeight, alignment: .leading)

                        Canvas(rendersAsynchronously: true) { context, _ in
                            for cell in cells {
                                let column = cell.index / 7
                                let row = cell.index % 7
                                let tokens = cell.bar.map(totalTokens(for:)) ?? 0
                                let rect = CGRect(
                                    x: CGFloat(column) * (cellSize + spacing),
                                    y: CGFloat(row) * (cellSize + spacing),
                                    width: cellSize,
                                    height: cellSize
                                )
                                let path = Path(roundedRect: rect, cornerRadius: min(4, cellSize * 0.28))
                                context.fill(path, with: .color(color(for: tokens, maximumTokens: maximumTokens)))
                                context.stroke(
                                    path,
                                    with: .color(Color.primary.opacity(tokens > 0 ? 0.11 : 0.055)),
                                    lineWidth: 0.8
                                )
                            }
                        }
                        .frame(width: gridWidth, height: gridHeight, alignment: .topLeading)
                        .accessibilityLabel(Text("\(rangeText), \(activeDaysText)"))
                        .overlay(alignment: .topLeading) {
                            heatmapHoverLayer(cells: cells, cellSize: cellSize, gridWidth: gridWidth, gridHeight: gridHeight)
                        }
                    }
                    .zIndex(1)

                    HStack(spacing: 6) {
                        Spacer()
                        Text(language == .chinese ? "少" : "Less")
                        ForEach(legendColors.indices, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(legendColors[index])
                                .frame(width: 14, height: 14)
                        }
                        Text(language == .chinese ? "多" : "More")
                    }
                    .font(.agentBar(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: dayLabelWidth + 10 + gridWidth, alignment: .trailing)
                    .zIndex(0)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: 192)
        }
    }

    @ViewBuilder
    private func heatmapHoverLayer(cells: [YearActivityCell], cellSize: CGFloat, gridWidth: CGFloat, gridHeight: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            PlotHoverTrackingView { location, _ in
                guard let location, let bar = bar(at: location, cells: cells, cellSize: cellSize) else {
                    hoveredBarID = nil
                    hoverLocation = nil
                    return
                }
                hoveredBarID = bar.id
                hoverLocation = location
            }
            .frame(width: gridWidth, height: gridHeight)

            if let hoveredBar, let hoverLocation {
                let tooltipPosition = chartTooltipPosition(
                    cursor: hoverLocation,
                    calloutSize: calloutSize,
                    plotSize: CGSize(width: gridWidth, height: gridHeight)
                )
                ChartHoverCallout(bar: hoveredBar, language: language)
                    .frame(width: calloutSize.width, height: calloutSize.height)
                    .allowsHitTesting(false)
                    .position(tooltipPosition)
            }
        }
        .frame(width: gridWidth, height: gridHeight, alignment: .topLeading)
    }

    private func bar(at location: CGPoint, cells: [YearActivityCell], cellSize: CGFloat) -> DailyUsageBar? {
        let slot = cellSize + spacing
        guard location.x >= 0, location.y >= 0 else { return nil }
        let column = Int(location.x / slot)
        let row = Int(location.y / slot)
        guard location.x - CGFloat(column) * slot <= cellSize,
              location.y - CGFloat(row) * slot <= cellSize
        else { return nil }
        let index = column * 7 + row
        guard cells.indices.contains(index) else { return nil }
        return cells[index].bar
    }

    private var hoveredBar: DailyUsageBar? {
        guard let hoveredBarID else { return nil }
        return bars.first { $0.id == hoveredBarID }
    }

    private var summaryHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(language == .chinese ? "Tokens · 过去一年" : "Tokens · last year")
                    .font(.agentBar(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(DisplayFormatters.compactTokenString(totalTokens, language: language))
                    .font(.agentBarMono(size: 34, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer()

            HStack(spacing: 28) {
                statistic(
                    value: DisplayFormatters.compactTokenString(averageActiveDayTokens, language: language),
                    title: language == .chinese ? "日均 Tokens" : "daily average"
                )
                statistic(value: "\(activeDaysCount)", title: language == .chinese ? "活跃天数" : "active days", color: AgentBarPalette.primary)
                statistic(
                    value: DisplayFormatters.compactTokenString(peakDayTokens, language: language),
                    detail: peakDayDateText,
                    title: language == .chinese ? "峰值日" : "peak day"
                )
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func statistic(value: String, detail: String? = nil, title: String, color: Color = Color.primary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.agentBar(size: 24, weight: .bold))
                    .foregroundStyle(color)
                if let detail {
                    Text("· \(detail)")
                        .font(.agentBar(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            Text(title)
                .font(.agentBar(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 78, alignment: .leading)
    }

    private func weekdayLabels(cellSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<7, id: \.self) { row in
                Text(weekdayLabel(for: row))
                    .font(.agentBar(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(height: cellSize, alignment: .center)
            }
        }
    }

    private func weekdayLabel(for row: Int) -> String {
        let weekdayIndex = (calendar.firstWeekday - 1 + row) % 7
        guard [1, 3, 5].contains(weekdayIndex) else { return "" }
        if language == .chinese {
            return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][weekdayIndex]
        }
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][weekdayIndex]
    }

    private var legendColors: [Color] {
        [
            color(for: 0, maximumTokens: maxTokens),
            color(for: maxTokens / 5, maximumTokens: maxTokens),
            color(for: maxTokens * 2 / 5, maximumTokens: maxTokens),
            color(for: maxTokens * 3 / 5, maximumTokens: maxTokens),
            color(for: maxTokens, maximumTokens: maxTokens)
        ]
    }

    private var totalTokens: Int {
        bars.reduce(0) { $0 + totalTokens(for: $1) }
    }

    private var activeDaysCount: Int {
        bars.filter { totalTokens(for: $0) > 0 }.count
    }

    private var averageActiveDayTokens: Int {
        guard activeDaysCount > 0 else { return 0 }
        return Int((Double(totalTokens) / Double(activeDaysCount)).rounded())
    }

    private var peakDayTokens: Int {
        peakDayBar.map(totalTokens(for:)) ?? 0
    }

    private var peakDayBar: DailyUsageBar? {
        bars.max { totalTokens(for: $0) < totalTokens(for: $1) }
    }

    private var peakDayDateText: String? {
        guard let peakDayBar, totalTokens(for: peakDayBar) > 0 else { return nil }
        return dayText(peakDayBar.day)
    }

    private var emptyCellColor: Color {
        colorScheme == .dark ? Color(red: 0.09, green: 0.11, blue: 0.14) : Color(red: 0.92, green: 0.93, blue: 0.94)
    }

    private func color(for tokens: Int, maximumTokens: Int) -> Color {
        guard tokens > 0 else { return emptyCellColor }
        let ratio = Double(tokens) / Double(max(maximumTokens, 1))
        if colorScheme == .dark {
            return darkContributionColor(for: ratio)
        }
        return lightContributionColor(for: ratio)
    }

    private func darkContributionColor(for ratio: Double) -> Color {
        if ratio >= 0.78 { return Color(red: 0.42, green: 0.66, blue: 0.88) }
        if ratio >= 0.56 { return Color(red: 0.34, green: 0.56, blue: 0.76) }
        if ratio >= 0.32 { return Color(red: 0.27, green: 0.44, blue: 0.62) }
        return Color(red: 0.20, green: 0.33, blue: 0.46)
    }

    private func lightContributionColor(for ratio: Double) -> Color {
        if ratio >= 0.75 { return Color(red: 0.26, green: 0.43, blue: 0.59) }
        if ratio >= 0.50 { return Color(red: 0.33, green: 0.50, blue: 0.66) }
        if ratio >= 0.25 { return Color(red: 0.39, green: 0.57, blue: 0.66) }
        return Color(red: 0.68, green: 0.77, blue: 0.85)
    }

    private var activityCells: [YearActivityCell] {
        (Array<DailyUsageBar?>(repeating: nil, count: leadingBlankCount) + bars.map { Optional($0) })
            .enumerated()
            .map { YearActivityCell(index: $0.offset, bar: $0.element) }
    }

    private var leadingBlankCount: Int {
        guard let first = bars.first else { return 0 }
        let weekday = calendar.component(.weekday, from: first.day)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var monthMarkers: [YearActivityMonthMarker] {
        bars.enumerated().compactMap { offset, bar in
            let day = calendar.component(.day, from: bar.day)
            guard offset == 0 || day == 1 else { return nil }
            return YearActivityMonthMarker(
                id: "\(offset)-\(bar.day.timeIntervalSince1970)",
                title: monthText(bar.day),
                column: (leadingBlankCount + offset) / 7
            )
        }
    }

    private var activeDaysText: String {
        let count = bars.filter { totalTokens(for: $0) > 0 }.count
        return language == .chinese ? "\(count) 天有活动" : "\(count)d active"
    }

    private var rangeText: String {
        guard let first = bars.first?.day, let last = bars.last?.day else { return "" }
        let suffix = language == .chinese ? "365天" : "365d"
        return "\(monthText(first)) - \(monthText(last)) · \(suffix)"
    }

    private var maxTokens: Int {
        max(1, bars.map { totalTokens(for: $0) }.max() ?? 1)
    }

    private func totalTokens(for bar: DailyUsageBar) -> Int {
        bar.codexTokens + bar.claudeTokens + bar.xaiTokens
    }

    private func monthText(_ date: Date) -> String {
        DisplayFormatters.localizedDateString(for: date, template: "MMM", language: language)
    }

    private func dayText(_ date: Date) -> String {
        DisplayFormatters.localizedDateString(for: date, template: "MMM d, y", language: .english)
    }

}

private struct YearActivityCell: Identifiable {
    var index: Int
    var bar: DailyUsageBar?
    var id: Int { index }
}

private struct YearActivityMonthMarker: Identifiable {
    var id: String
    var title: String
    var column: Int
}

private struct ChartHoverCallout: View {
    var bar: DailyUsageBar
    var language: AppLanguage
    var isHourly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateText)
                .font(.agentBar(size: 11, weight: .bold))
            metricRow("Codex", tokens: bar.codexTokens, cost: bar.codexCostUSD, color: AgentBarPalette.tertiary)
            metricRow("Claude", tokens: bar.claudeTokens, cost: bar.claudeCostUSD, color: AgentBarPalette.secondary)
            if bar.xaiTokens > 0 || bar.xaiCostUSD != 0 {
                metricRow("xAI", tokens: bar.xaiTokens, cost: bar.xaiCostUSD, color: .purple)
            }
            Divider()
            HStack {
                Text(L.text("total", language))
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(tokenText(bar.codexTokens + bar.claudeTokens + bar.xaiTokens))
                    Text(DisplayFormatters.costString(bar.codexCostUSD + bar.claudeCostUSD + bar.xaiCostUSD))
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
                .font(.agentBar(size: 10, weight: .bold))
            }
        }
        .font(.agentBar(size: 10, weight: .medium))
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
            .font(.agentBar(size: 10, weight: .semibold))
        }
    }

    private func tokenText(_ value: Int) -> String {
        "\(DisplayFormatters.compactTokenString(value, language: language)) \(L.text("tokens", language))"
    }

    private var dateText: String {
        DisplayFormatters.localizedDateString(for: bar.day, template: isHourly ? "yMMMd HH:mm" : "yMMMd", language: language)
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
            swiftUIChartLocation(
                fromAppKit: convert(event.locationInWindow, from: nil),
                plotHeight: bounds.height
            )
        }
    }
}

private func swiftUIChartLocation(fromAppKit location: CGPoint, plotHeight: CGFloat) -> CGPoint {
    CGPoint(x: location.x, y: plotHeight - location.y)
}

private func chartTooltipPosition(cursor: CGPoint, calloutSize: CGSize, plotSize: CGSize) -> CGPoint {
    let offset = CGSize(width: 16, height: 8)
    let halfWidth = calloutSize.width / 2
    let halfHeight = calloutSize.height / 2
    let proposedX = cursor.x + calloutSize.width + offset.width <= plotSize.width
        ? cursor.x + halfWidth + offset.width
        : cursor.x - halfWidth - offset.width
    let proposedY = cursor.y + calloutSize.height + offset.height <= plotSize.height
        ? cursor.y + halfHeight + offset.height
        : cursor.y - halfHeight - offset.height
    return CGPoint(
        x: min(max(halfWidth, proposedX), max(halfWidth, plotSize.width - halfWidth)),
        y: min(max(halfHeight, proposedY), max(halfHeight, plotSize.height - halfHeight))
    )
}

private func chartSlotIndex(at x: CGFloat, plotWidth: CGFloat, count: Int) -> Int? {
    guard count > 0, plotWidth > 0, x >= 0, x < plotWidth else { return nil }
    return min(Int(x / (plotWidth / CGFloat(count))), count - 1)
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
                .font(.agentBar(size: 13, weight: .bold))
            if let subtitle {
                Text(subtitle)
                    .font(.agentBar(size: 12))
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
            .font(.agentBar(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}

struct LoadingAccountPanel: View {
    var title: String
    var subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.agentBar(size: 13, weight: .bold))
                Text(subtitle)
                    .font(.agentBar(size: 11))
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

    var body: some View {
        HStack(spacing: 8) {
            MiniSummaryChip(
                title: localized("most_constrained"),
                value: summary.mostConstrainedAccount?.displayNameWithWorkspace(language: language) ?? "--",
                color: AgentBarPalette.quotaColor(remaining: summary.mostConstrainedAccount?.mostConstrainedRemainingPercent)
            )
            if let fiveHour = summary.lowestFiveHourRemaining {
                MiniSummaryChip(
                    title: localized("lowest_5h"),
                    value: DisplayFormatters.percentString(fiveHour),
                    color: AgentBarPalette.quotaColor(remaining: fiveHour)
                )
            }
            MiniSummaryChip(
                title: localized("lowest_weekly"),
                value: DisplayFormatters.percentString(summary.lowestWeeklyRemaining),
                color: AgentBarPalette.quotaColor(remaining: summary.lowestWeeklyRemaining)
            )
            MiniSummaryChip(
                title: localized("resets"),
                value: "\(resetCreditsCount)",
                color: AgentBarPalette.primary
            )
            MiniSummaryChip(
                title: localized("accounts"),
                value: "\(summary.accountCount)",
                color: AgentBarPalette.tertiary
            )
        }
    }

    private func localized(_ key: String) -> String {
        L.text(key, language)
    }
}

private struct QuotaPressurePanel: View {
    var pressure: QuotaPressureInsight
    var history: QuotaCapacityHistory
    var language: AppLanguage
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text(localized("quota_pressure"))
                    .font(.agentBar(size: 16, weight: .bold))
                Button {
                    showsDetails.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.agentBar(size: 12, weight: .bold))
                        .foregroundStyle(AgentBarPalette.primary)
                }
                .tactilePlainButton()
                .accessibilityLabel(localized("view_details"))
                .popover(isPresented: $showsDetails, arrowEdge: .trailing) {
                    QuotaPressureDetailsPopover(pressure: pressure, language: language, tint: severityColor)
                }
                Spacer(minLength: 0)
            }

            Text(severityTitle)
                .font(.agentBar(size: 20, weight: .bold))
                .foregroundStyle(severityColor)
                .padding(.top, 16)

            metricLabel(language == .chinese ? "预估剩余 Token 额度" : "Estimated tokens left")
                .padding(.top, 14)
            Text(estimatedRemainingTokensText)
                .font(.agentBar(size: 21, weight: .bold))
                .monospacedDigit()
                .padding(.top, 5)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.09))
                    Capsule()
                        .fill(AgentBarPalette.primary)
                        .frame(width: proxy.size.width * remainingProgress)
                }
            }
            .frame(height: 6)
            .padding(.top, 12)

            HStack(spacing: 8) {
                metricLabel(language == .chinese ? "基于用量估算" : "Based on usage")
                Spacer(minLength: 0)
                Text("\(DisplayFormatters.percentString(remainingProgress * 100)) \(language == .chinese ? "剩余" : "left")")
                    .font(.agentBar(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.top, 8)

            runwayTimeline
                .padding(.top, 20)

            Divider()
                .padding(.top, 18)

            if let fiveHourWindow = pressure.activeAccount?.fiveHourWindow {
                quotaWindowRow(fiveHourWindow)
                    .padding(.vertical, 12)
                Divider()
            }

            if let weeklyWindow = pressure.activeAccount?.weeklyWindow {
                quotaWindowRow(weeklyWindow)
                    .padding(.vertical, 12)
            }

            Spacer(minLength: 18)

            metricLabel(language == .chinese ? "周额度容量估算趋势" : "Estimated weekly capacity trend")
                .padding(.bottom, 8)

            if sparklineValues.count > 1 {
                QuotaPressureSparkline(values: sparklineValues)
                    .frame(height: 64)
            } else {
                Text(language == .chinese ? "等待容量样本" : "Waiting for capacity samples")
                    .font(.agentBar(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
            }

            Button {
                showsDetails = true
            } label: {
                HStack(spacing: 5) {
                    Text(language == .chinese ? "查看额度详情" : "View quota details")
                    Image(systemName: "arrow.right")
                        .font(.agentBar(size: 9, weight: .bold))
                }
                .font(.agentBar(size: 10, weight: .bold))
                .foregroundStyle(AgentBarPalette.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .tactilePlainButton()
            .padding(.top, 10)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .agentBarPanel()
    }

    private var runwayTimeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            timelineMilestone(
                title: localized("now"),
                detail: currentUsageText,
                filled: true
            )
            timelineMilestone(
                title: language == .chinese ? "预计耗尽" : "Estimated exhaustion",
                detail: projectedExhaustionText,
                filled: false,
                markerTopPadding: 16
            )

            Text(gapText)
                .font(.agentBar(size: 10, weight: .bold))
                .foregroundStyle(gapColor)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(gapColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .padding(.leading, 32)
                .padding(.vertical, 8)

            timelineMilestone(
                title: language == .chinese ? "额度重置" : "Quota reset",
                detail: resetText,
                filled: true
            )
        }
        .background(alignment: .leading) {
            Rectangle()
                .fill(AgentBarPalette.primary.opacity(0.70))
                .frame(width: 1.5)
                .padding(.leading, 5.25)
                .padding(.top, 8)
                .padding(.bottom, 23)
        }
    }

    private func timelineMilestone(
        title: String,
        detail: String,
        filled: Bool,
        markerTopPadding: CGFloat = 2
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(filled ? AgentBarPalette.primary : AgentBarDesign.cardBackground)
                .overlay {
                    Circle()
                        .strokeBorder(AgentBarPalette.primary, lineWidth: 1.5)
                }
                .frame(width: 12, height: 12)
                .padding(.top, markerTopPadding)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.agentBar(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.agentBar(size: 12, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
    }

    private func quotaWindowRow(_ window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(window.kind == .fiveHour ? L.text("five_hour", language) : localized("weekly"))
                    .font(.agentBar(size: 10, weight: .bold))
                Spacer(minLength: 0)
                Text("\(DisplayFormatters.percentString(window.remainingPercent)) \(language == .chinese ? "剩余" : "left")")
                    .font(.agentBar(size: 10, weight: .bold))
                    .monospacedDigit()
            }

            Text(window.resetLine(language: language))
                .font(.agentBar(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var projectedRisk: (date: Date, window: UsageWindow)? {
        let pairs: [(Date?, UsageWindow?)] = [
            (pressure.projectedFiveHourExhaustion, pressure.activeAccount?.fiveHourWindow),
            (pressure.projectedWeeklyExhaustion, pressure.activeAccount?.weeklyWindow)
        ]
        return pairs
            .compactMap { date, window -> (date: Date, window: UsageWindow)? in
                guard let date, let window else { return nil }
                guard window.resetsAt.map({ date < $0 }) ?? true else { return nil }
                return (date, window)
            }
            .min { $0.date < $1.date }
    }

    private var timelineWindow: UsageWindow? {
        projectedRisk?.window ?? [
            pressure.activeAccount?.fiveHourWindow,
            pressure.activeAccount?.weeklyWindow
        ]
        .compactMap { $0 }
        .min { $0.remainingPercent < $1.remainingPercent }
    }

    private var currentUsageText: String {
        let time = DisplayFormatters.localizedDateString(
            for: Date(),
            template: "HH:mm",
            language: language
        )
        let used = DisplayFormatters.percentString(timelineWindow?.usedPercent)
        return language == .chinese ? "\(time) · 已用 \(used)" : "\(time) · \(used) used"
    }

    private var projectedExhaustionText: String {
        guard let date = projectedRisk?.date else {
            return language == .chinese ? "暂无耗尽风险" : "No risk projected"
        }
        return compactDateTime(date)
    }

    private var resetText: String {
        guard let date = timelineWindow?.resetsAt else {
            return language == .chinese ? "时间未知" : "Time unknown"
        }
        return compactDateTime(date)
    }

    private var gapText: String {
        guard let exhaustion = projectedRisk?.date,
              let reset = projectedRisk?.window.resetsAt,
              reset > exhaustion
        else {
            return language == .chinese ? "预计可撑过重置" : "Expected to reach reset"
        }
        let duration = durationText(reset.timeIntervalSince(exhaustion))
        return language == .chinese ? "可能中断 \(duration)" : "Possible gap \(duration)"
    }

    private var gapColor: Color {
        projectedRisk == nil ? .green : severityColor
    }

    private func compactDateTime(_ date: Date) -> String {
        DisplayFormatters.localizedDateString(
            for: date,
            template: "MMM d HH:mm",
            language: language
        )
    }

    private func durationText(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int(ceil(interval / 60)))
        guard minutes >= 60 else {
            return language == .chinese ? "\(minutes) 分钟" : "\(minutes) min"
        }
        let hours = Int(ceil(Double(minutes) / 60))
        return language == .chinese ? "\(hours) 小时" : "\(hours) hr"
    }

    private var severityColor: Color {
        switch pressure.severity {
        case .critical: .red
        case .warning: .orange
        case .ok: .green
        }
    }

    private var severityTitle: String {
        switch (pressure.severity, language) {
        case (.critical, .chinese): "高风险"
        case (.warning, .chinese): "注意"
        case (.ok, .chinese): "健康"
        case (.critical, _): "High risk"
        case (.warning, _): "Watch"
        case (.ok, _): "Healthy"
        }
    }

    private var estimatedRemainingTokensText: String {
        guard let account = pressure.activeAccount,
              let window = timelineWindow,
              let sample = history.samples.last(where: { sample in
                  sample.accountID == account.id &&
                      (window.kind == .fiveHour
                          ? sample.estimatedFiveHourTotalTokens != nil
                          : sample.estimatedWeeklyTotalTokens != nil)
              }),
              let total = window.kind == .fiveHour
                  ? sample.estimatedFiveHourTotalTokens
                  : sample.estimatedWeeklyTotalTokens
        else { return "--" }
        let remaining = Int((Double(total) * window.remainingPercent / 100).rounded())
        return DisplayFormatters.compactTokenString(remaining, language: language)
    }

    private var remainingProgress: Double {
        let remaining = [
            pressure.activeAccount?.fiveHourWindow?.remainingPercent,
            pressure.activeAccount?.weeklyWindow?.remainingPercent
        ]
        .compactMap { $0 }
        .min() ?? 0
        return min(max(remaining / 100, 0), 1)
    }

    private var sparklineValues: [Int] {
        history.samples.suffix(24).compactMap(\.estimatedWeeklyTotalTokens)
    }

    private func metricLabel(_ text: String) -> some View {
        Text(text)
            .font(.agentBar(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func localized(_ key: String) -> String {
        L.text(key, language)
    }
}

private struct QuotaPressureSparkline: View {
    var values: [Int]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let minimum = values.min(), let maximum = values.max() else { return }
            let range = max(1, maximum - minimum)
            let xStep = size.width / CGFloat(values.count - 1)
            var path = Path()

            for (index, value) in values.enumerated() {
                let point = CGPoint(
                    x: CGFloat(index) * xStep,
                    y: size.height - CGFloat(value - minimum) / CGFloat(range) * size.height
                )
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }

            context.stroke(
                path,
                with: .color(AgentBarPalette.primary),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
        .accessibilityHidden(true)
    }
}

private struct QuotaPressureDetailsPopover: View {
    var pressure: QuotaPressureInsight
    var language: AppLanguage
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(localized("quota_details"), systemImage: "gauge.with.dots.needle.67percent")
                .font(.agentBar(size: 13, weight: .bold))
                .foregroundStyle(tint)
            detailRow(localized("active_account"), accountText(pressure.activeAccount))
            detailRow(localized("recommended_account"), accountText(pressure.recommendedAccount))
            if showsFiveHour {
                detailRow("5H", pressure.projectedFiveHourExhaustion.map(exhaustionText) ?? localized("not_projected"))
            }
            detailRow(localized("weekly"), pressure.projectedWeeklyExhaustion.map(exhaustionText) ?? localized("not_projected"))
            if showsFiveHour {
                detailRow(localized("rotation"), pressure.shouldTriggerRotation ? localized("will_trigger") : localized("standby"))
            }
            if let reason = pressure.recommendationReason, !reason.isEmpty {
                Text(reason)
                    .font(.agentBar(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.agentBar(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.agentBar(size: 11, weight: .semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private func accountText(_ account: UsageAccount?) -> String {
        guard let account else { return "--" }
        let weekly = DisplayFormatters.percentString(account.weeklyWindow?.remainingPercent)
        guard showsFiveHour else {
            return "\(account.displayNameWithWorkspace(language: language)) · \(localized("weekly")) \(weekly)"
        }
        let five = DisplayFormatters.percentString(account.fiveHourWindow?.remainingPercent)
        return "\(account.displayNameWithWorkspace(language: language)) · 5H \(five) · \(localized("weekly")) \(weekly)"
    }

    private var showsFiveHour: Bool {
        pressure.activeAccount?.fiveHourWindow != nil
    }

    private func exhaustionText(_ date: Date) -> String {
        DisplayFormatters.relativeString(for: date, language: language)
    }

    private func localized(_ key: String) -> String {
        L.text(key, language)
    }
}

private struct TopUsagePanel: View {
    private enum Category: String, CaseIterable, Identifiable {
        case sessions
        case projects
        case days
        case models

        var id: Self { self }
    }

    var breakdown: TopUsageBreakdown
    var language: AppLanguage
    var onSelectSession: (String) -> Void
    @State private var category: Category = .sessions

    var body: some View {
        if breakdown.sessions.isEmpty && breakdown.projects.isEmpty && breakdown.days.isEmpty && breakdown.models.isEmpty {
            EmptyPanelMessage(L.text("no_usage_data", language))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Picker(L.text("top_usage", language), selection: $category) {
                    ForEach(Category.allCases) { category in
                        Text(localized(category.rawValue))
                            .tag(category)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Text(summaryText)
                    .font(.agentBar(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                if visibleRows.isEmpty {
                    EmptyPanelMessage(L.text("no_usage_data", language))
                } else {
                    let maximum = max(1, visibleRows.map(\.tokens).max() ?? 1)
                    VStack(spacing: 16) {
                        ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, row in
                            if category == .sessions {
                                Button {
                                    onSelectSession(row.label)
                                } label: {
                                    topUsageRow(index: index, row: row, maximum: maximum)
                                }
                                .tactilePlainButton(pressedScale: 0.99)
                            } else {
                                topUsageRow(index: index, row: row, maximum: maximum)
                            }
                        }
                    }
                }
            }
        }
    }

    private func topUsageRow(index: Int, row: TopUsageRow, maximum: Int) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("\(index + 1)")
                    .font(.agentBarMono(size: 18, weight: .semibold))
                    .foregroundStyle(AgentBarPalette.primary)
                    .frame(width: 24, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(.agentBar(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if category == .sessions, let lastUsedAt = row.lastUsedAt {
                        Text("\(localized("latest")) \(DisplayFormatters.relativeString(for: lastUsedAt, language: language))")
                            .font(.agentBar(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(DisplayFormatters.compactTokenString(row.tokens, language: language))
                        .font(.agentBarMono(size: 12, weight: .bold))
                        .monospacedDigit()
                    if let estimatedCostUSD = row.estimatedCostUSD {
                        Text(DisplayFormatters.costString(estimatedCostUSD))
                            .font(.agentBar(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Text("\(Int((row.share * 100).rounded()))%")
                    .font(.agentBar(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                    Capsule()
                        .fill(selectedColor)
                        .frame(width: max(3, proxy.size.width * CGFloat(row.tokens) / CGFloat(maximum)))
                }
            }
            .frame(height: 4)
            .padding(.leading, 34)
        }
        .contentShape(Rectangle())
    }

    private var selectedRows: [TopUsageRow] {
        switch category {
        case .sessions: breakdown.sessions
        case .projects: breakdown.projects
        case .days: breakdown.days
        case .models: breakdown.models
        }
    }

    private var visibleRows: [TopUsageRow] {
        selectedRows
    }

    private var selectedColor: Color {
        switch category {
        case .sessions, .models: AgentBarPalette.primary
        case .projects: AgentBarPalette.tertiary
        case .days: AgentBarPalette.secondary
        }
    }

    private var summaryText: String {
        let share = Int((visibleRows.reduce(0) { $0 + $1.share } * 100).rounded())
        return String(
            format: localized("top_usage_summary"),
            visibleRows.count,
            localized(category.rawValue),
            share
        )
    }

    private func localized(_ key: String) -> String {
        L.text(key, language)
    }
}

private struct AccountHealthCenterPanel: View {
    var health: AccountHealthCenter
    var language: AppLanguage
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
                            .font(.agentBar(size: 12, weight: .bold))
                            .foregroundStyle(color(for: row))
                            .frame(width: 16)
                            .padding(.top, 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.agentBar(size: 12, weight: .bold))
                                .lineLimit(1)
                            Text(row.detail)
                                .font(.agentBar(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(row.workspaceLines, id: \.self) { line in
                                Text(line)
                                    .font(.agentBar(size: 10, weight: .medium))
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
                HStack(spacing: 8) {
                    Button {
                        onLogin(accountID)
                    } label: {
                        Label(localized("login"), systemImage: "person.crop.circle.badge.exclamationmark")
                            .font(.agentBar(size: 13, weight: .bold))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 40, maxHeight: 40)
                            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .foregroundStyle(.red)
                    .tactilePlainButton()
                    .agentBarPanel(cornerRadius: 12)
                    Button(role: .destructive) {
                        onRemove(accountID)
                    } label: {
                        Image(systemName: "trash")
                            .font(.agentBar(size: 13, weight: .bold))
                            .frame(width: 40, height: 40)
                            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .foregroundStyle(.red)
                    .tactilePlainButton()
                    .agentBarPanel(cornerRadius: 12)
                    .help(localized("remove"))
                }
            }
        case .dataSource:
            Button {
                onRefresh()
            } label: {
                Label(localized("refresh"), systemImage: "arrow.clockwise")
                    .font(.agentBar(size: 13, weight: .bold))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40, maxHeight: 40)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .foregroundStyle(AgentBarPalette.primary)
            .tactilePlainButton()
            .agentBarPanel(cornerRadius: 12)
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
        case .ok: AgentBarPalette.primary
        }
    }

    private func localized(_ key: String) -> String {
        L.text(key, language)
    }
}

private struct ResetExpiryRowData: Identifiable {
    var id: String
    var account: String
    var index: Int
    var expiresAt: Date?
}

private struct ResetExpiryRow: View {
    var row: ResetExpiryRowData
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.agentBar(size: 12, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(row.account) · \(L.text("reset", language)) \(row.index)")
                    .font(.agentBar(size: 12, weight: .bold))
                    .lineLimit(1)
                Text(detail)
                    .font(.agentBar(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(badge)
                .font(.agentBar(size: 10, weight: .bold))
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
        return AgentBarPalette.primary
    }
}

private struct AccountAvatar: View {
    var text: String
    var color: Color
    var size: CGFloat

    var body: some View {
        Text(initial)
            .font(.agentBar(size: max(12, size * 0.42), weight: .bold))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let account {
                HStack(spacing: 10) {
                    AccountAvatar(text: account.providerAccountDisplayName, color: AgentBarPalette.primary, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.providerAccountDisplayName)
                            .font(.agentBar(size: 14, weight: .bold))
                            .lineLimit(1)
                        Text(account.accountTypeLine(language: language))
                            .font(.agentBar(size: 11, weight: .semibold))
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
                if let fiveHour = account.fiveHourWindow {
                    infoRow("5H", windowText(fiveHour))
                }
                if let weekly = account.weeklyWindow {
                    infoRow(language == .chinese ? "本周" : "Weekly", windowText(weekly))
                }
                if let resetCredits = account.resetCredits {
                    infoRow(L.text("resets", language), resetCredits.summaryLine(language: language))
                }
                if let usage = account.grokSubscriptionUsage {
                    ForEach(usage.summaryLines(language: language), id: \.self) { line in
                        infoRow("Grok", line)
                    }
                }
                if let usage = account.cursorSubscriptionUsage {
                    ForEach(usage.summaryLines(language: language), id: \.self) { line in
                        infoRow("Cursor", line)
                    }
                }
                infoRow(L.text("total_tokens", language), DisplayFormatters.compactTokenString(account.tokens.total, language: language))
                infoRow(L.text("cost", language), account.estimatedCostUSD.map(DisplayFormatters.costString) ?? L.text("no_cost_data", language))
                infoRow(L.text("last_activity", language), account.lastActivityLine(language: language).replacingOccurrences(of: "\(L.text("last_activity", language)): ", with: ""))
                if let source = account.accessTokenSource {
                    infoRow(L.text("token_source", language), source)
                }
                infoRow(language == .chinese ? "数据源" : "Source", account.sourceDescription)
            } else {
                Text(L.text("current_account", language))
                    .font(.agentBar(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 318, alignment: .leading)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.agentBar(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.agentBar(size: 11, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func windowText(_ window: UsageWindow) -> String {
        let reset = window.resetsAt.map { DisplayFormatters.relativeString(for: $0, language: language) } ?? "--"
        return "\(DisplayFormatters.percentString(window.remainingPercent)) · \(reset)"
    }

    private func localized(_ key: String) -> String {
        L.text(key, language)
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
                            .font(.agentBar(size: 17, weight: .bold))
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
                    .font(.agentBar(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.agentBar(size: 18, weight: .bold))
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
                .font(.agentBar(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(value)
                    .font(.agentBar(size: 11, weight: .bold))
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
                isSwitching: switchingAccountID == account.id,
                onSwitch: { onSwitch(account) },
                onLogin: { onLogin(account) }
            )
        }
    }

    private var displayGroupHeader: some View {
        HStack(spacing: 6) {
            Text(group.title)
                .font(.agentBar(size: 11, weight: .bold))
                .lineLimit(1)
            Text("\(group.accounts.count) \(L.text("workspaces", language))")
                .font(.agentBar(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 2)
    }
}

private struct AccountLimitGroupView: View {
    var account: UsageAccount
    var language: AppLanguage
    var isSwitching: Bool
    var onSwitch: () -> Void
    var onLogin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                AccountAvatar(text: account.providerAccountDisplayName, color: account.isActive ? AgentBarPalette.primary : AgentBarPalette.secondary, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(account.providerAccountDisplayName)
                            .font(.agentBar(size: 13, weight: .bold))
                            .lineLimit(1)
                        if account.isActive {
                            Text(L.text("current", language))
                                .font(.agentBar(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AgentBarPalette.primary, in: Capsule())
                        }
                    }
                    Text(accountDetailLine)
                        .font(.agentBar(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ForEach(account.workspaceLines(language: language), id: \.self) { line in
                        Text(line)
                            .font(.agentBar(size: 10))
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
                } else if !account.isActive, account.supportsAccountSwitching {
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
                    .tint(AgentBarPalette.primary)
                    .disabled(isSwitching)
                    .pointingHandCursor(enabled: !isSwitching)
                } else if !account.supportsAccountSwitching {
                    Text(L.text("monitor_only", language))
                        .font(.agentBar(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(account.service.rawValue)
                            .font(.agentBar(size: 10, weight: .bold))
                        Text(account.accountTypeValue(language: language))
                            .font(.agentBar(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let warning = account.loginWarningLine(language: language) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.agentBar(size: 10, weight: .bold))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            if account.fiveHourWindow != nil || account.weeklyWindow != nil {
                HStack(spacing: 12) {
                    UsageWindowGauge(title: L.text("five_hour", language), window: account.fiveHourWindow, language: language)
                    UsageWindowGauge(title: L.text("weekly", language), window: account.weeklyWindow, language: language)
                }
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
                .font(.agentBar(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }

            if let usage = account.grokSubscriptionUsage {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(usage.summaryLines(language: language), id: \.self) { line in
                        Label(line, systemImage: "creditcard")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.agentBar(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }

            if let usage = account.cursorSubscriptionUsage {
                CursorSubscriptionGauge(usage: usage, language: language)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(usage.summaryLines(language: language, includesIncludedUsage: false), id: \.self) { line in
                        Label(line, systemImage: "creditcard")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.agentBar(size: 10, weight: .semibold))
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
                .stroke(account.needsLogin ? Color.red.opacity(0.70) : (account.isActive ? AgentBarPalette.primary.opacity(0.25) : Color.primary.opacity(0.06)), lineWidth: account.needsLogin ? 1.5 : 1)
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
                        .font(.agentBar(size: 16, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .contentShape(Rectangle())
            }
            .tactilePlainButton(pressedScale: 1)
            .accessibilityLabel(L.text("manage_loaded_accounts", language))
            .accessibilityValue(currentAccount?.providerAccountDisplayName ?? "--")
            .help(L.text("manage_loaded_accounts_subtitle", language))

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
                    .font(.agentBar(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(account?.providerAccountDisplayName ?? "--")
                    .font(.agentBar(size: 13, weight: .semibold))
                    .lineLimit(1)
                if let workspaceLine = account?.workspaceLine(language: language) {
                    Text(workspaceLine)
                        .font(.agentBar(size: 10, weight: .medium))
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
                    Text(account.providerAccountDisplayName)
                        .font(.agentBar(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if account.isActive {
                        Text(L.text("current", language))
                            .font(.agentBar(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(accountIdentityLine)
                    .font(.agentBar(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ForEach(account.workspaceLines(language: language), id: \.self) { line in
                    Text(line)
                        .font(.agentBar(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if account.supportsAccountRemoval {
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
            } else {
                Text(L.text("monitor_only", language))
                    .font(.agentBar(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
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
                    .font(.agentBar(size: 15, weight: .bold))
                Text(subtitle)
                    .font(.agentBar(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.62))
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

private struct MenuBarStatusPreview: View {
    var title: String
    var enabledServices: [UsageService]
    var showsProviderStatus: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: AppLogo.menuBarImage())
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)

            Text(title)
                .font(.agentBarMono(size: 12, weight: .semibold))
                .monospacedDigit()

            if showsProviderStatus {
                HStack(spacing: 4) {
                    ForEach(UsageService.allCases) { service in
                        Image(nsImage: ProviderIcon.image(for: service))
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 10, height: 10)
                            .opacity(enabledServices.contains(service) ? 0.95 : 0.22)
                            .accessibilityHidden(true)
                    }

                    Divider()
                        .frame(height: 11)
                        .opacity(0.34)

                    Text("\(enabledServices.count)")
                        .font(.agentBarMono(size: 10, weight: .semibold))
                        .monospacedDigit()
                }
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(Color.primary.opacity(0.07), in: Capsule())
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .background(.thinMaterial, in: Capsule())
    }
}

private struct MenuBarProviderToggleCard: View {
    var service: UsageService
    var hasData: Bool
    var language: AppLanguage
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(nsImage: ProviderIcon.image(for: service))
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.primary.opacity(0.88))
                    .frame(width: 24, height: 24)
                    .frame(width: 42, height: 42)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(service.rawValue)
                        .font(.agentBar(size: 13, weight: .semibold))
                    HStack(spacing: 7) {
                        Circle()
                            .fill(isOn ? AgentBarPalette.primary : Color.secondary)
                            .frame(width: 7, height: 7)
                        Text(statusText)
                            .font(.agentBar(size: 11))
                            .foregroundStyle(Color.primary.opacity(0.62))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .agentBarPanel()
        .accessibilityHint(statusText)
    }

    private var statusText: String {
        if !isOn {
            return L.text("menu_bar_not_included", language)
        }
        return L.text(hasData ? "menu_bar_included" : "menu_bar_included_no_data", language)
    }
}

private struct ProviderSettingsCard: View {
    var service: UsageService
    var subtitle: String
    var statusColor: Color
    var actionTitle: String
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: ProviderIcon.image(for: service))
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.primary.opacity(0.88))
                    .frame(width: 24, height: 24)
                    .frame(width: 42, height: 42)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(service.rawValue)
                        .font(.agentBar(size: 13, weight: .semibold))
                    HStack(spacing: 7) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)
                        Text(subtitle)
                            .font(.agentBar(size: 11))
                            .foregroundStyle(Color.primary.opacity(0.62))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack {
                Spacer()
                Button(action: action) {
                    HStack(spacing: 7) {
                        Image(systemName: "terminal")
                        Text(actionTitle)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.36))
                    }
                    .font(.agentBar(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .agentBarPanel()
    }
}

private struct SettingsRow<Content: View>: View {
    var title: String
    var subtitle: String
    var showsDivider = true
    @ViewBuilder var control: () -> Content

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.agentBar(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.agentBar(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.62))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            control()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .settingsRowStyle(showsDivider: showsDivider)
    }
}

private struct SettingsToggleRow: View {
    var title: String
    var subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.agentBar(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.agentBar(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.62))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .accessibilityRepresentation {
            Toggle(title, isOn: $isOn)
                .accessibilityHint(subtitle)
        }
        .settingsRowStyle()
    }
}

private struct PopoverMetricPicker: View {
    @ObservedObject var settings: SettingsStore
    var language: AppLanguage

    private var availableMetrics: [PopoverMetric] {
        PopoverMetric.allCases.filter { !settings.popoverMetrics.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(L.text("selected_metrics", language))
                            .font(.agentBar(size: 11, weight: .semibold))
                        Text("\(settings.popoverMetrics.count)/\(SettingsStore.maximumPopoverMetricCount)")
                            .font(.agentBar(size: 10, weight: .bold))
                            .foregroundStyle(AgentBarPalette.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                AgentBarPalette.primary.opacity(0.10),
                                in: Capsule()
                            )
                    }
                    Text(L.text("popover_metrics_subtitle", language))
                        .font(.agentBar(size: 10))
                        .foregroundStyle(Color.primary.opacity(0.58))
                        .lineLimit(1)
                }

                Spacer()

                Menu {
                    ForEach(availableMetrics) { metric in
                        Button {
                            settings.setPopoverMetric(metric, enabled: true)
                        } label: {
                            Label(metric.title(language), systemImage: metric.systemImage)
                        }
                    }
                } label: {
                    Label(L.text("add_metric", language), systemImage: "plus")
                        .font(.agentBar(size: 11, weight: .semibold))
                        .foregroundStyle(AgentBarPalette.primary)
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(
                            AgentBarPalette.primary.opacity(0.10),
                            in: Capsule()
                        )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(
                    availableMetrics.isEmpty
                        || settings.popoverMetrics.count >= SettingsStore.maximumPopoverMetricCount
                )
                .help(L.text("available_metrics", language))
            }

            List {
                ForEach(settings.popoverMetrics) { metric in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        Image(systemName: metric.systemImage)
                            .foregroundStyle(AgentBarPalette.primary)
                            .frame(width: 18)
                            .accessibilityHidden(true)
                        Text(metric.title(language))
                            .font(.agentBar(size: 12, weight: .semibold))
                        Spacer()
                        Button {
                            settings.setPopoverMetric(metric, enabled: false)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(settings.popoverMetrics.count == 1)
                        .accessibilityLabel("\(L.text("remove_metric", language)) \(metric.title(language))")
                    }
                    .frame(height: 30)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .onMove(perform: settings.movePopoverMetrics)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: CGFloat(settings.popoverMetrics.count * 30 + 6))
        }
    }
}

private struct BudgetIntegerField: View {
    @Binding var value: Int
    var language: AppLanguage
    var label: String

    var body: some View {
        HStack(spacing: 6) {
            TextField("0", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                .accessibilityLabel(label)
            Text(L.text("tokens", language))
                .font(.agentBar(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct CodexRotationThresholdControl: View {
    @Binding var threshold: Double
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L.text("codex_rotation_threshold", language))
    }
}

private struct BudgetCostField: View {
    @Binding var value: Double
    var language: AppLanguage
    var label: String

    var body: some View {
        HStack(spacing: 6) {
            Text("$")
                .font(.agentBar(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("0", value: $value, format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 86)
                .accessibilityLabel(label)
        }
    }
}

private extension View {
    func settingsRowStyle(showsDivider: Bool = true) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, settingsControlLeadingInset)
            .padding(.trailing, settingsControlTrailingInset)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if showsDivider {
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 1)
                        .padding(.leading, settingsControlLeadingInset)
                }
            }
    }

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
    var color: Color
}

private struct ServiceQuotaSummary: Identifiable {
    var id: UsageService { service }
    var service: UsageService
    var accountCount: Int
    var remainingPercent: Double
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
        self.accountName = account.providerAccountDisplayName
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

extension UsageRange {
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
