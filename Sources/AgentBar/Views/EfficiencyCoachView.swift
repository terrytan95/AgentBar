import AppKit
import Foundation
import SwiftUI

enum EfficiencyCoachPage: String, CaseIterable, Identifiable {
    case coach
    case contextBurn
    case cacheHealth

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .coach: "sparkles"
        case .contextBurn: "chart.line.uptrend.xyaxis"
        case .cacheHealth: "externaldrive.fill.badge.checkmark"
        }
    }
}

struct EfficiencyCoachView: View {
    @ObservedObject var store: UsageStore
    @State private var page: EfficiencyCoachPage = .coach
    @State private var selectedService = "all"
    @State private var selectedContextSessionID = ""
    @State private var copiedHandoffSessionID: String?
    @State private var navigationAnchor: EfficiencyCoachPage = .coach

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            pageNavigation

            if store.isLoadingSessionData {
                LoadingAccountPanel(
                    title: L.text("loading_session_data", store.language),
                    subtitle: L.text("loading_session_data_subtitle", store.language)
                )
            }

            if page == .coach {
                coach
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    Group {
                        switch page {
                        case .coach:
                            EmptyView()
                        case .contextBurn:
                            ContextBurnEfficiencyView(
                                store: store,
                                selectedSessionID: $selectedContextSessionID
                            )
                        case .cacheHealth:
                            CacheHealthEfficiencyView(store: store)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.bottom, 24)
                }
            }
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
        let actionSession = contextSessions.first {
            $0.confidence.meetsMinimum
                && $0.latestOccupancyRatio >= 0.70
                && ($0.recentInputGrowthRatio ?? 0) > 0
        }
        let pressureSessions = contextSessions.filter {
            $0.confidence.meetsMinimum && $0.latestOccupancyRatio >= 0.70
        }
        let cachedInput = cache.compactMap(\.cachedInputTokens).reduce(0, +)
        let totalInput = cache.compactMap(\.inputTokens).reduce(0, +)
        let cacheRatio = totalInput > 0 ? Double(cachedInput) / Double(totalInput) : nil
        let cacheHealthy = !cache.contains { summary in
            guard summary.confidence.meetsMinimum,
                  let ratio = summary.cacheRatio,
                  let baseline = summary.personalBaselineRatio
            else { return false }
            return ratio + 0.10 < baseline
        }

