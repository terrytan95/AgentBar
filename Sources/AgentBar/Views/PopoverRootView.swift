import AppKit
import SwiftUI

struct ResizablePopoverRootView: View {
    @ObservedObject var store: UsageStore
    var maximumHeight: CGFloat
    var onQuit: () -> Void
    var onHeightChange: (CGFloat) -> Void
    @ObservedObject private var settings: SettingsStore

    init(
        store: UsageStore,
        maximumHeight: CGFloat,
        onQuit: @escaping () -> Void = { NSApplication.shared.terminate(nil) },
        onHeightChange: @escaping (CGFloat) -> Void
    ) {
        self.store = store
        self.maximumHeight = maximumHeight
        self.onQuit = onQuit
        self.onHeightChange = onHeightChange
        self.settings = store.settings
    }

    var body: some View {
        PopoverRootView(
            store: store,
            onQuit: onQuit
        )
        .frame(width: PopoverLayout.width)
        .frame(minHeight: PopoverLayout.minimumHeight, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            resizeBorder
        }
        .onAppear {
            refreshPopoverLayout()
        }
        .onChange(of: store.accounts.count) { _, _ in
            applyAutomaticHeight()
        }
        .onChange(of: store.uiDataSourceSnapshots.count) { _, _ in
            applyAutomaticHeight()
        }
        .onChange(of: settings.popoverHeight) { _, newHeight in
            onHeightChange(CGFloat(newHeight))
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func refreshPopoverLayout() {
        let height = CGFloat(settings.popoverHeight)
        onHeightChange(height)
        DispatchQueue.main.async {
            onHeightChange(height)
        }
    }

    private func applyAutomaticHeight() {
        let height = PopoverLayout.height(
            accountCount: store.accounts.count,
            sourceCount: store.uiDataSourceSnapshots.count,
            maximumHeight: maximumHeight
        )
        settings.popoverHeight = Double(height)
        onHeightChange(height)
    }

    private var resizeBorder: some View {
        ZStack(alignment: .bottom) {
            PopoverResizeHandle(
                startHeight: CGFloat(settings.popoverHeight),
                maxHeight: maximumHeight
            ) { height, isFinal in
                onHeightChange(height)
                if isFinal {
                    settings.updatePopoverMaximumHeight(Double(maximumHeight))
                    settings.popoverHeight = Double(height)
                    onHeightChange(CGFloat(settings.popoverHeight))
                }
            }
            .frame(height: 12)
            .accessibilityLabel(L.text("resize_popover", store.language))

            Capsule()
                .fill(AgentBarPalette.primary.opacity(0.30))
                .frame(width: 48, height: 4)
                .padding(.bottom, 3)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 12)
    }
}

struct PopoverRootView: View {
    @ObservedObject var store: UsageStore
    var onQuit: () -> Void = { NSApplication.shared.terminate(nil) }
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isConfirmingQuit = false

    private var stateSwapAnimation: Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: AgentBarDesign.durationNormal)
    }

