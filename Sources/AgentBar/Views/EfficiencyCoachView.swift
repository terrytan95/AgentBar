import Foundation
import SwiftUI

enum EfficiencyCoachPage: String, CaseIterable, Identifiable {
    case coach
    case contextBurn
    case cacheHealth
    case modelEffort
    case contextSources
    case sessionOutliers
    case projectEfficiency
    case smartNudge

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .coach: "sparkles"
        case .contextBurn: "chart.line.uptrend.xyaxis"
        case .cacheHealth: "externaldrive.fill.badge.checkmark"
        case .modelEffort: "flask"
        case .contextSources: "doc.on.doc"
        case .sessionOutliers: "exclamationmark.magnifyingglass"
        case .projectEfficiency: "folder.badge.gearshape"
        case .smartNudge: "bell.badge"
        }
    }
}

struct EfficiencyCoachView: View {
    @ObservedObject var store: UsageStore
    @State private var page: EfficiencyCoachPage = .coach
    @State private var selectedService = "all"
    @State private var dismissedInsightIDs: Set<String> = []
    @State private var trialInsightIDs: Set<String> = []
    @State private var navigationAnchor: EfficiencyCoachPage = .coach

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            pageNavigation

            Group {
                switch page {
                case .coach:
                    coach
                case .contextBurn:
                    ContextBurnEfficiencyView(store: store)
                case .cacheHealth:
                    CacheHealthEfficiencyView(store: store)
                case .modelEffort:
                    ModelEffortLabView(store: store)
                case .contextSources:
                    ContextSourcesEfficiencyView(store: store)
                case .sessionOutliers:
                    SessionOutliersEfficiencyView(store: store)
                case .projectEfficiency:
                    ProjectEfficiencyView(store: store)
                case .smartNudge:
                    smartNudge
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var pageNavigation: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(EfficiencyCoachPage.allCases) { item in
                        Button {
                            page = item
                            navigationAnchor = item
                            withAnimation {
                                proxy.scrollTo(item, anchor: .center)
                            }
                        } label: {
                            Label(efficiencyText(item.rawValue, store.language), systemImage: item.icon)
                                .font(.agentBar(size: 11, weight: .bold))
                                .foregroundStyle(page == item ? .white : .secondary)
                                .padding(.horizontal, 11)
                                .frame(height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(page == item ? AgentBarPalette.primary : AgentBarDesign.panelHighlight)
                                )
                        }
                        .id(item)
                        .tactilePlainButton()
                        .accessibilityAddTraits(page == item ? .isSelected : [])
                    }
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height),
                              abs(value.translation.width) > 12
                        else { return }
                        navigationAnchor = adjacentPage(
                            to: navigationAnchor,
                            towardEnd: value.translation.width < 0
                        )
                        withAnimation {
                            proxy.scrollTo(navigationAnchor, anchor: .center)
                        }
                    }
            )
            .onChange(of: page) { _, newPage in
                navigationAnchor = newPage
                withAnimation {
                    proxy.scrollTo(newPage, anchor: .center)
                }
            }
        }
    }

    private func adjacentPage(to current: EfficiencyCoachPage, towardEnd: Bool) -> EfficiencyCoachPage {
        let pages = EfficiencyCoachPage.allCases
        guard let index = pages.firstIndex(of: current) else { return page }
        return pages[min(max(index + (towardEnd ? 1 : -1), pages.startIndex), pages.index(before: pages.endIndex))]
    }

    private var coach: some View {
        let points = servicePoints
        let insights = TokenEfficiencyAnalytics.coachInsights(
            points: points,
            tasks: store.tasks,
            range: store.selectedRange,
            customStart: store.customStart,
            customEnd: store.customEnd
        ).filter { !dismissedInsightIDs.contains($0.id) }
        let contextSessions = TokenEfficiencyAnalytics.contextBurn(
            points: points,
            range: store.selectedRange,
            customStart: store.customStart,
            customEnd: store.customEnd
        )
        let cache = TokenEfficiencyAnalytics.cacheHealth(
            points: points,
            range: store.selectedRange,
            customStart: store.customStart,
            customEnd: store.customEnd
        )

        return VStack(alignment: .leading, spacing: 16) {
            header(
                title: efficiencyText("coach", store.language),
                subtitle: efficiencyText("coachSubtitle", store.language)
            )

            HStack(spacing: 12) {
                coachMetric(
                    efficiencyText("opportunities", store.language),
                    insights.isEmpty ? "—" : "\(insights.count)",
                    icon: "sparkles",
                    color: .green
                )
                coachMetric(
                    efficiencyText("contextSessions", store.language),
                    contextSessions.isEmpty ? "—" : "\(contextSessions.count)",
                    icon: "chart.line.uptrend.xyaxis",
                    color: AgentBarPalette.primary
                )
                let cachedInput = cache.compactMap(\.cachedInputTokens).reduce(0, +)
                let totalInput = cache.compactMap(\.inputTokens).reduce(0, +)
                coachMetric(
                    efficiencyText("cacheReuse", store.language),
                    totalInput > 0 ? percent(Double(cachedInput) / Double(totalInput)) : "—",
                    icon: "externaldrive.fill.badge.checkmark",
                    color: .green
                )
                coachMetric(
                    efficiencyText("timeframe", store.language),
                    store.selectedRange.dashboardLabel(store.language),
                    icon: "calendar",
                    color: .purple
                )
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(efficiencyText("topOpportunities", store.language))
                        .font(.agentBar(size: 16, weight: .bold))
                    Text(efficiencyText("opportunitiesSubtitle", store.language))
                        .font(.agentBar(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                servicePicker
                UsageRangeControls(
                    range: $store.selectedRange,
                    customStart: $store.customStart,
                    customEnd: $store.customEnd,
                    language: store.language
                )
            }

            if insights.isEmpty {
                unavailablePanel(
                    efficiencyText("noInsights", store.language),
                    efficiencyText("noInsightsDetail", store.language)
                )
            } else {
                ForEach(insights) { insight in
                    insightCard(insight)
                }
            }

            Label(efficiencyText("privacyNote", store.language), systemImage: "lock.shield")
                .font(.agentBar(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var smartNudge: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(
                title: efficiencyText("smartNudge", store.language),
                subtitle: efficiencyText("smartNudgeSubtitle", store.language)
            )
            if let nudge = TokenEfficiencyAnalytics.smartNudge(points: servicePoints) {
                HStack(spacing: 16) {
                    Image(systemName: "bell.badge.fill")
                        .font(.agentBar(size: 28, weight: .bold))
                        .foregroundStyle(.orange)
                        .frame(width: 58, height: 58)
                        .background(Circle().fill(.orange.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(efficiencyText("contextNudge", store.language))
                            .font(.agentBar(size: 16, weight: .bold))
                        Text(
                            String(
                                format: efficiencyText("nudgeDetail", store.language),
                                Int(nudge.contextOccupancyRatio * 100),
                                nudge.service.rawValue
                            )
                        )
                        .font(.agentBar(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(efficiencyText("reviewEvidence", store.language)) {
                        page = .contextBurn
                    }
                    .tactilePlainButton()
                    .buttonStyle(.borderedProminent)
                }
                .padding(18)
                .agentBarPanel(cornerRadius: 14)
            } else {
                unavailablePanel(
                    efficiencyText("noNudge", store.language),
                    efficiencyText("noNudgeDetail", store.language)
                )
            }
        }
    }

    private var servicePoints: [UsagePoint] {
        guard selectedService != "all",
              let service = UsageService(rawValue: selectedService)
        else { return store.usageDataDisplayPoints }
        return store.usageDataDisplayPoints.filter { $0.service == service }
    }

    private var servicePicker: some View {
        Picker("", selection: $selectedService) {
            Text(efficiencyText("allServices", store.language)).tag("all")
            ForEach(UsageService.allCases) { service in
                Text(service.rawValue).tag(service.rawValue)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 132)
        .accessibilityLabel(efficiencyText("service", store.language))
    }

    private func insightCard(_ insight: EfficiencyCoachInsight) -> some View {
        let presentation = insightPresentation(insight)
        return HStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: presentation.icon)
                    .font(.agentBar(size: 26, weight: .bold))
                    .foregroundStyle(presentation.color)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(presentation.color.opacity(0.1)))
                Text(efficiencyText(presentation.impactKey, store.language))
                    .font(.agentBar(size: 10, weight: .bold))
                    .foregroundStyle(presentation.color)
            }
            .frame(width: 106)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(presentation.title)
                    .font(.agentBar(size: 16, weight: .bold))
                Text(presentation.detail)
                    .font(.agentBar(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Label("\(insight.sampleSize) \(efficiencyText("samples", store.language))", systemImage: "number")
                    Label(confidenceLabel(insight.confidence), systemImage: "checkmark.seal")
                }
                .font(.agentBar(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(spacing: 8) {
                Button(efficiencyText("seeEvidence", store.language)) {
                    page = presentation.evidencePage
                }
                .buttonStyle(.bordered)

                Button {
                    if trialInsightIDs.contains(insight.id) {
                        trialInsightIDs.remove(insight.id)
                    } else {
                        trialInsightIDs.insert(insight.id)
                    }
                } label: {
                    Text(
                        trialInsightIDs.contains(insight.id)
                            ? efficiencyText("trialQueued", store.language)
                            : efficiencyText("tryNextSession", store.language)
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(efficiencyText("dismiss", store.language)) {
                    dismissedInsightIDs.insert(insight.id)
                }
                .buttonStyle(.bordered)
            }
            .font(.agentBar(size: 11, weight: .bold))
            .frame(width: 156)
            .padding(14)
        }
        .frame(minHeight: 154)
        .agentBarPanel(cornerRadius: 14)
    }

    private func insightPresentation(_ insight: EfficiencyCoachInsight) -> (
        title: String,
        detail: String,
        icon: String,
        color: Color,
        impactKey: String,
        evidencePage: EfficiencyCoachPage
    ) {
        switch insight.kind {
        case .contextPressure:
            return (
                String(
                    format: efficiencyText("contextTitle", store.language),
                    Int(insight.measuredValue * 100)
                ),
                efficiencyText("contextDetail", store.language),
                "chart.line.uptrend.xyaxis",
                AgentBarPalette.primary,
                "highImpact",
                .contextBurn
            )
        case .cacheReuseExperiment:
            return (
                String(
                    format: efficiencyText("cacheTitle", store.language),
                    Int(insight.measuredValue * 100)
                ),
                efficiencyText("cacheDetail", store.language),
                "externaldrive.fill.badge.checkmark",
                .green,
                "highImpact",
                .cacheHealth
            )
        case .sessionOutlier:
            return (
                String(
                    format: efficiencyText("outlierTitle", store.language),
                    DisplayFormatters.compactTokenString(Int(insight.measuredValue), language: store.language)
                ),
                efficiencyText("outlierDetail", store.language),
                "exclamationmark.magnifyingglass",
                .purple,
                "mediumImpact",
                .sessionOutliers
            )
        }
    }

    private func coachMetric(
        _ title: String,
        _ value: String,
        icon: String,
        color: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.agentBar(size: 19, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 11).fill(color.opacity(0.1)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.agentBar(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.agentBarMono(size: 18, weight: .bold))
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .agentBarPanel(cornerRadius: 12)
    }

    private func header(title: String, subtitle: String) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.agentBar(size: 22, weight: .bold))
                Text(subtitle)
                    .font(.agentBar(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.refresh(force: true, showManualFeedback: true)
            } label: {
                Label(efficiencyText("refresh", store.language), systemImage: "arrow.clockwise")
                    .font(.agentBar(size: 12, weight: .bold))
            }
            .buttonStyle(.bordered)
        }
    }

    private func unavailablePanel(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.agentBar(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.agentBar(size: 15, weight: .bold))
            Text(detail)
                .font(.agentBar(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .agentBarPanel(cornerRadius: 14)
    }

    private func confidenceLabel(_ confidence: TokenEfficiencyConfidence) -> String {
        "\(efficiencyText(confidence.level.rawValue, store.language)) · \(confidence.sampleSize)/\(confidence.minimumSampleSize)"
    }
}

private struct ContextBurnEfficiencyView: View {
    @ObservedObject var store: UsageStore
    @State private var selectedSessionID = ""

    private var sessions: [ContextBurnSession] {
        TokenEfficiencyAnalytics.contextBurn(
            points: store.points,
            range: store.selectedRange,
            customStart: store.customStart,
            customEnd: store.customEnd
        )
    }

    private var session: ContextBurnSession? {
        sessions.first { $0.id == selectedSessionID } ?? sessions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            detailHeader(
                efficiencyText("contextBurn", store.language),
                efficiencyText("contextBurnSubtitle", store.language),
                store: store
            )

            HStack {
                Picker(efficiencyText("session", store.language), selection: $selectedSessionID) {
                    ForEach(sessions) { session in
                        Text(sessionDropdownTitle(session))
                            .tag(session.id)
                    }
                }
                .frame(maxWidth: 320)
                Spacer()
                UsageRangeControls(
                    range: $store.selectedRange,
                    customStart: $store.customStart,
                    customEnd: $store.customEnd,
                    language: store.language
                )
            }

            if let session {
                HStack(alignment: .top, spacing: 14) {
                    contextChart(session)
                    contextFacts(session)
                        .frame(width: 310)
                }
                HStack(spacing: 12) {
                    metricPanel(
                        efficiencyText("currentContext", store.language),
                        DisplayFormatters.compactTokenString(session.latestInputTokens, language: store.language),
                        percent(session.latestOccupancyRatio),
                        .orange
                    )
                    metricPanel(
                        efficiencyText("peakContext", store.language),
                        DisplayFormatters.compactTokenString(
                            Int(Double(session.contextWindowTokens) * session.peakOccupancyRatio),
                            language: store.language
                        ),
                        percent(session.peakOccupancyRatio),
                        .red
                    )
                    metricPanel(
                        efficiencyText("contextWindow", store.language),
                        DisplayFormatters.compactTokenString(session.contextWindowTokens, language: store.language),
                        session.scope.model ?? "—",
                        AgentBarPalette.primary
                    )
                }
            } else {
                efficiencyUnavailable(store.language)
            }
        }
    }

    private func contextChart(_ session: ContextBurnSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(efficiencyText("contextOccupancy", store.language))
                .font(.agentBar(size: 15, weight: .bold))
            Text(efficiencyText("contextChartDetail", store.language))
                .font(.agentBar(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            GeometryReader { proxy in
                let fill = min(1, max(0, session.latestOccupancyRatio))
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AgentBarPalette.primary.opacity(0.07))
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [AgentBarPalette.primary.opacity(0.62), .purple.opacity(0.22)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: proxy.size.height * fill)
                    Rectangle()
                        .fill(.orange)
                        .frame(height: 2)
                        .offset(y: -proxy.size.height * 0.7)
                    Text(percent(session.latestOccupancyRatio))
                        .font(.agentBarMono(size: 28, weight: .bold))
                        .padding(18)
                }
            }
            .frame(minHeight: 250)
            Label(
                efficiencyText(
                    session.latestOccupancyRatio >= 0.7 ? "freshCheckpoint" : "contextHealthy",
                    store.language
                ),
                systemImage: session.latestOccupancyRatio >= 0.7 ? "arrow.counterclockwise.circle" : "checkmark.circle"
            )
            .font(.agentBar(size: 12, weight: .bold))
            .foregroundStyle(session.latestOccupancyRatio >= 0.7 ? .orange : .green)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 410)
        .agentBarPanel(cornerRadius: 14)
    }

    private func contextFacts(_ session: ContextBurnSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(efficiencyText("sessionFacts", store.language))
                .font(.agentBar(size: 15, weight: .bold))
            fact(efficiencyText("service", store.language), session.scope.service.rawValue)
            fact(efficiencyText("model", store.language), session.scope.model ?? "—")
            fact(efficiencyText("project", store.language), session.scope.projectName ?? "—")
            fact(
                efficiencyText("growth", store.language),
                session.recentInputGrowthRatio.map(percent) ?? "—"
            )
            fact(
                efficiencyText("confidence", store.language),
                efficiencyText(session.confidence.level.rawValue, store.language)
            )
            Divider()
            Text(efficiencyText("whyContextMatters", store.language))
                .font(.agentBar(size: 13, weight: .bold))
            Text(efficiencyText("whyContextDetail", store.language))
                .font(.agentBar(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(minHeight: 410, alignment: .top)
        .agentBarPanel(cornerRadius: 14)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .font(.agentBar(size: 11, weight: .medium))
    }

    private func sessionDropdownTitle(_ session: ContextBurnSession) -> String {
        guard let title = session.title else { return shortSession(session.sessionID) }
        return title.count > 50 ? "\(title.prefix(50))…" : title
    }
}

private struct CacheHealthEfficiencyView: View {
    @ObservedObject var store: UsageStore
    @State private var selectedService = "all"

    private var summaries: [CacheHealthSummary] {
        let points: [UsagePoint]
        if let service = UsageService(rawValue: selectedService) {
            points = store.usageDataDisplayPoints.filter { $0.service == service }
        } else {
            points = store.usageDataDisplayPoints
        }
        return TokenEfficiencyAnalytics.cacheHealth(
            points: points,
            range: store.selectedRange,
            customStart: store.customStart,
            customEnd: store.customEnd
        )
    }

    private var ratio: Double? {
        let cached = summaries.compactMap(\.cachedInputTokens).reduce(0, +)
        let total = summaries.compactMap(\.inputTokens).reduce(0, +)
        return total > 0 ? Double(cached) / Double(total) : nil
    }

    private var input: Int? {
        let values = summaries.compactMap(\.inputTokens)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    private var uncached: Int? {
        let values = summaries.compactMap(\.uncachedInputTokens)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            detailHeader(
                efficiencyText("cacheHealth", store.language),
                efficiencyText("cacheHealthSubtitle", store.language),
                store: store
            )
            HStack {
                Picker("", selection: $selectedService) {
                    Text(efficiencyText("allServices", store.language)).tag("all")
                    ForEach(UsageService.allCases) { service in
                        Text(service.rawValue).tag(service.rawValue)
                    }
                }
                .frame(width: 150)
                Spacer()
                UsageRangeControls(
                    range: $store.selectedRange,
                    customStart: $store.customStart,
                    customEnd: $store.customEnd,
                    language: store.language
                )
            }

            HStack(spacing: 12) {
                metricPanel(
                    efficiencyText("cacheReuse", store.language),
                    ratio.map(percent) ?? "—",
                    efficiencyText("cacheReuseDetail", store.language),
                    AgentBarPalette.primary
                )
                metricPanel(
                    efficiencyText("uncachedInput", store.language),
                    uncached.map { DisplayFormatters.compactTokenString($0, language: store.language) } ?? "—",
                    efficiencyText("uncachedDetail", store.language),
                    .orange
                )
                metricPanel(
                    efficiencyText("totalInput", store.language),
                    input.map { DisplayFormatters.compactTokenString($0, language: store.language) } ?? "—",
                    efficiencyText("measuredLocally", store.language),
                    .green
                )
            }

            VStack(alignment: .leading, spacing: 14) {
                Text(efficiencyText("cacheByService", store.language))
                    .font(.agentBar(size: 15, weight: .bold))
                if summaries.isEmpty {
                    efficiencyUnavailable(store.language)
                } else {
                    ForEach(summaries) { summary in
                        cacheRow(summary)
                    }
                }
            }
            .padding(18)
            .agentBarPanel(cornerRadius: 14)

            VStack(alignment: .leading, spacing: 12) {
                Text(efficiencyText("lowestCacheSessions", store.language))
                    .font(.agentBar(size: 15, weight: .bold))
                let sessions = summaries.flatMap(\.sessions).sorted { $0.cacheRatio < $1.cacheRatio }
                if sessions.isEmpty {
                    Text(efficiencyText("unavailable", store.language))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessions.prefix(8)) { session in
                        HStack {
                            Text(shortSession(session.sessionID))
                                .font(.agentBarMono(size: 11, weight: .semibold))
                            Spacer()
                            Text(session.scope.service.rawValue).foregroundStyle(.secondary)
                            Text(percent(session.cacheRatio))
                                .foregroundStyle(session.cacheRatio < 0.4 ? .orange : .green)
                                .frame(width: 58, alignment: .trailing)
                            Text(DisplayFormatters.compactTokenString(session.uncachedInputTokens, language: store.language))
                                .frame(width: 82, alignment: .trailing)
                        }
                        .font(.agentBar(size: 11, weight: .semibold))
                        Divider()
                    }
                }
            }
            .padding(18)
            .agentBarPanel(cornerRadius: 14)
        }
    }

    private func cacheRow(_ summary: CacheHealthSummary) -> some View {
        HStack(spacing: 14) {
            Text(summary.service.rawValue)
                .font(.agentBar(size: 12, weight: .bold))
                .frame(width: 110, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AgentBarDesign.hairline)
                    Capsule()
                        .fill(AgentBarPalette.primary)
                        .frame(width: proxy.size.width * min(1, max(0, summary.cacheRatio ?? 0)))
                }
            }
            .frame(height: 9)
            Text(summary.cacheRatio.map(percent) ?? "—")
                .font(.agentBarMono(size: 12, weight: .bold))
                .frame(width: 62, alignment: .trailing)
            Text("\(summary.sessions.count) \(efficiencyText("sessions", store.language))")
                .font(.agentBar(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .trailing)
        }
    }
}

private struct ModelEffortLabView: View {
    @ObservedObject var store: UsageStore
    @State private var selectedID = ""
    @State private var startedTrialIDs: Set<String> = []

    var body: some View {
        let experiments = TokenEfficiencyAnalytics.modelEffortExperiments(
            points: store.usageDataDisplayPoints,
            tasks: store.auditTasks
        )
        let selected = experiments.first { $0.id == selectedID } ?? experiments.first
        return VStack(alignment: .leading, spacing: 16) {
            detailHeader(
                efficiencyText("modelEffort", store.language),
                efficiencyText("modelEffortSubtitle", store.language),
                store: store
            )
            HStack(spacing: 12) {
                metricPanel(
                    efficiencyText("evaluatedGroups", store.language),
                    "\(Set(store.auditTasks.compactMap(\.projectName)).count)",
                    efficiencyText("localTaskGroups", store.language),
                    AgentBarPalette.primary
                )
                metricPanel(
                    efficiencyText("experimentCandidates", store.language),
                    experiments.isEmpty ? "—" : "\(experiments.count)",
                    efficiencyText("safeToTrial", store.language),
                    .purple
                )
                metricPanel(
                    efficiencyText("trialsStarted", store.language),
                    "\(startedTrialIDs.count)",
                    efficiencyText("localOnly", store.language),
                    .green
                )
            }

            if experiments.isEmpty {
                efficiencyUnavailable(store.language)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(experiments) { experiment in
                        Button {
                            selectedID = experiment.id
                        } label: {
                            HStack {
                                Circle()
                                    .fill(selected?.id == experiment.id ? AgentBarPalette.primary : .clear)
                                    .overlay(Circle().stroke(AgentBarDesign.hairline))
                                    .frame(width: 10, height: 10)
                                Text(experiment.scope.projectName ?? efficiencyText("unknownProject", store.language))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(experiment.currentEffort) → \(experiment.suggestedTrialEffort)")
                                    .foregroundStyle(AgentBarPalette.primary)
                                    .frame(width: 150)
                                Text("\(experiment.completedTaskCount) \(efficiencyText("tasks", store.language))")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 100, alignment: .trailing)
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .font(.agentBar(size: 11, weight: .semibold))
                            .padding(.horizontal, 16)
                            .frame(height: 48)
                            .contentShape(Rectangle())
                        }
                        .tactilePlainButton()
                        if experiment.id != experiments.last?.id { Divider() }
                    }
                }
                .agentBarPanel(cornerRadius: 14)

                if let selected {
                    experimentDetail(selected)
                }
            }
        }
    }

    private func experimentDetail(_ experiment: ModelEffortExperiment) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Label(efficiencyText("reversibleExperiment", store.language), systemImage: "info.circle")
                    .font(.agentBar(size: 12, weight: .bold))
                    .foregroundStyle(AgentBarPalette.primary)
                Text(efficiencyText("experimentWarning", store.language))
                    .font(.agentBar(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Divider()
                factRow(efficiencyText("service", store.language), experiment.scope.service.rawValue)
                factRow(efficiencyText("model", store.language), experiment.scope.model ?? "—")
                factRow(efficiencyText("sampleSize", store.language), "\(experiment.completedTaskCount)")
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            .agentBarPanel(cornerRadius: 14)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    effortCard(
                        efficiencyText("currentControl", store.language),
                        experiment.currentEffort,
                        AgentBarPalette.primary
                    )
                    Image(systemName: "arrow.right")
                    effortCard(
                        efficiencyText("trialExperiment", store.language),
                        experiment.suggestedTrialEffort,
                        .green
                    )
                }
                Button {
                    startedTrialIDs.insert(experiment.id)
                } label: {
                    Text(
                        startedTrialIDs.contains(experiment.id)
                            ? efficiencyText("trialQueued", store.language)
                            : String(
                                format: efficiencyText("startTrial", store.language),
                                experiment.trialTaskCount
                            )
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func effortCard(_ title: String, _ effort: String, _ color: Color) -> some View {
        VStack(spacing: 8) {
            Text(title).foregroundStyle(.secondary)
            Text(effort)
                .font(.agentBarMono(size: 20, weight: .bold))
                .foregroundStyle(color)
        }
        .font(.agentBar(size: 11, weight: .semibold))
        .frame(maxWidth: .infinity, minHeight: 130)
        .agentBarPanel(cornerRadius: 14)
    }
}

@MainActor
private func detailHeader(_ title: String, _ subtitle: String, store: UsageStore) -> some View {
    HStack {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.agentBar(size: 22, weight: .bold))
            Text(subtitle)
                .font(.agentBar(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        Spacer()
        Button {
            store.refresh(force: true, showManualFeedback: true)
        } label: {
            Label(efficiencyText("refresh", store.language), systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
    }
}

@MainActor
private func metricPanel(_ title: String, _ value: String, _ detail: String, _ color: Color) -> some View {
    VStack(alignment: .leading, spacing: 7) {
        Text(title)
            .font(.agentBar(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
        Text(value)
            .font(.agentBarMono(size: 23, weight: .bold))
            .foregroundStyle(color)
            .lineLimit(1)
        Text(detail)
            .font(.agentBar(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }
    .padding(16)
    .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
    .agentBarPanel(cornerRadius: 12)
}

@MainActor
private func efficiencyUnavailable(_ language: AppLanguage) -> some View {
    VStack(spacing: 8) {
        Image(systemName: "chart.bar.xaxis")
            .font(.agentBar(size: 26, weight: .semibold))
            .foregroundStyle(.secondary)
        Text(efficiencyText("unavailable", language))
            .font(.agentBar(size: 14, weight: .bold))
        Text(efficiencyText("unavailableDetail", language))
            .font(.agentBar(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 180)
    .agentBarPanel(cornerRadius: 14)
}

@MainActor
private func factRow(_ title: String, _ value: String) -> some View {
    HStack {
        Text(title).foregroundStyle(.secondary)
        Spacer()
        Text(value).fontWeight(.semibold)
    }
    .font(.agentBar(size: 11, weight: .medium))
}

private func percent(_ value: Double) -> String {
    guard value.isFinite else { return "—" }
    return "\(Int((value * 100).rounded()))%"
}

private func shortSession(_ value: String) -> String {
    value.count > 12 ? "\(value.prefix(8))…" : value
}

private func efficiencyText(_ key: String, _ language: AppLanguage) -> String {
    let english: [String: String] = [
        "coach": "Efficiency Guide",
        "contextBurn": "Context Burn",
        "cacheHealth": "Cache Health",
        "modelEffort": "Model & Effort Lab",
        "contextSources": "Context Sources",
        "sessionOutliers": "Session Outliers",
        "projectEfficiency": "Project Efficiency",
        "smartNudge": "Smart Nudge",
        "coachSubtitle": "Turn usage into prioritized, explainable actions.",
        "opportunities": "Opportunities",
        "contextSessions": "Measured sessions",
        "cacheReuse": "Cache reuse",
        "timeframe": "Timeframe",
        "topOpportunities": "Top opportunities",
        "opportunitiesSubtitle": "Based on local usage patterns and confidence thresholds.",
        "allServices": "All services",
        "service": "Service",
        "noInsights": "No high-confidence opportunities yet",
        "noInsightsDetail": "AgentBar will show suggestions when enough comparable local usage is available.",
        "privacyNote": "Computed locally from usage metadata. Prompt, reply, code, and tool-output content is not retained.",
        "smartNudgeSubtitle": "A timely local signal when a session approaches its context limit.",
        "contextNudge": "Context pressure detected",
        "nudgeDetail": "This session is using %d%% of its context window in %@.",
        "reviewEvidence": "Review evidence",
        "noNudge": "No active nudge",
        "noNudgeDetail": "No session currently meets the evidence and context-pressure thresholds.",
        "samples": "samples",
        "sessions": "sessions",
        "tasks": "tasks",
        "high": "High",
        "medium": "Medium",
        "low": "Low",
        "highImpact": "High impact",
        "mediumImpact": "Medium impact",
        "contextTitle": "Context reached %d%% in one session",
        "contextDetail": "A long-running session is approaching its measured context limit. Review a fresh-session checkpoint.",
        "cacheTitle": "Cache reuse fell to %d%%",
        "cacheDetail": "Reuse is below your personal baseline. Test stable prefixes and repeated setup in the next comparable session.",
        "outlierTitle": "Uncached input reached %@",
        "outlierDetail": "This completed session exceeded its same-project, same-model baseline.",
        "seeEvidence": "See evidence",
        "tryNextSession": "Try next session",
        "trialQueued": "Trial queued",
        "dismiss": "Dismiss",
        "refresh": "Refresh",
        "contextBurnSubtitle": "See measured context occupancy before a session becomes crowded.",
        "session": "Session",
        "contextOccupancy": "Current context occupancy",
        "contextChartDetail": "Input context relative to the provider-reported model window.",
        "freshCheckpoint": "Consider a fresh-session checkpoint",
        "contextHealthy": "Context occupancy is below the review threshold",
        "sessionFacts": "Session facts",
        "model": "Model",
        "project": "Project",
        "growth": "Recent growth",
        "confidence": "Confidence",
        "whyContextMatters": "Why this matters",
        "whyContextDetail": "As context grows, less room remains for new signal. A fresh session can preserve focus when you carry forward a concise handoff.",
        "currentContext": "Current context",
        "peakContext": "Peak context",
        "contextWindow": "Context window",
        "cacheHealthSubtitle": "Understand prompt-cache reuse and uncached input without claiming unobserved savings.",
        "cacheReuseDetail": "Share of input served from cache",
        "uncachedInput": "Uncached input",
        "uncachedDetail": "Observed input not served from cache",
        "totalInput": "Total input",
        "measuredLocally": "Measured from local usage metadata",
        "cacheByService": "Cache reuse by service",
        "lowestCacheSessions": "Sessions with lowest cache reuse",
        "modelEffortSubtitle": "Build a small manual trial from local project, model, and effort history.",
        "evaluatedGroups": "Projects observed",
        "localTaskGroups": "Project labels in task history",
        "experimentCandidates": "Manual trial candidates",
        "safeToTrial": "Meets the six-task history floor",
        "trialsStarted": "Trials started",
        "localOnly": "Local UI state; no automatic model change",
        "unknownProject": "Unknown project",
        "reversibleExperiment": "Manual experiment — not a quality recommendation",
        "experimentWarning": "These tasks share provider, project, model, and effort only. AgentBar cannot tell whether they are similar or whether lower effort preserves quality. Choose comparable future tasks and judge quality yourself.",
        "sampleSize": "Sample size",
        "currentControl": "Current (control)",
        "trialExperiment": "Trial (experiment)",
        "startTrial": "Start %d-task trial",
        "unavailable": "Data unavailable",
        "unavailableDetail": "The selected range does not contain enough compatible local usage metadata."
    ]
    let chinese: [String: String] = [
        "coach": "效率指南",
        "contextBurn": "上下文消耗",
        "cacheHealth": "缓存健康",
        "modelEffort": "模型与推理强度实验室",
        "contextSources": "上下文来源",
        "sessionOutliers": "会话异常",
        "projectEfficiency": "项目效率",
        "smartNudge": "智能提醒",
        "coachSubtitle": "把用量转化为有优先级、可解释的行动。",
        "opportunities": "优化机会",
        "contextSessions": "已测会话",
        "cacheReuse": "缓存复用率",
        "timeframe": "时间范围",
        "topOpportunities": "优先机会",
        "opportunitiesSubtitle": "基于本地用量模式与可信度门槛。",
        "allServices": "全部服务",
        "service": "服务",
        "noInsights": "暂时没有高可信优化机会",
        "noInsightsDetail": "当本地可比较用量足够时，AgentBar 会显示建议。",
        "privacyNote": "仅根据本地用量元数据计算，不保留提示、回复、代码或工具输出内容。",
        "smartNudgeSubtitle": "当会话接近上下文上限时给出及时的本地信号。",
        "contextNudge": "检测到上下文压力",
        "nudgeDetail": "此会话已使用 %d%% 的上下文窗口（%@）。",
        "reviewEvidence": "查看证据",
        "noNudge": "暂无提醒",
        "noNudgeDetail": "当前没有会话同时达到证据与上下文压力门槛。",
        "samples": "个样本",
        "sessions": "个会话",
        "tasks": "个任务",
        "high": "高",
        "medium": "中",
        "low": "低",
        "highImpact": "高影响",
        "mediumImpact": "中等影响",
        "contextTitle": "单个会话上下文达到 %d%%",
        "contextDetail": "长会话正在接近已测上下文上限，可评估开启新会话的检查点。",
        "cacheTitle": "缓存复用率降至 %d%%",
        "cacheDetail": "复用率低于你的个人基线，可在下个同类会话测试稳定前缀和重复设置。",
        "outlierTitle": "未缓存输入达到 %@",
        "outlierDetail": "此已完成会话高于同项目、同模型的个人基线。",
        "seeEvidence": "查看证据",
        "tryNextSession": "下个会话试用",
        "trialQueued": "已加入试验",
        "dismiss": "忽略",
        "refresh": "刷新",
        "contextBurnSubtitle": "在会话变得拥挤前查看已测上下文占用。",
        "session": "会话",
        "contextOccupancy": "当前上下文占用",
        "contextChartDetail": "输入上下文相对于服务方报告的模型窗口。",
        "freshCheckpoint": "可考虑开启新会话检查点",
        "contextHealthy": "上下文占用低于复核门槛",
        "sessionFacts": "会话信息",
        "model": "模型",
        "project": "项目",
        "growth": "近期增长",
        "confidence": "可信度",
        "whyContextMatters": "为什么重要",
        "whyContextDetail": "上下文增长会压缩新信息空间。携带简洁交接摘要开启新会话，可帮助保持聚焦。",
        "currentContext": "当前上下文",
        "peakContext": "峰值上下文",
        "contextWindow": "上下文窗口",
        "cacheHealthSubtitle": "了解提示缓存复用与未缓存输入，不虚构无法观测的节省。",
        "cacheReuseDetail": "由缓存提供的输入占比",
        "uncachedInput": "未缓存输入",
        "uncachedDetail": "观测到未由缓存提供的输入",
        "totalInput": "总输入",
        "measuredLocally": "根据本地用量元数据测量",
        "cacheByService": "各服务缓存复用率",
        "lowestCacheSessions": "缓存复用率最低的会话",
        "modelEffortSubtitle": "根据本地项目、模型与推理强度历史，手动设计小规模实验。",
        "evaluatedGroups": "已观察项目",
        "localTaskGroups": "任务历史中的项目标签",
        "experimentCandidates": "手动实验候选",
        "safeToTrial": "达到六个任务的历史门槛",
        "trialsStarted": "已开始试验",
        "localOnly": "仅本地界面状态，不自动切换模型",
        "unknownProject": "未知项目",
        "reversibleExperiment": "手动实验，不代表质量建议",
        "experimentWarning": "这些任务只共享提供商、项目、模型与推理强度。AgentBar 无法判断任务是否相似，也无法确认较低强度是否保持质量。请自行选择可比较的未来任务并评估质量。",
        "sampleSize": "样本量",
        "currentControl": "当前（对照）",
        "trialExperiment": "试验",
        "startTrial": "开始 %d 个任务试验",
        "unavailable": "数据不可用",
        "unavailableDetail": "所选时间范围内没有足够的兼容本地用量元数据。"
    ]
    return (language == .chinese ? chinese : english)[key] ?? key
}
