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
            .accessibilityLabel(L.text("resize_popover", store.language))

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
                .padding(.horizontal, PopoverLayout.horizontalInset)
                .padding(.vertical, 12)
            hairline
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    quickSummarySection
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
                .background(.ultraThinMaterial)
        }
        .background(popoverBackground)
        .preferredColorScheme(store.settings.useDarkAppearance ? .dark : .light)
        .animation(nil, value: store.settings.useDarkAppearance)
    }

    private var popoverBackground: some View {
        LinearGradient(
            colors: [
                AgentBarDesign.panelHighlight,
                AgentBarDesign.appBackground,
                store.settings.themeColor.primary.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var hairline: some View {
        Rectangle()
            .fill(AgentBarDesign.hairline)
            .frame(height: 1)
    }

    private var dataSourceHealth: DataSourceHealthSummary {
        UsageInsights.dataSourceHealth(snapshots: store.snapshots)
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
                    .font(.system(size: 17, weight: .bold))
                Text(store.popoverHeaderQuotaTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let activeAccount = store.activeAccount {
                    Text("\(L.text("current_account", store.language)): \(activeAccount.displayNameWithWorkspace(language: store.language))")
                        .font(.system(size: 10, weight: .semibold))
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
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(store.settings.themeColor.primary)
            .frame(width: 32, height: 32)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .tactilePlainButton()
            .agentBarPanel(cornerRadius: 10)
            .help(L.text("refresh", store.language))
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.text("accounts", store.language))
                .font(.system(size: 13, weight: .bold))
            if store.isLoadingAccountInformation && store.accounts.isEmpty {
                PopoverLoadingRow(title: L.text("loading_accounts", store.language), subtitle: L.text("loading_account_info_subtitle", store.language))
            } else {
                ForEach(store.accountDisplayGroups()) { group in
                    PopoverAccountDisplayGroupView(
                        group: group,
                        language: store.language,
                        theme: store.settings.themeColor,
                        switchingAccountID: store.switchingAccountID,
                        onSwitch: store.switchActiveAccount,
                        onLogin: { account in store.openLogin(for: account) },
                        onRemove: store.removeAccount
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.text("overview", store.language))
                .font(.system(size: 13, weight: .bold))
            HStack(spacing: 8) {
                KPIPill(title: L.text("tokens", store.language), value: DisplayFormatters.tokenString(store.summary.totalTokens), systemImage: "cylinder.split.1x2.fill", tint: store.settings.themeColor.primary)
                KPIPill(title: L.text("cost", store.language), value: costText(store.summary.estimatedCostUSD), systemImage: "dollarsign", tint: store.settings.themeColor.secondary)
                KPIPill(title: L.text("data_sources", store.language), value: dataSourceSummaryText, systemImage: dataSourceHealth.issueCount == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill", tint: dataSourceHealth.issueCount == 0 ? .green : .orange)
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
            .map { "\($0.service.rawValue) \($0.status.label(language: store.language))" }
            .joined(separator: " · ")
    }

    private func costText(_ value: Decimal?) -> String {
        value.map { DisplayFormatters.costString($0) } ?? L.text("no_cost_data", store.language)
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
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(store.settings.themeColor.primary)
                .tactilePlainButton()
                .agentBarPanel(cornerRadius: 10)
                .help(L.text("settings", store.language))
            }

            PopoverToolbarButton(title: L.text("quit_app", store.language), systemImage: "power") {
                onQuit()
            }
        }
        .padding(.vertical, 8)
    }
}

struct PopoverAccountDisplayGroupView: View {
    var group: UsageAccountDisplayGroup
    var language: AppLanguage
    var theme: AppThemeColor
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
                        theme: theme,
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
                theme: theme,
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
    var theme: AppThemeColor
    var isSwitching: Bool
    var onSwitch: () -> Void
    var onLogin: () -> Void
    var onRemove: () -> Void
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
    var systemImage: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.12), in: Circle())
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .agentBarPanel(cornerRadius: 12)
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
        .accessibilityLabel(L.text("stacked_usage_bars", .english))
    }
}

struct PopoverToolbarButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .foregroundStyle(.primary)
        .tactilePlainButton()
        .agentBarPanel(cornerRadius: 10)
        .help(title)
    }
}