        return VStack(alignment: .leading, spacing: 16) {
            header(
                title: efficiencyText("coach", store.language),
                subtitle: efficiencyText("coachSubtitle", store.language)
            )

            statusStrip(
                measuredSessions: contextSessions.count,
                hasAction: actionSession != nil,
                cacheRatio: cacheRatio,
                cacheHealthy: cacheHealthy
            )

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if let actionSession {
                        primaryActionCard(
                            actionSession,
                            pressureSessions: pressureSessions,
                            cacheRatio: cacheRatio,
                            cacheHealthy: cacheHealthy
                        )
                    } else {
                        noActionCard
                    }

                    secondaryCards

                    Label(efficiencyText("privacyNote", store.language), systemImage: "lock.shield")
                        .font(.agentBar(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 24)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
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

    private func statusStrip(
        measuredSessions: Int,
        hasAction: Bool,
        cacheRatio: Double?,
        cacheHealthy: Bool
    ) -> some View {
        let cacheValue = cacheRatio.map(percent) ?? "—"
        let cacheStatus = cacheRatio == nil
            ? efficiencyText("unavailable", store.language)
            : efficiencyText(cacheHealthy ? "healthy" : "review", store.language)
        let cacheColor: Color = cacheRatio == nil ? .secondary : (cacheHealthy ? .green : .orange)

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                statusItem(
                    store.selectedRange.dashboardLabel(store.language),
                    icon: "calendar",
                    color: AgentBarPalette.primary
                )
                statusDivider
                statusItem(
                    "\(measuredSessions) \(efficiencyText("sessions", store.language))",
                    icon: "bubble.left.and.bubble.right",
                    color: AgentBarPalette.primary
                )
                statusDivider
                statusItem(
                    efficiencyText(hasAction ? "oneAction" : "noActions", store.language),
                    icon: "bolt",
                    color: hasAction ? AgentBarPalette.primary : .green
                )
                statusDivider
                statusItem(
                    "\(efficiencyText("cacheReuse", store.language)) \(cacheValue) \(cacheStatus)",
                    icon: "externaldrive.fill.badge.checkmark",
                    color: cacheColor
                )
            }
            .frame(minHeight: 58)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                statusItem(
                    store.selectedRange.dashboardLabel(store.language),
                    icon: "calendar",
                    color: AgentBarPalette.primary
                )
                statusItem(
                    "\(measuredSessions) \(efficiencyText("sessions", store.language))",
                    icon: "bubble.left.and.bubble.right",
                    color: AgentBarPalette.primary
                )
                statusItem(
                    efficiencyText(hasAction ? "oneAction" : "noActions", store.language),
                    icon: "bolt",
                    color: hasAction ? AgentBarPalette.primary : .green
                )
                statusItem(
                    "\(efficiencyText("cacheReuse", store.language)) \(cacheValue) \(cacheStatus)",
                    icon: "externaldrive.fill.badge.checkmark",
                    color: cacheColor
                )
            }
            .padding(8)
        }
        .agentBarPanel(cornerRadius: 12)
    }

    private func statusItem(_ text: String, icon: String, color: Color) -> some View {
        Label {
            Text(text)
                .lineLimit(1)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
        }
        .font(.agentBar(size: 11, weight: .bold))
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var statusDivider: some View {
        Divider()
            .frame(height: 26)
    }

    private func primaryActionCard(
        _ session: ContextBurnSession,
        pressureSessions: [ContextBurnSession],
        cacheRatio: Double?,
        cacheHealthy: Bool
    ) -> some View {
        let target = session.scope.projectName?.trimmedNonEmpty ?? session.scope.service.rawValue
        let minimumPressure = pressureSessions.map(\.latestOccupancyRatio).min() ?? session.latestOccupancyRatio
        let maximumPressure = pressureSessions.map(\.latestOccupancyRatio).max() ?? session.latestOccupancyRatio
        let copied = copiedHandoffSessionID == session.sessionID

        return VStack(alignment: .leading, spacing: 16) {
            Text(efficiencyText("doNow", store.language))
                .font(.agentBar(size: 11, weight: .bold))
                .foregroundStyle(AgentBarPalette.primary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AgentBarPalette.primary.opacity(0.09))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: efficiencyText("handoffTitle", store.language), target))
                    .font(.agentBar(size: 24, weight: .bold))
                Text(efficiencyText("handoffDetail", store.language))
                    .font(.agentBar(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    evidenceChip(
                        String(
                            format: efficiencyText("highestContext", store.language),
                            percent(maximumPressure)
                        ),
                        icon: "chart.line.uptrend.xyaxis",
                        color: AgentBarPalette.primary
                    )
                    evidenceChip(
                        String(
                            format: efficiencyText("pressureSessions", store.language),
                            pressureSessions.count,
                            percent(minimumPressure),
                            percent(maximumPressure)
                        ),
                        icon: "bubble.left.and.bubble.right",
                        color: AgentBarPalette.primary
                    )
                    evidenceChip(
                        cacheRatio.map {
                            String(
                                format: efficiencyText(
                                    cacheHealthy ? "cacheNormal" : "cacheReview",
                                    store.language
                                ),
                                percent($0)
                            )
                        } ?? efficiencyText("cacheUnavailable", store.language),
                        icon: "externaldrive.fill.badge.checkmark",
                        color: cacheRatio == nil ? .secondary : (cacheHealthy ? .green : .orange)
                    )
                }

                VStack(spacing: 8) {
                    evidenceChip(
                        String(
                            format: efficiencyText("highestContext", store.language),
                            percent(maximumPressure)
                        ),
                        icon: "chart.line.uptrend.xyaxis",
                        color: AgentBarPalette.primary
                    )
                    evidenceChip(
                        String(
                            format: efficiencyText("pressureSessions", store.language),
                            pressureSessions.count,
                            percent(minimumPressure),
                            percent(maximumPressure)
                        ),
                        icon: "bubble.left.and.bubble.right",
                        color: AgentBarPalette.primary
                    )
                    evidenceChip(
                        cacheRatio.map {
                            String(
                                format: efficiencyText(
                                    cacheHealthy ? "cacheNormal" : "cacheReview",
                                    store.language
                                ),
                                percent($0)
                            )
                        } ?? efficiencyText("cacheUnavailable", store.language),
                        icon: "externaldrive.fill.badge.checkmark",
                        color: cacheRatio == nil ? .secondary : (cacheHealthy ? .green : .orange)
                    )
                }
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.on.clipboard")
                    .font(.agentBar(size: 17, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(efficiencyText("handoffPrompt", store.language))
                    .font(.agentBar(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AgentBarPalette.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AgentBarPalette.primary.opacity(0.16), lineWidth: 1)
            )

            HStack(spacing: 10) {
                Button {
                    copyHandoff(for: session)
                } label: {
                    Label(
                        efficiencyText(copied ? "copied" : "copyHandoff", store.language),
                        systemImage: copied ? "checkmark" : "doc.on.clipboard"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    selectedContextSessionID = session.id
                    page = .contextBurn
                } label: {
                    Label(efficiencyText("viewSession", store.language), systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .font(.agentBar(size: 12, weight: .bold))

            Label(efficiencyText("verificationDetail", store.language), systemImage: "checkmark.circle")
                .font(.agentBar(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .agentBarPanel(cornerRadius: 14)
    }

    private func evidenceChip(_ text: String, icon: String, color: Color) -> some View {
        Label {
            Text(text)
                .lineLimit(1)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
        }
        .font(.agentBar(size: 11, weight: .bold))
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AgentBarDesign.panelHighlight)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var noActionCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.agentBar(size: 28, weight: .bold))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 5) {
                Text(efficiencyText("noActionTitle", store.language))
                    .font(.agentBar(size: 17, weight: .bold))
                Text(efficiencyText("noActionDetail", store.language))
                    .font(.agentBar(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .agentBarPanel(cornerRadius: 14)
    }

    private var secondaryCards: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                secondaryCard(
                    title: efficiencyText("upNext", store.language),
                    detail: efficiencyText("noMoreActions", store.language),
                    icon: "calendar",
                    color: AgentBarPalette.primary
                )
                secondaryCard(
                    title: efficiencyText("recentVerification", store.language),
                    detail: efficiencyText(
                        copiedHandoffSessionID == nil ? "verificationEmpty" : "verificationPending",
                        store.language
                    ),
                    icon: "chart.line.uptrend.xyaxis",
                    color: AgentBarPalette.primary
                )
            }

            VStack(spacing: 12) {
                secondaryCard(
                    title: efficiencyText("upNext", store.language),
                    detail: efficiencyText("noMoreActions", store.language),
                    icon: "calendar",
                    color: AgentBarPalette.primary
                )
                secondaryCard(
                    title: efficiencyText("recentVerification", store.language),
                    detail: efficiencyText(
                        copiedHandoffSessionID == nil ? "verificationEmpty" : "verificationPending",
                        store.language
                    ),
                    icon: "chart.line.uptrend.xyaxis",
                    color: AgentBarPalette.primary
                )
            }
        }
    }

    private func secondaryCard(
        title: String,
        detail: String,
        icon: String,
        color: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.agentBar(size: 19, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(color.opacity(0.1)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.agentBar(size: 14, weight: .bold))
                Text(detail)
                    .font(.agentBar(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .agentBarPanel(cornerRadius: 12)
    }

    private func copyHandoff(for session: ContextBurnSession) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(efficiencyText("handoffPrompt", store.language), forType: .string)
        copiedHandoffSessionID = session.sessionID
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
            servicePicker
            UsageRangeControls(
                range: $store.selectedRange,
                customStart: $store.customStart,
                customEnd: $store.customEnd,
                language: store.language
            )
            Button {
                store.refresh(force: true, showManualFeedback: true)
            } label: {
                Label(efficiencyText("refresh", store.language), systemImage: "arrow.clockwise")
                    .font(.agentBar(size: 12, weight: .bold))
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct ContextBurnEfficiencyView: View {
    @ObservedObject var store: UsageStore
    @Binding var selectedSessionID: String

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
        "coachSubtitle": "Turn usage into your next action.",
        "oneAction": "1 action",
        "noActions": "0 actions",
        "healthy": "healthy",
        "review": "review",
        "doNow": "Do now · about 5 min",
        "handoffTitle": "Give %@’s long session a handoff",
        "handoffDetail": "Create a factual handoff, then continue in a fresh session.",
        "highestContext": "Highest %@",
        "pressureSessions": "%d sessions reached %@–%@",
        "cacheNormal": "Cache %@ healthy",
        "cacheReview": "Cache %@ needs review",
        "cacheUnavailable": "Cache unavailable",
        "handoffPrompt": "Create a handoff I can carry into a new session: goal, completed work, changed files, verification results, unfinished items, and the exact next step. Include only known facts and do not continue the task.",
        "copyHandoff": "Copy handoff prompt",
        "copied": "Copied",
        "viewSession": "View session",
        "verificationDetail": "The next session in this project will be used for verification.",
        "noActionTitle": "No action needed now",
        "noActionDetail": "No measured session crossed the handoff threshold in this range.",
        "upNext": "Up next",
        "noMoreActions": "No other required action right now.",
        "recentVerification": "Recent verification",
        "verificationEmpty": "Complete an action to see the observed before-and-after change.",
        "verificationPending": "Handoff copied. Start a fresh session to verify the change.",
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
        "unavailable": "Data unavailable",
        "unavailableDetail": "The selected range does not contain enough compatible local usage metadata."
    ]
    let chinese: [String: String] = [
        "coach": "效率指南",
        "contextBurn": "上下文消耗",
        "cacheHealth": "缓存健康",
        "coachSubtitle": "把用量转化为下一步行动。",
        "oneAction": "1 个行动",
        "noActions": "0 个行动",
        "healthy": "正常",
        "review": "需留意",
        "doNow": "现在做 · 约 5 分钟",
        "handoffTitle": "给 %@ 的长会话做一次交接",
        "handoffDetail": "先生成事实交接，再开启新会话。",
        "highestContext": "最高 %@",
        "pressureSessions": "%d 个会话达到 %@–%@",
        "cacheNormal": "缓存 %@ 正常",
        "cacheReview": "缓存 %@ 需留意",
        "cacheUnavailable": "缓存数据不可用",
        "handoffPrompt": "请输出一份可带入新会话的事实交接：目标、已完成、改动文件、验证结果、未完成事项、明确下一步。只写已知事实，不继续执行任务。",
        "copyHandoff": "复制交接指令",
        "copied": "已复制",
        "viewSession": "查看对应会话",
        "verificationDetail": "下个同项目会话将用于验收。",
        "noActionTitle": "现在无需行动",
        "noActionDetail": "所选范围内没有已测会话达到交接门槛。",
        "upNext": "之后行动",
        "noMoreActions": "暂无其他必须处理的行动。",
        "recentVerification": "最近验证",
        "verificationEmpty": "完成一次行动后显示前后变化。",
        "verificationPending": "交接指令已复制；开启新会话后即可验证变化。",
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
        "unavailable": "数据不可用",
        "unavailableDetail": "所选时间范围内没有足够的兼容本地用量元数据。"
    ]
    return (language == .chinese ? chinese : english)[key] ?? key
}
