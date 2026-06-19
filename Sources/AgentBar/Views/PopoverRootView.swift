import AppKit
import SwiftUI

struct ResizablePopoverRootView: View {
    @ObservedObject var store: UsageStore
    var maximumHeight: CGFloat
    var onOpenStatistics: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: () -> Void
    var onHeightChange: (CGFloat) -> Void
    @ObservedObject private var settings: SettingsStore

    init(
        store: UsageStore,
        maximumHeight: CGFloat,
        onOpenStatistics: (() -> Void)?,
        onOpenSettings: (() -> Void)?,
        onQuit: @escaping () -> Void = { NSApplication.shared.terminate(nil) },
        onHeightChange: @escaping (CGFloat) -> Void
    ) {
        self.store = store
        self.maximumHeight = maximumHeight
        self.onOpenStatistics = onOpenStatistics
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        self.onHeightChange = onHeightChange
        self.settings = store.settings
    }

    private var resize: PopoverResizeDrag {
        PopoverResizeDrag(
            bounds: PanelResizeBounds(
                minHeight: Double(PopoverLayout.minimumHeight),
                maxHeight: Double(maximumHeight)
            )
        )
    }

    var body: some View {
        PopoverRootView(
            store: store,
            onOpenStatistics: onOpenStatistics,
            onOpenSettings: onOpenSettings,
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

    private var resizeBorder: some View {
        ZStack(alignment: .bottom) {
            PopoverResizeHandle(
                startHeight: CGFloat(settings.popoverHeight),
                resize: resize
            ) { height, isFinal in
                onHeightChange(height)
                if isFinal {
                    settings.updatePopoverMaximumHeight(Double(maximumHeight))
                    settings.popoverHeight = Double(height)
                    onHeightChange(CGFloat(settings.popoverHeight))
                }
            }
            .frame(height: 12)
            .accessibilityLabel("Resize popover")

            Capsule()
                .fill(settings.themeColor.primary.opacity(0.30))
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
    var onOpenStatistics: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: () -> Void = { NSApplication.shared.terminate(nil) }
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            PopoverScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    recommendationSection
                    quickSummarySection
                    accountSection
                }
                .padding(.vertical, PopoverLayout.horizontalInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .padding(.horizontal, PopoverLayout.horizontalInset)
        .background(.regularMaterial)
        .preferredColorScheme(AppAppearance.colorScheme(useDarkAppearance: store.settings.useDarkAppearance))
        .animation(nil, value: store.settings.useDarkAppearance)
    }

    private var dataSourceHealth: DataSourceHealthSummary {
        UsageInsights.dataSourceHealth(snapshots: store.snapshots)
    }

    private var quotaPressure: QuotaPressureInsight {
        UsageInsights.quotaPressure(
            accounts: store.accounts,
            points: store.points,
            rotationThresholdRemainingPercent: store.settings.codexRotationThresholdRemainingPercent,
            autoRotationEnabled: store.settings.autoCodexAccountRotationEnabled
        )
    }

    private var recommendation: PopoverActionRecommendation {
        PopoverActionRecommendation.make(
            pressure: quotaPressure,
            dataSourceHealth: dataSourceHealth,
            language: store.language
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("AgentBar")
                    .font(.headline)
                Text(store.popoverHeaderQuotaTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let activeAccount = store.activeAccount {
                    Text("\(L.text("current_account", store.language)): \(activeAccount.displayName)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                store.refresh(force: true)
            } label: {
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .pointingHandCursor()
            .help(L.text("refresh", store.language))
        }
        .padding(.vertical, PopoverLayout.horizontalInset)
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.text("accounts", store.language))
                .font(.subheadline.weight(.semibold))
            if store.isLoadingAccountInformation && store.accounts.isEmpty {
                PopoverLoadingRow(title: L.text("loading_accounts", store.language), subtitle: L.text("loading_account_info_subtitle", store.language))
            } else {
                ForEach(store.sortedAccounts()) { account in
                    AccountRowView(
                        account: account,
                        language: store.language,
                        theme: store.settings.themeColor,
                        isSwitching: store.switchingAccountID == account.id,
                        onSwitch: { store.switchActiveAccount(account) },
                        onLogin: { store.openLogin(for: account) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recommendationSection: some View {
        PopoverRecommendationPanel(
            recommendation: recommendation,
            theme: store.settings.themeColor,
            isWorking: isRecommendationActionWorking
        ) {
            performRecommendationAction(recommendation.action)
        }
    }

    private var quickSummarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.text("overview", store.language))
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                KPIPill(title: L.text("tokens", store.language), value: DisplayFormatters.tokenString(store.summary.totalTokens), tint: store.settings.themeColor.primary)
                KPIPill(title: L.text("cost", store.language), value: costText(store.summary.estimatedCostUSD), tint: store.settings.themeColor.secondary)
                KPIPill(title: L.text("data_sources", store.language), value: dataSourceSummaryText, tint: dataSourceHealth.issueCount == 0 ? .green : .orange)
            }

            if !store.uiDataSourceSnapshots.isEmpty {
                Text(dataSourceDetailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var dataSourceSummaryText: String {
        let total = max(dataSourceHealth.rows.count, store.uiDataSourceSnapshots.count)
        return total > 0 ? "\(dataSourceHealth.liveCount)/\(total)" : "--"
    }

    private var dataSourceDetailText: String {
        store.uiDataSourceSnapshots
            .map { "\($0.service.rawValue) \($0.status.label)" }
            .joined(separator: " · ")
    }

    private var isRecommendationActionWorking: Bool {
        switch recommendation.action {
        case .switchAccount(let accountID):
            store.switchingAccountID == accountID
        case .refresh:
            store.isRefreshing
        case .waitForReset, .none:
            false
        }
    }

    private func costText(_ value: Decimal?) -> String {
        value.map { DisplayFormatters.costString($0) } ?? L.text("no_cost_data", store.language)
    }

    private func performRecommendationAction(_ action: PopoverActionRecommendation.Action) {
        switch action {
        case .switchAccount(let accountID):
            guard let account = store.accounts.first(where: { $0.id == accountID }) else { return }
            store.switchActiveAccount(account)
        case .refresh:
            store.refresh(force: true)
        case .waitForReset, .none:
            break
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            PopoverToolbarButton(title: L.text("statistics", store.language), systemImage: "chart.bar.xaxis") {
                if let onOpenStatistics {
                    onOpenStatistics()
                } else {
                    openWindow(id: "statistics")
                }
            }

            if let onOpenSettings {
                PopoverToolbarButton(title: L.text("settings", store.language), systemImage: "gearshape") {
                    onOpenSettings()
                }
            } else {
                SettingsLink {
                    Label(L.text("settings", store.language), systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .pointingHandCursor()
            }

            PopoverToolbarButton(title: L.text("quit_app", store.language), systemImage: "power") {
                onQuit()
            }
        }
        .padding(.vertical, 8)
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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct PopoverRecommendationPanel: View {
    var recommendation: PopoverActionRecommendation
    var theme: AppThemeColor
    var isWorking: Bool
    var onAction: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(recommendation.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(recommendation.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: isExpanded)
                }

                Spacer(minLength: 6)

                if let actionTitle = recommendation.actionTitle {
                    Button {
                        onAction()
                    } label: {
                        if isWorking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(actionTitle)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(tint)
                    .disabled(isWorking)
                    .pointingHandCursor(enabled: !isWorking)
                }

                if hasExpandableText {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(isExpanded ? "Hide full text" : "Show full text")
                    .accessibilityLabel(isExpanded ? "Hide full text" : "Show full text")
                    .pointingHandCursor()
                }
            }

            if isExpanded,
               let actionTitle = recommendation.actionTitle,
               actionTitle.count > Self.compactActionTitleLimit {
                Text(actionTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 34)
            }
        }
        .onChange(of: recommendation) { _, newValue in
            if !Self.hasExpandableText(for: newValue) {
                isExpanded = false
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }

    private var hasExpandableText: Bool {
        Self.hasExpandableText(for: recommendation)
    }

    private static func hasExpandableText(for recommendation: PopoverActionRecommendation) -> Bool {
        recommendation.detail.count > compactDetailLimit ||
            (recommendation.actionTitle?.count ?? 0) > compactActionTitleLimit
    }

    private static let compactDetailLimit = 72
    private static let compactActionTitleLimit = 22

    private var iconName: String {
        switch recommendation.severity {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "arrow.triangle.2.circlepath.circle.fill"
        }
    }

    private var tint: Color {
        switch recommendation.severity {
        case .ok: theme.primary
        case .warning: .orange
        case .critical: .red
        }
    }
}

struct AccountRowView: View {
    var account: UsageAccount
    var language: AppLanguage
    var theme: AppThemeColor
    var isSwitching: Bool
    var onSwitch: () -> Void
    var onLogin: () -> Void

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
                } else if account.isActive {
                    Text(L.text("current", language))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(theme.primary, in: Capsule())
                } else {
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

            HStack(spacing: 10) {
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
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }

            HStack(spacing: 6) {
                Text(account.accountTypeValue)
                Text("·")
                Text(lastActivitySummary)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(account.needsLogin ? Color.red.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(account.needsLogin ? Color.red.opacity(0.70) : Color.clear, lineWidth: 1.5)
        }
    }

    private var secondaryIdentity: String {
        "\(account.sourceDescription) · \(account.service.rawValue)"
    }

    private var lastActivitySummary: String {
        guard let lastUpdated = account.lastUpdated else { return "\(L.text("last_activity", language)): --" }
        return "\(L.text("last_activity", language)): \(DisplayFormatters.relativeString(for: lastUpdated))"
    }
}

struct UsageWindowGauge: View {
    var title: String
    var window: UsageWindow?
    var language: AppLanguage
    var theme: AppThemeColor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(DisplayFormatters.percentString(window?.remainingPercent))
                    .monospacedDigit()
            }
            .font(.caption2)
            ProgressView(value: (window?.remainingPercent ?? 0) / 100)
                .tint(tint)
            Text(window?.resetLine(language: language) ?? L.text("reset_time_unknown", language))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var tint: Color {
        guard let remaining = window?.remainingPercent else { return .gray }
        if remaining < 15 { return .red }
        if remaining < 35 { return .orange }
        return theme.primary
    }
}

struct KPIPill: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct MiniStackedBars: View {
    var bars: [DailyUsageBar]

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(1, bars.map { $0.codexTokens + $0.claudeTokens }.max() ?? 1)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(bars) { bar in
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(.purple.opacity(0.65))
                            .frame(height: proxy.size.height * CGFloat(bar.claudeTokens) / CGFloat(maxValue))
                        Rectangle()
                            .fill(.blue.opacity(0.75))
                            .frame(height: proxy.size.height * CGFloat(bar.codexTokens) / CGFloat(maxValue))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityLabel("Stacked usage bars")
    }
}

struct PopoverToolbarButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .pointingHandCursor()
        .help(title)
    }
}
