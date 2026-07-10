import SwiftUI

struct ProjectBillingView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject private var settings: SettingsStore
    @State private var selectedProjectID: String?

    init(store: UsageStore) {
        self.store = store
        self.settings = store.settings
    }

    private var projects: [ProjectUsageSummary] {
        ProjectUsageAnalytics.summaries(
            points: store.usageDataDisplayPoints,
            range: store.selectedRange,
            customStart: store.customStart,
            customEnd: store.customEnd,
            budgets: settings.projectBudgets
        )
    }

    private var selectedProject: ProjectUsageSummary? {
        projects.first(where: { $0.id == selectedProjectID }) ?? projects.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            overviewMetrics

            if projects.isEmpty {
                emptyState
            } else {
                HStack(alignment: .top, spacing: 14) {
                    projectList
                        .frame(width: 320)
                    if let selectedProject {
                        projectDetail(selectedProject)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(localized("Project Billing", "项目账单"))
                    .font(.agentBar(size: 20, weight: .bold))
                Text(localized("Tokens, estimated cost, models, trends, and budgets by repository.", "按仓库查看 Tokens、预估费用、模型、趋势与预算。"))
                    .font(.agentBar(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            UsageRangeControls(
                range: $store.selectedRange,
                customStart: $store.customStart,
                customEnd: $store.customEnd,
                language: store.language
            )
            Button {
                store.refresh(force: true, showManualFeedback: true)
            } label: {
                Label(L.text("refresh", store.language), systemImage: "arrow.clockwise")
                    .font(.agentBar(size: 13, weight: .bold))
                    .foregroundStyle(AgentBarPalette.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
            }
            .tactilePlainButton()
            .agentBarPanel(cornerRadius: 12)
        }
    }

    private var overviewMetrics: some View {
        let tokens = projects.reduce(0) { $0 + $1.summary.totalTokens }
        let costs = projects.compactMap(\.summary.estimatedCostUSD)
        let cost = costs.isEmpty ? nil : costs.reduce(Decimal(0), +)
        let overBudget = projects.filter { project in
            project.budgetStatus.tokenSeverity != .ok || project.budgetStatus.costSeverity != .ok
        }.count

        return HStack(spacing: 14) {
            metric(localized("Repositories", "仓库"), "\(projects.count)", icon: "folder.fill", color: AgentBarPalette.primary)
            metric("Tokens", DisplayFormatters.compactTokenString(tokens, language: store.language), icon: "cylinder.split.1x2.fill", color: .blue)
            metric(localized("Estimated cost", "预估费用"), DisplayFormatters.costString(cost), icon: "dollarsign", color: .green)
            metric(localized("Budget alerts", "预算提醒"), "\(overBudget)", icon: "exclamationmark.triangle.fill", color: overBudget > 0 ? .orange : .green)
        }
    }

    private func metric(_ title: String, _ value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.agentBar(size: 16, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.agentBar(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.agentBarMono(size: 20, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .agentBarPanel(cornerRadius: 12)
    }

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(localized("Repositories", "仓库"))
                .font(.agentBar(size: 15, weight: .bold))
                .padding(16)
            Divider()
            ForEach(projects) { project in
                Button {
                    selectedProjectID = project.id
                } label: {
                    projectListRow(project)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                Divider()
            }
        }
        .agentBarPanel(cornerRadius: 14)
    }

    private func projectListRow(_ project: ProjectUsageSummary) -> some View {
        let selected = selectedProject?.id == project.id
        let warning = project.budgetStatus.tokenSeverity != .ok || project.budgetStatus.costSeverity != .ok
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(selected ? AgentBarPalette.primary : .secondary)
                Text(project.name)
                    .font(.agentBar(size: 13, weight: .bold))
                    .lineLimit(1)
                Spacer()
                if warning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            Text(project.path ?? project.id)
                .font(.agentBarMono(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack {
                Text(DisplayFormatters.compactTokenString(project.summary.totalTokens, language: store.language))
                Spacer()
                Text(DisplayFormatters.costString(project.summary.estimatedCostUSD))
            }
            .font(.agentBarMono(size: 11, weight: .bold))
        }
        .padding(14)
        .background(selected ? AgentBarPalette.primary.opacity(0.09) : Color.clear)
        .contentShape(Rectangle())
    }

    private func projectDetail(_ project: ProjectUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            projectHeader(project)

            HStack(spacing: 12) {
                detailMetric("Tokens", DisplayFormatters.compactTokenString(project.summary.totalTokens, language: store.language), change: project.periodChange.tokenPercent)
                detailMetric(localized("Estimated cost", "预估费用"), DisplayFormatters.costString(project.summary.estimatedCostUSD), change: project.periodChange.costPercent)
                detailMetric(localized("Models", "模型"), "\(project.models.count)", change: nil)
            }

            ProjectUsageTrendChart(
                bars: project.summary.dailyBars,
                language: store.language
            )

            HStack(alignment: .top, spacing: 14) {
                modelPanel(project)
                budgetPanel(project)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func projectHeader(_ project: ProjectUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(project.name)
                    .font(.agentBar(size: 18, weight: .bold))
                Spacer()
                budgetStatusPill(project)
            }
            if let path = project.path {
                Text(path)
                    .font(.agentBarMono(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(16)
        .agentBarPanel(cornerRadius: 14)
    }

    private func detailMetric(_ title: String, _ value: String, change: Double?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.agentBar(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(value)
                    .font(.agentBarMono(size: 20, weight: .bold))
                Spacer()
                if let change {
                    Text(DisplayFormatters.changePercentString(change))
                        .font(.agentBar(size: 10, weight: .bold))
                        .foregroundStyle(change > 0 ? .orange : .green)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .agentBarPanel(cornerRadius: 12)
    }

    private func modelPanel(_ project: ProjectUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(localized("Models", "模型"))
                .font(.agentBar(size: 14, weight: .bold))
                .padding(14)
            Divider()
            ForEach(Array(project.models.prefix(8))) { model in
                HStack(spacing: 12) {
                    Text(model.model)
                        .font(.agentBarMono(size: 11, weight: .bold))
                        .lineLimit(1)
                    Spacer()
                    Text(DisplayFormatters.compactTokenString(model.tokens, language: store.language))
                        .font(.agentBarMono(size: 11, weight: .bold))
                    Text(DisplayFormatters.costString(model.estimatedCostUSD))
                        .font(.agentBarMono(size: 11, weight: .bold))
                        .frame(width: 72, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                Divider()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .agentBarPanel(cornerRadius: 12)
    }

    private func budgetPanel(_ project: ProjectUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(localized("Repository budget", "仓库预算"))
                    .font(.agentBar(size: 14, weight: .bold))
                Text(localized("Set 0 to disable a threshold.", "设为 0 可关闭对应阈值。"))
                    .font(.agentBar(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            Divider()
            budgetRow(localized("Daily tokens", "每日 Tokens"), value: intBudgetBinding(project.id, \.dailyTokenLimit))
            budgetRow(localized("Weekly tokens", "每周 Tokens"), value: intBudgetBinding(project.id, \.weeklyTokenLimit))
            costBudgetRow(localized("Daily cost", "每日费用"), value: doubleBudgetBinding(project.id, \.dailyCostLimitUSD))
            costBudgetRow(localized("Weekly cost", "每周费用"), value: doubleBudgetBinding(project.id, \.weeklyCostLimitUSD))
        }
        .frame(width: 330, alignment: .topLeading)
        .agentBarPanel(cornerRadius: 12)
    }

    private func budgetRow(_ title: String, value: Binding<Int>) -> some View {
        HStack {
            Text(title).font(.agentBar(size: 11, weight: .semibold))
            Spacer()
            TextField("0", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
    }

    private func costBudgetRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title).font(.agentBar(size: 11, weight: .semibold))
            Spacer()
            TextField("0", value: value, format: .currency(code: "USD"))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
    }

    private func intBudgetBinding(_ projectID: String, _ keyPath: WritableKeyPath<ProjectBudget, Int>) -> Binding<Int> {
        Binding {
            settings.projectBudget(for: projectID)[keyPath: keyPath]
        } set: { value in
            var budget = settings.projectBudget(for: projectID)
            budget[keyPath: keyPath] = value
            settings.updateProjectBudget(budget)
        }
    }

    private func doubleBudgetBinding(_ projectID: String, _ keyPath: WritableKeyPath<ProjectBudget, Double>) -> Binding<Double> {
        Binding {
            settings.projectBudget(for: projectID)[keyPath: keyPath]
        } set: { value in
            var budget = settings.projectBudget(for: projectID)
            budget[keyPath: keyPath] = value
            settings.updateProjectBudget(budget)
        }
    }

    private func budgetStatusPill(_ project: ProjectUsageSummary) -> some View {
        if project.budget.isConfigured, store.selectedRange != .today, store.selectedRange != .thisWeek {
            return Text(localized("View Today or This Week", "切换到今天或本周"))
                .font(.agentBar(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
        let severity = maxSeverity(project.budgetStatus.tokenSeverity, project.budgetStatus.costSeverity)
        let title: String
        let color: Color
        switch severity {
        case .critical:
            title = localized("Over budget", "超出预算")
            color = .red
        case .warning:
            title = localized("Near budget", "接近预算")
            color = .orange
        case .ok:
            title = project.budget.isConfigured ? localized("On budget", "预算正常") : localized("No budget", "未设预算")
            color = project.budget.isConfigured ? .green : .secondary
        }
        return Text(title)
            .font(.agentBar(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func maxSeverity(_ lhs: InsightSeverity, _ rhs: InsightSeverity) -> InsightSeverity {
        if lhs == .critical || rhs == .critical { return .critical }
        if lhs == .warning || rhs == .warning { return .warning }
        return .ok
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 36))
                .foregroundStyle(AgentBarPalette.primary)
            Text(localized("No repository usage in this range", "所选范围内没有仓库用量"))
                .font(.agentBar(size: 16, weight: .bold))
            Text(localized("Choose another range or run a Codex task inside a repository.", "请选择其他范围，或在仓库中运行 Codex 任务。"))
                .font(.agentBar(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .agentBarPanel(cornerRadius: 14)
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        store.language == .chinese ? chinese : english
    }
}

private struct ProjectUsageTrendChart: View {
    var bars: [DailyUsageBar]
    var language: AppLanguage

    private var visibleBars: [DailyUsageBar] { Array(bars.suffix(30)) }
    private var maximum: Int {
        max(1, visibleBars.map { $0.codexTokens + $0.claudeTokens }.max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(language == .chinese ? "Token 趋势" : "Token trend")
                    .font(.agentBar(size: 14, weight: .bold))
                Spacer()
                Text(language == .chinese ? "最近最多 30 个活跃日" : "Up to 30 recent active days")
                    .font(.agentBar(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if visibleBars.isEmpty {
                Text("--")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 110)
            } else {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(visibleBars) { bar in
                        let tokens = bar.codexTokens + bar.claudeTokens
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(AgentBarPalette.primary.opacity(0.78))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(4, CGFloat(tokens) / CGFloat(maximum) * 108))
                            .help("\(DisplayFormatters.shortDayString(for: bar.day, language: language)) · \(DisplayFormatters.compactTokenString(tokens, language: language))")
                    }
                }
                .frame(height: 112, alignment: .bottom)
            }
        }
        .padding(14)
        .agentBarPanel(cornerRadius: 12)
    }
}
