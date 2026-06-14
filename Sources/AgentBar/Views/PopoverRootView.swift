import SwiftUI

struct PopoverRootView: View {
    @ObservedObject var store: UsageStore
    var onOpenStatistics: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    @Environment(\.openWindow) private var openWindow
    @State private var hudVisible = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    accountSection
                    summarySection
                    dataSourceSection
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("AgentBar")
                    .font(.headline)
                Text("\(DisplayFormatters.percentString(store.lowestRemaining)) \(L.text("remaining", store.language))")
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
                store.refresh()
            } label: {
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help(L.text("refresh", store.language))
            .disabled(store.isRefreshing)
        }
        .padding(16)
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.text("overview", store.language))
                .font(.subheadline.weight(.semibold))
            if store.isLoadingAccountInformation && store.accounts.isEmpty {
                PopoverLoadingRow(title: L.text("loading_accounts", store.language), subtitle: L.text("loading_account_info_subtitle", store.language))
            } else {
                if store.isLoadingAccountInformation {
                    PopoverLoadingRow(title: L.text("refreshing_accounts", store.language), subtitle: "\(store.accounts.count) \(L.text("accounts_loaded", store.language))")
                }
                ForEach(store.accounts.sortedByActiveThenName()) { account in
                    AccountRowView(account: account, language: store.language)
                }
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.text("statistics", store.language))
                .font(.subheadline.weight(.semibold))
            HStack {
                KPIPill(title: L.text("tokens", store.language), value: DisplayFormatters.tokenString(store.summary.totalTokens), tint: .blue)
                KPIPill(title: L.text("cost", store.language), value: DisplayFormatters.costString(store.summary.estimatedCostUSD), tint: .green)
            }
            MiniStackedBars(bars: Array(store.summary.dailyBars.suffix(10)))
                .frame(height: 72)
        }
    }

    private var dataSourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.text("data_sources", store.language))
                .font(.subheadline.weight(.semibold))
            ForEach(store.uiDataSourceSnapshots, id: \.service) { snapshot in
                HStack {
                    Text(snapshot.service.rawValue)
                    Spacer()
                    Text(snapshot.status.label)
                        .foregroundStyle(snapshot.status == .live ? .green : .orange)
                }
                .font(.caption)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                hudVisible.toggle()
                if hudVisible {
                    HUDWindowController.shared.show(store: store)
                } else {
                    HUDWindowController.shared.hide()
                }
            } label: {
                Label(hudVisible ? L.text("hide_hud", store.language) : L.text("show_hud", store.language), systemImage: "rectangle.on.rectangle")
            }
            Button {
                if let onOpenStatistics {
                    onOpenStatistics()
                } else {
                    openWindow(id: "statistics")
                }
            } label: {
                Label(L.text("statistics", store.language), systemImage: "chart.bar.xaxis")
            }
            Spacer()
            if let onOpenSettings {
                Button {
                    onOpenSettings()
                } label: {
                    Label(L.text("settings", store.language), systemImage: "gearshape")
                }
            } else {
                SettingsLink {
                    Label(L.text("settings", store.language), systemImage: "gearshape")
                }
            }
        }
        .padding(12)
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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct AccountRowView: View {
    var account: UsageAccount
    var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName)
                        .font(.callout.weight(.semibold))
                    Text(secondaryIdentity)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if account.isActive {
                        Text(L.text("current", language))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor, in: Capsule())
                    }
                    Text(account.service.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                UsageWindowGauge(title: L.text("five_hour", language), window: account.fiveHourWindow)
                UsageWindowGauge(title: L.text("weekly", language), window: account.weeklyWindow)
            }

            HStack {
                Text(account.plan?.uppercased() ?? account.status.label)
                Spacer()
                Text(DisplayFormatters.tokenString(account.tokens.total))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var secondaryIdentity: String {
        if let username = account.username, username != account.displayName {
            return username
        }
        return account.sourceDescription
    }
}

struct UsageWindowGauge: View {
    var title: String
    var window: UsageWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(DisplayFormatters.percentString(window?.remainingPercent))
            }
            .font(.caption2)
            ProgressView(value: (window?.remainingPercent ?? 0) / 100)
                .tint(tint)
        }
    }

    private var tint: Color {
        guard let remaining = window?.remainingPercent else { return .gray }
        if remaining < 15 { return .red }
        if remaining < 35 { return .orange }
        return .green
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