    private func stateSwapTransition(anchor: UnitPoint) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.97, anchor: anchor))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, PopoverLayout.horizontalInset)
                .padding(.vertical, 12)
            hairline
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if store.settings.showPopoverOverviewSection {
                        quickSummarySection
                    }
                    accountSection
                }
                .padding(.horizontal, PopoverLayout.horizontalInset)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            hairline
            footer
                .padding(.horizontal, PopoverLayout.horizontalInset)
                .frame(height: 62)
                .background(AgentBarDesign.panelHighlight)
        }
        .agentBarGlassSurface(
            isEnabled: store.settings.useTranslucentAppearance,
            opaqueBackground: AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
        )
        .onDisappear {
            isConfirmingQuit = false
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(hairlineColor)
            .frame(height: 1)
    }

    private var hairlineColor: Color {
        colorScheme == .dark ? AgentBarDesign.hairline : Color(nsColor: .separatorColor).opacity(0.72)
    }

    private var dataSourceHealth: DataSourceHealthSummary {
        UsageInsights.dataSourceHealth(
            snapshots: Dictionary(uniqueKeysWithValues: store.uiDataSourceSnapshots.map { ($0.service, $0) })
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppLogo.image())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("AgentBar")
                    .font(.agentBarDisplay(size: 17, weight: .bold))
                Text(store.popoverHeaderQuotaTitle)
                    .font(.agentBar(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let activeAccount = store.activeAccount {
                    Text("\(L.text("current_account", store.language)): \(activeAccount.displayNameWithWorkspace(language: store.language))")
                        .font(.agentBar(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                store.refresh(force: true)
            } label: {
                Group {
                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .frame(width: 40, height: 40)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .font(.agentBar(size: 14, weight: .bold))
            .foregroundStyle(AgentBarPalette.primary)
            .tactilePlainButton()
            .agentBarPanel(cornerRadius: 12)
            .help(L.text("refresh", store.language))
        }
    }

    private var accountSection: some View {
        let isLoading = store.isLoadingAccountInformation && store.accounts.isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            Text(L.text("accounts", store.language))
                .font(.agentBar(size: 13, weight: .bold))
            Group {
                if isLoading {
                    PopoverLoadingRow(title: L.text("loading_accounts", store.language), subtitle: L.text("loading_account_info_subtitle", store.language))
                        .transition(stateSwapTransition(anchor: .top))
                } else {
                    ForEach(store.accountDisplayGroups()) { group in
                        PopoverAccountDisplayGroupView(
                            group: group,
                            language: store.language,
                            switchingAccountID: store.switchingAccountID,
                            onSwitch: store.switchActiveAccount,
                            onLogin: { account in store.openLogin(for: account) },
                            onRemove: store.removeAccount
                        )
                    }
                    .transition(stateSwapTransition(anchor: .top))
                }
            }
            .animation(stateSwapAnimation, value: isLoading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.text("overview", store.language))
                .font(.agentBar(size: 13, weight: .bold))
            HStack(spacing: 8) {
                ForEach(store.settings.popoverMetrics) { metric in
                    quickSummaryMetric(metric)
                }
            }

            if dataSourceHealth.issueCount > 0 {
                Label(dataSourceIssueText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func quickSummaryMetric(_ metric: PopoverMetric) -> some View {
        switch metric {
        case .tokens:
            KPIPill(
                title: metric.title(store.language),
                value: DisplayFormatters.tokenString(store.summary.totalTokens),
                systemImage: metric.systemImage,
                tint: AgentBarPalette.primary
            )
        case .cost:
            KPIPill(
                title: metric.title(store.language),
                value: costText(store.summary.estimatedCostUSD),
                systemImage: metric.systemImage,
                tint: AgentBarPalette.secondary
            )
        case .availableResets:
            KPIPill(
                title: metric.title(store.language),
                value: availableResetCountText,
                systemImage: metric.systemImage,
                tint: .purple
            )
        case .earliestRecovery:
            KPIPill(
                title: metric.title(store.language),
                value: earliestRecoveryText,
                systemImage: metric.systemImage,
                tint: AgentBarPalette.primary
            )
        case .currentBalance:
            KPIPill(
                title: metric.title(store.language),
                value: DisplayFormatters.percentString(activeRemainingPercent),
                systemImage: metric.systemImage,
                tint: AgentBarPalette.quotaColor(remaining: activeRemainingPercent)
            )
        }
    }

    private var activeRemainingPercent: Double? {
        guard let account = store.activeAccount,
              account.status == .live,
              !account.needsLogin
        else { return nil }
        return account.mostConstrainedRemainingPercent
    }

    private var availableResetCountText: String {
        let counts = store.accounts
            .filter { $0.status == .live && !$0.needsLogin }
            .compactMap { $0.resetCredits?.visibleCount }
        guard !counts.isEmpty else { return "--" }
        let count = counts.reduce(0, +)
        return store.language == .chinese ? "\(count) 次" : "\(count)"
    }

    private var earliestRecoveryText: String {
        guard let date = earliestRecoveryDate else { return "--" }
        return DisplayFormatters.relativeString(for: date, language: store.language)
    }

    private var earliestRecoveryDate: Date? {
        let now = Date()
        return store.accounts
            .filter { $0.status == .live && !$0.needsLogin }
            .flatMap { [$0.fiveHourWindow?.resetsAt, $0.weeklyWindow?.resetsAt] }
            .compactMap { $0 }
            .filter { $0 > now }
            .min()
    }

    private var dataSourceIssueText: String {
        dataSourceHealth.rows
            .filter { $0.status != .live }
            .map { "\($0.service.rawValue) \($0.status.label(language: store.language))" }
            .joined(separator: " · ")
    }

    private func costText(_ value: Decimal?) -> String {
        value.map { DisplayFormatters.costString($0) } ?? L.text("no_cost_data", store.language)
    }

    private var footer: some View {
        Group {
            if isConfirmingQuit {
                quitConfirmation
                    .transition(stateSwapTransition(anchor: .trailing))
            } else {
                footerActions
                    .transition(stateSwapTransition(anchor: .trailing))
            }
        }
        .padding(.vertical, 8)
        .animation(stateSwapAnimation, value: isConfirmingQuit)
    }

    private var footerActions: some View {
        HStack(spacing: 10) {
            PopoverToolbarButton(title: L.text("statistics", store.language), systemImage: "chart.bar.xaxis") {
                showStatisticsWindow()
            }

            PopoverToolbarButton(title: L.text("settings", store.language), systemImage: "gearshape") {
                showStatisticsWindow(tab: .settings)
            }

            PopoverToolbarButton(title: L.text("quit_app", store.language), systemImage: "power") {
                isConfirmingQuit = true
            }
        }
    }

    private var quitConfirmation: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L.text("quit_app", store.language))
                    .font(.agentBar(size: 12, weight: .bold))
                Text(L.text("quit_app_confirmation", store.language))
                    .font(.agentBar(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button(L.text("cancel", store.language)) {
                isConfirmingQuit = false
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut(.cancelAction)
            .pointingHandCursor()

            Button(L.text("quit_app", store.language), role: .destructive) {
                onQuit()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.red)
            .pointingHandCursor()
        }
        .frame(maxWidth: .infinity)
    }

    private func showStatisticsWindow(tab: DashboardTopTab? = nil) {
        AgentBarWindowPresenter.presentStatisticsWindow(store: store, initialTab: tab ?? .usage)

        if let tab {
            DispatchQueue.main.async {
                DashboardNavigation.request(tab)
            }
        }
    }
}

private enum AgentBarWindowPresenter {
    @MainActor
    private static var statisticsWindow: NSWindow?

    @MainActor
    static func presentStatisticsWindow(store: UsageStore, initialTab: DashboardTopTab) {
        if presentExistingStatisticsWindow() {
            return
        }

        let controller = NSHostingController(
            rootView: StatisticsView(store: store, initialTab: initialTab)
                .frame(minWidth: 1180, minHeight: 760)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1480, height: 940),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.title = "AgentBar"
        window.contentViewController = controller
        window.minSize = NSSize(width: 1180, height: 760)
        window.isReleasedWhenClosed = false
        window.center()
        statisticsWindow = window

        presentExistingStatisticsWindow()
    }

    @MainActor
    @discardableResult
    static func presentExistingStatisticsWindow() -> Bool {
        guard let window = existingStatisticsWindow else { return false }

        NSApp.unhide(nil)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    @MainActor
    private static var existingStatisticsWindow: NSWindow? {
        statisticsWindow
            ?? NSApp.orderedWindows.first(where: isStatisticsWindow)
            ?? NSApp.windows.first(where: isStatisticsWindow)
    }

    @MainActor
    private static func isStatisticsWindow(_ window: NSWindow) -> Bool {
        window.title == "AgentBar" && !(window is NSPanel)
    }
}

struct PopoverAccountDisplayGroupView: View {
    var group: UsageAccountDisplayGroup
    var language: AppLanguage
    var switchingAccountID: String?
    var onSwitch: (UsageAccount) -> Void
    var onLogin: (UsageAccount) -> Void
    var onRemove: (UsageAccount) -> Void

    var body: some View {
        if group.isGrouped {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(group.title)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                    Text("\(group.accounts.count) \(L.text("workspaces", language))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 2)

                ForEach(group.accounts) { account in
                    AccountRowView(
                        account: account,
                        language: language,
                        isSwitching: switchingAccountID == account.id,
                        onSwitch: { onSwitch(account) },
                        onLogin: { onLogin(account) },
                        onRemove: { onRemove(account) }
                    )
                    .padding(.leading, 12)
                }
            }
        } else if let account = group.accounts.first {
            AccountRowView(
                account: account,
                language: language,
                isSwitching: switchingAccountID == account.id,
                onSwitch: { onSwitch(account) },
                onLogin: { onLogin(account) },
                onRemove: { onRemove(account) }
            )
        }
    }
}

struct PopoverLoadingRow: View {
    var title: String
    var subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .agentBarPanel(cornerRadius: 10)
    }
}

struct AccountRowView: View {
    var account: UsageAccount
    var language: AppLanguage
    var isSwitching: Bool
    var onSwitch: () -> Void
    var onLogin: () -> Void
    var onRemove: () -> Void
    @State private var isConfirmingSwitch = false
    @State private var isConfirmingRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(secondaryIdentity)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ForEach(account.workspaceLines(language: language), id: \.self) { line in
                        Text(line)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                HStack(spacing: 6) {
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
                    } else if account.isActive {
                        Text(L.text("current", language))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AgentBarPalette.primary, in: Capsule())
                    } else if account.service == .codex {
                        Button {
                            isConfirmingSwitch = true
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
                    }

                    if account.service == .codex {
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
                }
            }

            if let warning = account.loginWarningLine(language: language) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
            }

            if account.service == .codex {
                Label(accessTokenExpiryText, systemImage: "key.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accessTokenExpiryColor)
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                UsageWindowGauge(title: L.text("five_hour", language), window: account.fiveHourWindow, language: language)
                UsageWindowGauge(title: L.text("weekly", language), window: account.weeklyWindow, language: language)
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
                .font(.caption2)
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
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }

            HStack(spacing: 6) {
                Text(account.accountTypeValue(language: language))
                Text("·")
                Text(lastActivitySummary)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(account.needsLogin ? Color.red.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .agentBarPanel(cornerRadius: 10)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(account.needsLogin ? Color.red.opacity(0.70) : Color.clear, lineWidth: 1.5)
        }
        .confirmationDialog(L.text("use_account", language), isPresented: $isConfirmingSwitch) {
            Button(L.text("use_account", language)) {
                onSwitch()
            }
        } message: {
            Text(L.text("switch_account_confirmation", language))
        }
        .confirmationDialog(L.text("remove_account", language), isPresented: $isConfirmingRemoval) {
            Button(L.text("remove_account", language), role: .destructive) {
                onRemove()
            }
        } message: {
            Text(L.text("remove_account_confirmation", language))
        }
    }

    private var secondaryIdentity: String {
        "\(account.sourceDescription) · \(account.service.rawValue)"
    }

    private var lastActivitySummary: String {
        guard let lastUpdated = account.lastUpdated else { return "\(L.text("last_activity", language)): --" }
        return "\(L.text("last_activity", language)): \(DisplayFormatters.relativeString(for: lastUpdated, language: language))"
    }

    private var accessTokenExpiryText: String {
        guard let expiry = account.accessTokenExpiresAt else {
            return "\(L.text("access_token_expiry", language)): \(L.text("expiry_date_unavailable", language))"
        }
        let date = DisplayFormatters.shortDateTimeString(for: expiry, language: language)
        let status = expiry <= Date()
            ? L.text("expired", language)
            : DisplayFormatters.relativeString(for: expiry, language: language)
        return "\(L.text("access_token_expiry", language)): \(date) · \(status)"
    }

    private var accessTokenExpiryColor: Color {
        guard let expiry = account.accessTokenExpiresAt else { return .secondary }
        let remaining = expiry.timeIntervalSinceNow
        if remaining <= 0 { return .red }
        if remaining <= AccessTokenExpiryReminderPlanner.warningInterval { return .orange }
        return .secondary
    }
}

struct UsageWindowGauge: View {
    var title: String
    var window: UsageWindow?
    var language: AppLanguage

    var body: some View {
        if let window {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                    Spacer()
                    Text(DisplayFormatters.percentString(window.remainingPercent))
                        .monospacedDigit()
                }
                .font(.caption2)
                ProgressView(value: window.remainingPercent / 100)
                    .tint(tint)
                Text(window.resetLine(language: language))
                    .font(.agentBar(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    private var tint: Color {
        guard let remaining = window?.remainingPercent else { return .gray }
        if remaining < 15 { return .red }
        if remaining < 35 { return .orange }
        return AgentBarPalette.primary
    }
}

struct KPIPill: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: systemImage)
                .font(.agentBar(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.12), in: Circle())
            Text(title)
                .font(.agentBar(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
            Text(value)
                .font(.agentBarMono(size: 13, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .agentBarPanel(cornerRadius: 12)
    }
}

struct PopoverToolbarButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.agentBar(size: 12, weight: .bold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 36)
                .agentBarPanel(cornerRadius: 10)
        }
        .foregroundStyle(.primary)
        .tactilePlainButton()
        .help(title)
    }
}
