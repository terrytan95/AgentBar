import SwiftUI

struct ContextSourcesEfficiencyView: View {
    @ObservedObject var store: UsageStore
    @State private var timingFilter: ContextSourceTimingFilter = .all
    @State private var serviceFilter: UsageService?

    init(store: UsageStore) {
        self.store = store
    }

    private var sources: [ContextSourceStat] {
        let knownContextNames = Set(["AGENTS.md", "CLAUDE.md"])
        let candidates = Dictionary(
            grouping: store.usageDataDisplayPoints.flatMap { point -> [ContextSourceCandidate] in
                var urls: [URL] = []
                if let root = point.repositoryPath ?? point.cwd, root.hasPrefix("/") {
                    let name = point.service == .codex ? "AGENTS.md" : point.service == .claudeCode ? "CLAUDE.md" : nil
                    if let name {
                        urls.append(URL(fileURLWithPath: root).appendingPathComponent(name))
                    }
                }
                if let path = point.sourceFile, path.hasPrefix("/") {
                    let url = URL(fileURLWithPath: path)
                    if knownContextNames.contains(url.lastPathComponent) {
                        urls.append(url)
                    }
                }
                return urls.map {
                    ContextSourceCandidate(url: $0, service: point.service, loadTiming: .session)
                }
            },
            by: { "\($0.service.rawValue)|\($0.url.standardizedFileURL.path)" }
        )
        .compactMap { $0.value.first }

        return TokenEfficiencyAnalytics.contextSourceStats(candidates).filter {
            (serviceFilter == nil || $0.service == serviceFilter)
                && timingFilter.matches($0.loadTiming)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EfficiencySupportingHeader(
                title: efficiencySupportingText("context_sources", store.language),
                subtitle: efficiencySupportingText("context_sources_subtitle", store.language),
                icon: "doc.text.magnifyingglass",
                language: store.language
            ) {
                store.refresh(force: true, showManualFeedback: true)
            }

            localOnlyBanner
            controls

            if sources.isEmpty {
                emptySources
            } else {
                sourceSummary
                sourceList
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var localOnlyBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.agentBar(size: 17, weight: .bold))
                .foregroundStyle(AgentBarPalette.primary)
                .frame(width: 36, height: 36)
                .background(AgentBarPalette.primary.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(efficiencySupportingText("local_only", store.language))
                    .font(.agentBar(size: 13, weight: .bold))
                Text(efficiencySupportingText("local_only_detail", store.language))
                    .font(.agentBar(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .agentBarPanel(cornerRadius: 12)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("", selection: $timingFilter) {
                ForEach(ContextSourceTimingFilter.allCases) { filter in
                    Text(filter.title(store.language)).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            .accessibilityLabel(efficiencySupportingText("load_timing", store.language))

            Picker(efficiencySupportingText("provider", store.language), selection: $serviceFilter) {
                Text(efficiencySupportingText("all_providers", store.language))
                    .tag(nil as UsageService?)
                ForEach(UsageService.allCases) { service in
                    Text(service.rawValue).tag(service as UsageService?)
                }
            }
            .frame(width: 190)
            Spacer()
        }
    }

    private var sourceSummary: some View {
        let bytes = sources.reduce(0) { $0 + $1.byteCount }
        let tokens = sources.reduce(0) { $0 + $1.estimatedTokenCount }
        return HStack(spacing: 14) {
            EfficiencySupportingMetric(
                title: efficiencySupportingText("visible_sources", store.language),
                value: "\(sources.count)",
                icon: "doc.on.doc.fill",
                color: AgentBarPalette.primary
            )
            EfficiencySupportingMetric(
                title: efficiencySupportingText("metadata_size", store.language),
                value: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file),
                icon: "internaldrive.fill",
                color: .purple
            )
            EfficiencySupportingMetric(
                title: efficiencySupportingText("estimated_tokens", store.language),
                value: DisplayFormatters.compactTokenString(tokens, language: store.language),
                icon: "text.word.spacing",
                color: .green
            )
        }
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(efficiencySupportingText("source", store.language))
                Spacer()
                Text(efficiencySupportingText("provider", store.language)).frame(width: 110, alignment: .leading)
                Text(efficiencySupportingText("size", store.language)).frame(width: 90, alignment: .trailing)
                Text(efficiencySupportingText("estimated_tokens", store.language)).frame(width: 110, alignment: .trailing)
                Text(efficiencySupportingText("load_timing", store.language)).frame(width: 110, alignment: .trailing)
            }
            .font(.agentBar(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(14)
            Divider()

            ForEach(sources) { source in
                HStack(spacing: 12) {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(AgentBarPalette.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.url.lastPathComponent)
                            .font(.agentBar(size: 12, weight: .bold))
                        Text(source.url.deletingLastPathComponent().path)
                            .font(.agentBarMono(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text(source.service.rawValue).frame(width: 110, alignment: .leading)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(source.byteCount), countStyle: .file))
                        .frame(width: 90, alignment: .trailing)
                    Text(DisplayFormatters.compactTokenString(source.estimatedTokenCount, language: store.language))
                        .frame(width: 110, alignment: .trailing)
                    Text(source.loadTiming.title(store.language))
                        .frame(width: 110, alignment: .trailing)
                }
                .font(.agentBar(size: 11, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: 58)
                Divider()
            }
        }
        .agentBarPanel(cornerRadius: 14)
    }

    private var emptySources: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.badge.ellipsis")
                .font(.system(size: 34))
                .foregroundStyle(AgentBarPalette.primary)
            Text(efficiencySupportingText("no_context_sources", store.language))
                .font(.agentBar(size: 16, weight: .bold))
            Text(efficiencySupportingText("no_context_sources_detail", store.language))
                .font(.agentBar(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .agentBarPanel(cornerRadius: 14)
    }
}

struct SessionOutliersEfficiencyView: View {
    @ObservedObject var store: UsageStore
    @State private var expectedOutlierIDs: Set<String> = []
    @State private var evidenceOutlierID: String?

    init(store: UsageStore) {
        self.store = store
    }

    private var outliers: [SessionEfficiencyOutlier] {
        TokenEfficiencyAnalytics.sessionOutliers(
            points: store.usageDataDisplayPoints,
            tasks: store.auditTasks,
            range: store.selectedRange,
            customStart: store.customStart,
            customEnd: store.customEnd
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EfficiencySupportingHeader(
                title: efficiencySupportingText("session_outliers", store.language),
                subtitle: efficiencySupportingText("session_outliers_subtitle", store.language),
                icon: "sparkles",
                language: store.language
            ) {
                store.refresh(force: true, showManualFeedback: true)
            }

            if outliers.isEmpty {
                emptyOutliers
            } else {
                outlierSummary
                outlierList
                privacyNote
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var outlierSummary: some View {
        let visible = outliers.filter { !expectedOutlierIDs.contains($0.id) }
        let medianMultiple = visible.compactMap { outlier -> Double? in
            guard outlier.baselineUncachedInputTokens > 0 else { return nil }
            return Double(outlier.uncachedInputTokens) / outlier.baselineUncachedInputTokens
        }.sorted()
        let multiple = medianMultiple.isEmpty ? nil : medianMultiple[medianMultiple.count / 2]

        return HStack(spacing: 14) {
            EfficiencySupportingMetric(
                title: efficiencySupportingText("unreviewed_sessions", store.language),
                value: "\(visible.count)",
                icon: "exclamationmark.bubble.fill",
                color: .orange
            )
            EfficiencySupportingMetric(
                title: efficiencySupportingText("typical_multiple", store.language),
                value: multiple.map { String(format: "%.1f×", $0) } ?? efficiencySupportingText("unavailable", store.language),
                icon: "chart.bar.xaxis",
                color: AgentBarPalette.primary
            )
            EfficiencySupportingMetric(
                title: efficiencySupportingText("baseline", store.language),
                value: efficiencySupportingText("same_project_p95", store.language),
                icon: "scope",
                color: .purple
            )
        }
    }

    private var outlierList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(efficiencySupportingText("session", store.language))
                Spacer()
                Text(efficiencySupportingText("uncached_input", store.language)).frame(width: 120, alignment: .trailing)
                Text(efficiencySupportingText("project_baseline", store.language)).frame(width: 120, alignment: .trailing)
                Text(efficiencySupportingText("difference", store.language)).frame(width: 90, alignment: .trailing)
                Text(efficiencySupportingText("actions", store.language)).frame(width: 220, alignment: .trailing)
            }
            .font(.agentBar(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(14)
            Divider()

            ForEach(outliers) { outlier in
                outlierRow(outlier)
                Divider()
                if evidenceOutlierID == outlier.id {
                    evidenceRow(outlier)
                    Divider()
                }
            }
        }
        .agentBarPanel(cornerRadius: 14)
    }

    private func outlierRow(_ outlier: SessionEfficiencyOutlier) -> some View {
        let expected = expectedOutlierIDs.contains(outlier.id)
        let multiple = outlier.baselineUncachedInputTokens > 0
            ? Double(outlier.uncachedInputTokens) / outlier.baselineUncachedInputTokens
            : nil
        return HStack(spacing: 12) {
            Circle()
                .fill(expected ? Color.secondary : Color.orange)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(outlier.title?.trimmedNonEmpty ?? shortSessionID(outlier.sessionID))
                    .font(.agentBar(size: 12, weight: .bold))
                    .lineLimit(1)
                Text("\(outlier.scope.service.rawValue) · \(outlier.scope.projectName ?? efficiencySupportingText("unknown_project", store.language))")
                    .font(.agentBar(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(DisplayFormatters.compactTokenString(outlier.uncachedInputTokens, language: store.language))
                .frame(width: 120, alignment: .trailing)
            Text(DisplayFormatters.compactTokenString(Int(outlier.baselineUncachedInputTokens), language: store.language))
                .frame(width: 120, alignment: .trailing)
            Text(multiple.map { String(format: "%.1f×", $0) } ?? efficiencySupportingText("unavailable", store.language))
                .foregroundStyle(expected ? Color.secondary : Color.orange)
                .frame(width: 90, alignment: .trailing)
            HStack(spacing: 8) {
                Button(efficiencySupportingText("inspect_evidence", store.language)) {
                    evidenceOutlierID = evidenceOutlierID == outlier.id ? nil : outlier.id
                }
                .buttonStyle(.bordered)
                Button(expected
                    ? efficiencySupportingText("marked_expected", store.language)
                    : efficiencySupportingText("mark_expected", store.language)
                ) {
                    if expected {
                        expectedOutlierIDs.remove(outlier.id)
                    } else {
                        expectedOutlierIDs.insert(outlier.id)
                    }
                }
                .buttonStyle(.bordered)
            }
            .frame(width: 220, alignment: .trailing)
        }
        .font(.agentBarMono(size: 10, weight: .semibold))
        .padding(.horizontal, 14)
        .frame(minHeight: 62)
        .opacity(expected ? 0.58 : 1)
    }

    private func evidenceRow(_ outlier: SessionEfficiencyOutlier) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(efficiencySupportingText("evidence", store.language))
                .font(.agentBar(size: 11, weight: .bold))
            Text(String(
                format: efficiencySupportingText("evidence_detail", store.language),
                outlier.confidence.sampleSize,
                outlier.thresholdUncachedInputTokens
            ))
            .font(.agentBar(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            Text(efficiencySupportingText("telemetry_only", store.language))
                .font(.agentBar(size: 10, weight: .bold))
                .foregroundStyle(AgentBarPalette.primary)
        }
        .padding(14)
        .background(AgentBarPalette.primary.opacity(0.06))
    }

    private var privacyNote: some View {
        Label(efficiencySupportingText("outlier_privacy", store.language), systemImage: "lock.fill")
            .font(.agentBar(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private var emptyOutliers: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.green)
            Text(efficiencySupportingText("no_outliers", store.language))
                .font(.agentBar(size: 16, weight: .bold))
            Text(efficiencySupportingText("no_outliers_detail", store.language))
                .font(.agentBar(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .agentBarPanel(cornerRadius: 14)
    }
}

struct ProjectEfficiencyView: View {
    @ObservedObject var store: UsageStore
    @State private var selectedProjectID: String?

    init(store: UsageStore) {
        self.store = store
    }

    private var projects: [ProjectEfficiencySummary] {
        TokenEfficiencyAnalytics.projectEfficiency(
            points: store.usageDataDisplayPoints,
            tasks: store.auditTasks,
            range: store.selectedRange,
            customStart: store.customStart,
            customEnd: store.customEnd
        )
    }

    var body: some View {
        let selected = projects.first { $0.id == selectedProjectID } ?? projects.first
        VStack(alignment: .leading, spacing: 16) {
            EfficiencySupportingHeader(
                title: efficiencySupportingText("project_efficiency", store.language),
                subtitle: efficiencySupportingText("project_efficiency_subtitle", store.language),
                icon: "chart.xyaxis.line",
                language: store.language
            ) {
                store.refresh(force: true, showManualFeedback: true)
            }

            if projects.isEmpty {
                emptyProjects
            } else if let selected {
                projectPicker(selected: selected)
                metrics(selected)
                projectEvidence(selected)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func projectPicker(selected: ProjectEfficiencySummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundStyle(AgentBarPalette.primary)
            Picker(efficiencySupportingText("project", store.language), selection: $selectedProjectID) {
                ForEach(projects) { project in
                    Text("\(project.name) · \(project.service.rawValue)")
                        .tag(project.id as String?)
                }
            }
            .frame(maxWidth: 360)
            Text(selected.path ?? selected.service.rawValue)
                .font(.agentBarMono(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            UsageRangeControls(
                range: $store.selectedRange,
                customStart: $store.customStart,
                customEnd: $store.customEnd,
                language: store.language
            )
        }
        .padding(12)
        .agentBarPanel(cornerRadius: 12)
    }

    private func metrics(_ project: ProjectEfficiencySummary) -> some View {
        HStack(spacing: 14) {
            EfficiencySupportingMetric(
                title: efficiencySupportingText("tokens_per_task", store.language),
                value: project.tokensPerCompletedTask.map {
                    DisplayFormatters.compactTokenString(Int($0), language: store.language)
                } ?? efficiencySupportingText("unavailable", store.language),
                icon: "waveform.path.ecg",
                color: AgentBarPalette.primary
            )
            EfficiencySupportingMetric(
                title: efficiencySupportingText("cache_reuse", store.language),
                value: percent(project.cacheRatio),
                icon: "link",
                color: .green
            )
            EfficiencySupportingMetric(
                title: efficiencySupportingText("long_context_sessions", store.language),
                value: project.longContextSessionCount.map(String.init)
                    ?? efficiencySupportingText("unavailable", store.language),
                icon: "timer",
                color: .purple
            )
            EfficiencySupportingMetric(
                title: efficiencySupportingText("reasoning_share", store.language),
                value: percent(project.reasoningShare),
                icon: "brain.head.profile",
                color: .orange
            )
        }
    }

    private func projectEvidence(_ project: ProjectEfficiencySummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(efficiencySupportingText("project_evidence", store.language))
                        .font(.agentBar(size: 15, weight: .bold))
                    Text(efficiencySupportingText("project_evidence_detail", store.language))
                        .font(.agentBar(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                confidencePill(project.confidence)
            }

            Divider()

            HStack(spacing: 14) {
                evidenceFact(
                    efficiencySupportingText("completed_tasks", store.language),
                    "\(project.completedTaskCount)",
                    "checkmark.circle.fill",
                    .green
                )
                evidenceFact(
                    efficiencySupportingText("provider", store.language),
                    project.service.rawValue,
                    "server.rack",
                    AgentBarPalette.primary
                )
                evidenceFact(
                    efficiencySupportingText("comparison_scope", store.language),
                    efficiencySupportingText("same_project", store.language),
                    "scope",
                    .purple
                )
            }

            Label(efficiencySupportingText("project_comparison_note", store.language), systemImage: "info.circle")
                .font(.agentBar(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .agentBarPanel(cornerRadius: 14)
    }

    private func evidenceFact(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.agentBar(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.agentBar(size: 12, weight: .bold))
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
    }

    private func confidencePill(_ confidence: TokenEfficiencyConfidence) -> some View {
        Text("\(efficiencySupportingText("confidence", store.language)): \(confidence.level.title(store.language)) · \(confidence.sampleSize)")
            .font(.agentBar(size: 10, weight: .bold))
            .foregroundStyle(confidence.meetsMinimum ? Color.green : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background((confidence.meetsMinimum ? Color.green : Color.secondary).opacity(0.1), in: Capsule())
    }

    private var emptyProjects: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 34))
                .foregroundStyle(AgentBarPalette.primary)
            Text(efficiencySupportingText("no_project_efficiency", store.language))
                .font(.agentBar(size: 16, weight: .bold))
            Text(efficiencySupportingText("no_project_efficiency_detail", store.language))
                .font(.agentBar(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .agentBarPanel(cornerRadius: 14)
    }

    private func percent(_ value: Double?) -> String {
        value.map { String(format: "%.0f%%", $0 * 100) }
            ?? efficiencySupportingText("unavailable", store.language)
    }
}

struct EfficiencySmartNudgeCard: View {
    var nudge: TokenEfficiencyNudge
    var language: AppLanguage
    var onDismiss: () -> Void
    var onOpen: () -> Void

    init(
        nudge: TokenEfficiencyNudge,
        language: AppLanguage,
        onDismiss: @escaping () -> Void,
        onOpen: @escaping () -> Void
    ) {
        self.nudge = nudge
        self.language = language
        self.onDismiss = onDismiss
        self.onOpen = onOpen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(AgentBarPalette.primary.opacity(0.14), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: min(1, nudge.contextOccupancyRatio))
                        .stroke(AgentBarPalette.primary, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(nudge.contextOccupancyRatio * 100))%")
                        .font(.agentBarMono(size: 12, weight: .bold))
                        .foregroundStyle(AgentBarPalette.primary)
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 3) {
                    Text(String(
                        format: efficiencySupportingText("context_at", language),
                        Int(nudge.contextOccupancyRatio * 100)
                    ))
                    .font(.agentBar(size: 14, weight: .bold))
                    Text(efficiencySupportingText("fresh_task_suggestion", language))
                        .font(.agentBar(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.agentBar(size: 10, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .tactilePlainButton()
                .accessibilityLabel(efficiencySupportingText("dismiss", language))
            }

            Button(action: onOpen) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                    Text(efficiencySupportingText("open_efficiency_coach", language))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.agentBar(size: 11, weight: .bold))
                .foregroundStyle(AgentBarPalette.primary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(AgentBarPalette.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            }
            .tactilePlainButton()
        }
        .padding(14)
        .agentBarPanel(cornerRadius: 12)
    }
}

private struct EfficiencySupportingHeader: View {
    var title: String
    var subtitle: String
    var icon: String
    var language: AppLanguage
    var onRefresh: () -> Void

    init(
        title: String,
        subtitle: String,
        icon: String,
        language: AppLanguage,
        onRefresh: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.language = language
        self.onRefresh = onRefresh
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.agentBar(size: 18, weight: .bold))
                .foregroundStyle(AgentBarPalette.primary)
                .frame(width: 40, height: 40)
                .background(AgentBarPalette.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.agentBar(size: 20, weight: .bold))
                Text(subtitle)
                    .font(.agentBar(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onRefresh) {
                Label(efficiencySupportingText("refresh", language), systemImage: "arrow.clockwise")
            }
                .font(.agentBar(size: 12, weight: .bold))
                .foregroundStyle(AgentBarPalette.primary)
                .padding(.horizontal, 13)
                .frame(height: 38)
                .tactilePlainButton()
                .agentBarPanel(cornerRadius: 11)
        }
    }
}

private struct EfficiencySupportingMetric: View {
    var title: String
    var value: String
    var icon: String
    var color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.agentBar(size: 16, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.agentBar(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.agentBarMono(size: 18, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .agentBarPanel(cornerRadius: 12)
    }
}

private enum ContextSourceTimingFilter: String, CaseIterable, Identifiable {
    case all
    case always
    case onDemand

    var id: String { rawValue }

    func matches(_ timing: ContextSourceLoadTiming) -> Bool {
        switch self {
        case .all: true
        case .always: timing == .always || timing == .session || timing == .unknown
        case .onDemand: timing == .onDemand
        }
    }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .all: efficiencySupportingText("all_sources", language)
        case .always: efficiencySupportingText("always_loaded", language)
        case .onDemand: efficiencySupportingText("on_demand", language)
        }
    }
}

private extension ContextSourceLoadTiming {
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .always: efficiencySupportingText("always", language)
        case .session: efficiencySupportingText("session_start", language)
        case .onDemand: efficiencySupportingText("on_demand", language)
        case .unknown: efficiencySupportingText("unknown", language)
        }
    }
}

private extension TokenEfficiencyConfidenceLevel {
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .low: efficiencySupportingText("low", language)
        case .medium: efficiencySupportingText("medium", language)
        case .high: efficiencySupportingText("high", language)
        }
    }
}

private func shortSessionID(_ id: String) -> String {
    id.count > 10 ? "\(id.prefix(8))…" : id
}

private func efficiencySupportingText(_ key: String, _ language: AppLanguage) -> String {
    let english: [String: String] = [
        "actions": "Actions",
        "all_providers": "All providers",
        "all_sources": "All",
        "always": "Always",
        "always_loaded": "Always loaded",
        "baseline": "Baseline",
        "cache_reuse": "Cache reuse",
        "comparison_scope": "Comparison scope",
        "completed_tasks": "Completed tasks",
        "confidence": "Confidence",
        "context_at": "Context at %d%%",
        "context_sources": "Context Sources",
        "context_sources_subtitle": "A privacy-safe inventory of known context files in detected project roots.",
        "difference": "Difference",
        "dismiss": "Dismiss",
        "estimated_tokens": "Tokens (est.)",
        "evidence": "Evidence",
        "evidence_detail": "Compared with %d completed sessions; the local p95 threshold is %.0f uncached input tokens.",
        "fresh_task_suggestion": "Consider a fresh task after this checkpoint.",
        "high": "High",
        "inspect_evidence": "Inspect evidence",
        "load_timing": "Load timing",
        "local_only": "Local analysis only",
        "local_only_detail": "Only file paths and sizes are used. File contents are never read or retained.",
        "long_context_sessions": "Long-context sessions",
        "low": "Low",
        "mark_expected": "Mark expected",
        "marked_expected": "Expected",
        "medium": "Medium",
        "metadata_size": "Metadata size",
        "no_context_sources": "No explicit context sources available",
        "no_context_sources_detail": "AgentBar checks only known filenames in detected project roots. It does not scan folders or read file contents.",
        "no_outliers": "No supported outliers in this range",
        "no_outliers_detail": "Outliers require at least eight comparable completed sessions in the same project, provider, and model.",
        "no_project_efficiency": "No project efficiency data in this range",
        "no_project_efficiency_detail": "Choose another range or complete tasks inside a detected repository.",
        "on_demand": "On demand",
        "open_efficiency_coach": "Open Efficiency Guide",
        "outlier_privacy": "Calculated from token telemetry only; prompt and response content is not analyzed.",
        "project": "Project",
        "project_baseline": "Project baseline",
        "project_comparison_note": "Values are compared only within this project. Missing telemetry is shown as unavailable, not zero.",
        "project_efficiency": "Project Efficiency",
        "project_efficiency_subtitle": "Compare working patterns within the same project.",
        "project_evidence": "Supporting evidence",
        "project_evidence_detail": "Local, deterministic measurements from completed tasks in the selected range.",
        "provider": "Provider",
        "refresh": "Refresh",
        "reasoning_share": "Reasoning share",
        "same_project": "Same project",
        "same_project_p95": "Same-project p95",
        "session": "Session",
        "session_outliers": "Session Outliers",
        "session_outliers_subtitle": "Find unusually expensive sessions using token telemetry only.",
        "session_start": "Session start",
        "size": "Size",
        "source": "Source",
        "telemetry_only": "No prompt content analyzed",
        "tokens_per_task": "Tokens / completed task",
        "typical_multiple": "Typical multiple",
        "unavailable": "Unavailable",
        "uncached_input": "Uncached input",
        "unknown": "Unknown",
        "unknown_project": "Unknown project",
        "unreviewed_sessions": "Unreviewed sessions",
        "visible_sources": "Visible sources"
    ]
    let chinese: [String: String] = [
        "actions": "操作",
        "all_providers": "全部提供商",
        "all_sources": "全部",
        "always": "始终",
        "always_loaded": "始终加载",
        "baseline": "基线",
        "cache_reuse": "缓存复用率",
        "comparison_scope": "比较范围",
        "completed_tasks": "已完成任务",
        "confidence": "置信度",
        "context_at": "上下文占用 %d%%",
        "context_sources": "上下文来源",
        "context_sources_subtitle": "以隐私安全方式清点已识别项目根目录中的已知上下文文件。",
        "difference": "差异",
        "dismiss": "关闭",
        "estimated_tokens": "Token（估算）",
        "evidence": "依据",
        "evidence_detail": "与 %d 个已完成会话比较；本地 p95 阈值为 %.0f 个未缓存输入 Token。",
        "fresh_task_suggestion": "建议在此检查点之后新建任务。",
        "high": "高",
        "inspect_evidence": "查看依据",
        "load_timing": "加载时机",
        "local_only": "仅限本地分析",
        "local_only_detail": "仅使用文件路径和大小；绝不读取或保留文件内容。",
        "long_context_sessions": "长上下文会话",
        "low": "低",
        "mark_expected": "标记为预期",
        "marked_expected": "符合预期",
        "medium": "中",
        "metadata_size": "元数据大小",
        "no_context_sources": "没有可用的明确上下文来源",
        "no_context_sources_detail": "AgentBar 只检查已识别项目根目录中的已知文件名，不扫描目录，也不读取文件内容。",
        "no_outliers": "所选范围内没有满足条件的异常值",
        "no_outliers_detail": "异常检测至少需要同项目、提供商和模型的八个可比已完成会话。",
        "no_project_efficiency": "所选范围内没有项目效率数据",
        "no_project_efficiency_detail": "请选择其他范围，或在可识别的代码仓库中完成任务。",
        "on_demand": "按需",
        "open_efficiency_coach": "打开效率指南",
        "outlier_privacy": "仅根据 Token 遥测计算；不分析提示词或回复内容。",
        "project": "项目",
        "project_baseline": "项目基线",
        "project_comparison_note": "数值仅在此项目内比较。缺失遥测显示为不可用，而非零。",
        "project_efficiency": "项目效率",
        "project_efficiency_subtitle": "在同一项目内比较工作模式。",
        "project_evidence": "支持依据",
        "project_evidence_detail": "来自所选范围已完成任务的本地确定性测量。",
        "provider": "提供商",
        "refresh": "刷新",
        "reasoning_share": "推理占比",
        "same_project": "同一项目",
        "same_project_p95": "同项目 p95",
        "session": "会话",
        "session_outliers": "会话异常",
        "session_outliers_subtitle": "仅使用 Token 遥测识别异常昂贵的会话。",
        "session_start": "会话开始",
        "size": "大小",
        "source": "来源",
        "telemetry_only": "未分析提示词内容",
        "tokens_per_task": "每个已完成任务 Token",
        "typical_multiple": "典型倍数",
        "unavailable": "不可用",
        "uncached_input": "未缓存输入",
        "unknown": "未知",
        "unknown_project": "未知项目",
        "unreviewed_sessions": "待审查会话",
        "visible_sources": "可见来源"
    ]
    return language == .chinese ? chinese[key] ?? english[key] ?? key : english[key] ?? key
}
