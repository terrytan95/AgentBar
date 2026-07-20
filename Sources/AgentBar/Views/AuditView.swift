import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AuditView: View {
    @ObservedObject var store: UsageStore
    var points: [UsagePoint]
    var selectedSessionLabel: String?
    var dataSourceHealth: DataSourceHealthSummary
    var onClearSessionSelection: () -> Void = {}

    @State private var selectedTab: AuditUsageTab = .threads
    @State private var selectedTaskID: String?
    @State private var expandedThreadID: String?
    @State private var exportStatus: String?
    @State private var tasksPage = 0
    @State private var threadsPage = 0
    @State private var sortColumn: AuditSortColumn = .time
    @State private var sortAscending = false
    @State private var kpiGridColumns = 6

    private let pageSize = 20
    nonisolated private static let kpiCardCount = 6
    nonisolated private static let kpiCardHeight: CGFloat = 96
    nonisolated private static let kpiGridSpacing: CGFloat = 12

    private var snapshot: AuditUsageSnapshot {
        AuditUsageSnapshot.make(
            points: points,
            tasks: store.auditTasks,
            range: store.selectedRange,
            customStart: store.customStart,
            customEnd: store.customEnd,
            selectedSessionLabel: selectedSessionLabel,
            sortColumn: sortColumn,
            sortAscending: sortAscending
        )
    }

    var body: some View {
        let preparedSnapshot = snapshot

        VStack(alignment: .leading, spacing: 14) {
            header(preparedSnapshot)
            if let codexSessionScanNote {
                scanWarning(codexSessionScanNote)
            }
            kpiGrid(preparedSnapshot)
            tablePanel(preparedSnapshot)
            exportPanel(preparedSnapshot)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            applySessionSelection(to: preparedSnapshot)
        }
        .onChange(of: selectedSessionLabel) { _, _ in applySessionSelection(to: preparedSnapshot) }
        .onChange(of: preparedSnapshot.taskIDs) { _, ids in
            tasksPage = clampedPage(tasksPage, total: ids.count)
            threadsPage = clampedPage(threadsPage, total: preparedSnapshot.threadRows.count)
            guard let selectedTaskID, ids.contains(selectedTaskID) else {
                self.selectedTaskID = ids.first
                return
            }
        }
    }

    private func header(_ snapshot: AuditUsageSnapshot) -> some View {
        HStack(alignment: .center, spacing: 16) {
            if selectedSessionLabel != nil {
                Button {
                    clearSessionSelection()
                } label: {
                    Label(localized("back_to_audit"), systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .pointingHandCursor()
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(localized("title"))
                    .font(.agentBar(size: 20, weight: .bold))
                Text(localized("subtitle"))
                    .font(.agentBar(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            auditRangePicker
            statusPill(snapshot)
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
    }

    private var auditRangePicker: some View {
        UsageRangeControls(
            range: $store.selectedRange,
            customStart: $store.customStart,
            customEnd: $store.customEnd,
            language: store.language
        )
    }

    private func statusPill(_ snapshot: AuditUsageSnapshot) -> some View {
        Text("\(snapshot.rangeTasks.count) \(localized("tasks")) · JSONL")
            .font(.agentBar(size: 12, weight: .bold))
            .foregroundStyle(AgentBarPalette.primary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var codexSessionScanNote: String? {
        guard let note = dataSourceHealth.rows.first(where: { $0.service == .codex })?.note,
              note.hasPrefix("Codex session scan skipped")
        else { return nil }
        return L.codexSessionScanWarning(note, language: store.language)
    }

    private func scanWarning(_ note: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(note)
                .font(.agentBar(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 34)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func kpiGrid(_ snapshot: AuditUsageSnapshot) -> some View {
        GeometryReader { proxy in
            let columns = Self.kpiGridColumns(for: proxy.size.width)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.kpiGridSpacing), count: columns), spacing: Self.kpiGridSpacing) {
                metricCard(localized("visible_tasks"), "\(snapshot.rangeTasks.count)")
                metricCard(localized("total_tokens"), DisplayFormatters.compactTokenString(snapshot.composition.total, language: store.language))
                metricCard(localized("cached_input"), DisplayFormatters.compactTokenString(snapshot.composition.cachedInput, language: store.language))
                metricCard(localized("uncached_input"), DisplayFormatters.compactTokenString(max(0, snapshot.composition.input - snapshot.composition.cachedInput), language: store.language))
                metricCard(localized("reasoning_output"), DisplayFormatters.compactTokenString(snapshot.composition.reasoningOutput, language: store.language))
                metricCard(localized("estimated_cost"), costText(snapshot.totalCost))
            }
            .onAppear { setKpiGridColumns(columns) }
            .onChange(of: columns) { _, columns in setKpiGridColumns(columns) }
        }
        .frame(height: Self.kpiGridHeight(columns: kpiGridColumns))
    }

    nonisolated static func kpiGridColumns(for width: CGFloat) -> Int {
        width < 980 ? 3 : 6
    }

    nonisolated static func kpiGridHeight(for width: CGFloat) -> CGFloat {
        kpiGridHeight(columns: kpiGridColumns(for: width))
    }

    nonisolated static func kpiGridHeight(columns: Int) -> CGFloat {
        let rows = CGFloat((kpiCardCount + columns - 1) / columns)
        return rows * kpiCardHeight + max(0, rows - 1) * kpiGridSpacing
    }

    private func setKpiGridColumns(_ columns: Int) {
        guard kpiGridColumns != columns else { return }
        kpiGridColumns = columns
    }

    private func metricCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.agentBar(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.agentBarMono(size: 22, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: Self.kpiCardHeight, alignment: .topLeading)
        .agentBarPanel(cornerRadius: 12)
    }

    private func tablePanel(_ snapshot: AuditUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(selectedTab == .tasks ? localized("model_tasks") : localized("threads"))
                    .font(.agentBar(size: 16, weight: .bold))
                Picker("", selection: $selectedTab) {
                    ForEach(AuditUsageTab.allCases) { tab in
                        Text(tab.title(language: store.language)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                Spacer()
                Button {
                    export(format: .csv, snapshot: snapshot)
                } label: {
                    Label("CSV", systemImage: "tablecells")
                }
                .buttonStyle(.bordered)
                .pointingHandCursor()
            }
            .padding(16)

            Divider()

            Text(selectedTab == .tasks ? localized("tasks_caption") : localized("threads_caption"))
                .font(.agentBar(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            VStack(spacing: 0) {
                tableHeader
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)

                Divider()

                if selectedTab == .tasks {
                    tasksTable(snapshot)
                } else {
                    threadsTable(snapshot)
                }
            }
        }
        .agentBarPanel(cornerRadius: 14)
    }

    private var tableHeader: some View {
        HStack(spacing: 8) {
            sortHeader(.time, localized("time"), width: 108, alignment: .leading)
            sortThreadHeader(localized("thread"))
            sortHeader(.model, localized("model"), width: 76)
            sortHeader(.effort, localized("effort"), width: 50)
            sortHeader(.tps, localized("tps"), width: 48)
            sortHeader(.firstToken, localized("first_token"), width: 72)
            sortHeader(.duration, localized("duration"), width: 64)
            sortHeader(.tokens, localized("tokens"), width: 68)
            sortHeader(.cached, localized("cached"), width: 68)
            sortHeader(.uncached, localized("uncached"), width: 68)
            sortHeader(.output, localized("output"), width: 58)
            sortHeader(.reasoning, localized("reasoning"), width: 58)
        }
        .font(.agentBar(size: 11, weight: .bold))
        .foregroundStyle(.secondary)
    }

    private func tasksTable(_ snapshot: AuditUsageSnapshot) -> some View {
        VStack(spacing: 0) {
            ForEach(page(snapshot.sortedTasks, index: clampedPage(tasksPage, total: snapshot.rangeTasks.count))) { task in
                taskRow(task, threadTitle: snapshot.sessionTitle(for: task), nested: false)
                if selectedTaskID == task.id {
                    taskDetail(task: task, threadTitle: snapshot.sessionTitle(for: task))
                }
                Divider()
            }
            paginationFooter(total: snapshot.rangeTasks.count, page: $tasksPage, itemName: localized("tasks"))
        }
    }

    private func threadsTable(_ snapshot: AuditUsageSnapshot) -> some View {
        VStack(spacing: 0) {
            ForEach(page(snapshot.threadRows, index: clampedPage(threadsPage, total: snapshot.threadRows.count))) { thread in
                threadRow(thread)
                if expandedThreadID == thread.id {
                    ForEach(thread.tasks.prefix(20)) { task in
                        taskRow(task, threadTitle: thread.title, nested: true)
                        if selectedTaskID == task.id {
                            taskDetail(task: task, threadTitle: thread.title)
                        }
                    }
                }
                Divider()
            }
            paginationFooter(total: snapshot.threadRows.count, page: $threadsPage, itemName: localized("threads"))
        }
    }

    private func taskRow(_ task: AgentTask, threadTitle: String, nested: Bool) -> some View {
        Button {
            selectedTaskID = task.id
        } label: {
            HStack(spacing: 8) {
                column(dateText(task.auditDate), width: 108, alignment: .leading)
                threadColumn((nested ? "  " : "") + threadTitle, strong: true)
                column(modelText(task.models), width: 76, pill: true)
                column(task.reasoningEffort ?? "—", width: 50)
                column(tpsText(task.tokensPerSecond), width: 48)
                column(millisecondsText(task.validTimeToFirstTokenMilliseconds), width: 72)
                column(millisecondsText(task.reportedDurationMilliseconds), width: 64)
                column(DisplayFormatters.compactTokenString(task.tokens.total, language: store.language), width: 68)
                column(DisplayFormatters.compactTokenString(task.tokens.cachedInput, language: store.language), width: 68)
                column(DisplayFormatters.compactTokenString(task.uncachedInputTokens, language: store.language), width: 68)
                column(DisplayFormatters.compactTokenString(task.tokens.output, language: store.language), width: 58)
                column(DisplayFormatters.compactTokenString(task.tokens.reasoningOutput, language: store.language), width: 58)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, nested ? 8 : 11)
            .background(selectedTaskID == task.id ? AgentBarPalette.primary.opacity(0.10) : Color.clear)
            .contentShape(Rectangle())
        }
        .tactilePlainButton(pressedScale: 1)
    }

    private func threadRow(_ thread: AuditThreadRow) -> some View {
        Button {
            expandedThreadID = expandedThreadID == thread.id ? nil : thread.id
            selectedTaskID = thread.tasks.first?.id
        } label: {
            HStack(spacing: 8) {
                column(dateText(thread.latest), width: 108, alignment: .leading)
                HStack(spacing: 8) {
                    Image(systemName: expandedThreadID == thread.id ? "minus.circle.fill" : "plus.circle.fill")
                        .foregroundStyle(AgentBarPalette.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(thread.title)
                            .font(.agentBar(size: 12, weight: .bold))
                            .lineLimit(2)
                        Text("\(thread.tasks.count) \(localized("tasks")) · \(thread.projectName)")
                            .font(.agentBar(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                column(modelText(thread.models), width: 76, pill: true)
                column(effortText(thread.reasoningEfforts), width: 50)
                column(tpsText(thread.tokensPerSecond), width: 48)
                column(millisecondsText(thread.averageTimeToFirstTokenMilliseconds), width: 72)
                column(millisecondsText(thread.reportedDurationMilliseconds), width: 64)
                column(DisplayFormatters.compactTokenString(thread.tokens.total, language: store.language), width: 68)
                column(DisplayFormatters.compactTokenString(thread.tokens.cachedInput, language: store.language), width: 68)
                column(DisplayFormatters.compactTokenString(max(0, thread.tokens.input - thread.tokens.cachedInput), language: store.language), width: 68)
                column(DisplayFormatters.compactTokenString(thread.tokens.output, language: store.language), width: 58)
                column(DisplayFormatters.compactTokenString(thread.tokens.reasoningOutput, language: store.language), width: 58)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .tactilePlainButton(pressedScale: 1)
    }

    private func column(_ text: String, width: CGFloat? = nil, alignment: Alignment = .trailing, strong: Bool = false, pill: Bool = false) -> some View {
        Text(text)
            .font(.agentBar(size: 12, weight: strong ? .bold : .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.62)
            .padding(.horizontal, pill ? 8 : 0)
            .frame(width: width, alignment: alignment)
            .foregroundStyle(pill ? AgentBarPalette.primary : .primary.opacity(0.9))
            .background(pill ? AgentBarPalette.primary.opacity(0.10) : Color.clear, in: Capsule())
    }

    private func threadColumn(_ text: String, strong: Bool = false) -> some View {
        Text(text)
            .font(.agentBar(size: 12, weight: strong ? .bold : .semibold))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.primary.opacity(0.9))
    }

    private func sortHeader(_ column: AuditSortColumn, _ text: String, width: CGFloat, alignment: Alignment = .trailing) -> some View {
        Button {
            setSort(column)
        } label: {
            HStack(spacing: 3) {
                Text(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.agentBar(size: 9, weight: .bold))
                }
            }
            .frame(width: width, height: 18, alignment: alignment)
            .contentShape(Rectangle())
        }
        .tactilePlainButton(pressedScale: 1)
    }

    private func sortThreadHeader(_ text: String) -> some View {
        Button {
            setSort(.thread)
        } label: {
            HStack(spacing: 3) {
                Text(text)
                    .lineLimit(1)
                if sortColumn == .thread {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.agentBar(size: 9, weight: .bold))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
            .contentShape(Rectangle())
        }
        .tactilePlainButton(pressedScale: 1)
    }

    private func taskDetail(task: AgentTask, threadTitle: String) -> some View {
        let models = task.models.isEmpty ? "—" : task.models.joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localized("task_investigator"))
                        .font(.agentBar(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(task.title ?? threadTitle)
                        .font(.agentBar(size: 16, weight: .bold))
                    Text("\(dateText(task.auditDate)) · \(threadTitle) · \(task.reasoningEffort ?? "—")")
                        .font(.agentBar(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let sourceFile = task.sourceFile {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: sourceFile)])
                    } label: {
                        Label(localized("show_source"), systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .pointingHandCursor()
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                detailCard(localized("tps"), tpsText(task.tokensPerSecond), localized("end_to_end_throughput"))
                detailCard(localized("first_token"), millisecondsText(task.validTimeToFirstTokenMilliseconds), localized("reported_by_codex"))
                detailCard(localized("duration"), millisecondsText(task.reportedDurationMilliseconds), localized("reported_by_codex"))
                detailCard(localized("last_call_input"), DisplayFormatters.tokenString(task.tokens.input), localized("exact_from_callback"))
                detailCard(localized("cached_input"), DisplayFormatters.tokenString(task.tokens.cachedInput), "")
                detailCard(localized("uncached_input"), DisplayFormatters.tokenString(task.uncachedInputTokens), localized("fresh_context"))
                detailCard(localized("output"), DisplayFormatters.tokenString(task.tokens.output), localized("assistant_output"))
                detailCard(localized("reasoning_output"), DisplayFormatters.tokenString(task.tokens.reasoningOutput), localized("reasoning"))
                detailCard(localized("estimated_cost"), costText(task.estimatedCostUSD), localized("configured_price"))
                detailCard(localized("model"), models, task.reasoningEffort ?? "—")
                detailCard("Task ID", task.id, task.sessionID)
                detailCard("Cwd", task.cwd ?? "—", task.projectName ?? "—")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AgentBarPalette.primary.opacity(0.06))
    }

    private func detailCard(_ title: String, _ value: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.agentBar(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.agentBar(size: 15, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.68)
                .textSelection(.enabled)
            Text(subtitle)
                .font(.agentBar(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func exportPanel(_ snapshot: AuditUsageSnapshot) -> some View {
        HStack(spacing: 10) {
            Text(localized("privacy_note"))
                .font(.agentBar(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let exportStatus {
                Text(exportStatus)
                    .font(.agentBar(size: 11, weight: .bold))
                    .foregroundStyle(AgentBarPalette.primary)
            }
            Button {
                export(format: .json, snapshot: snapshot)
            } label: {
                Label("JSON", systemImage: "curlybraces")
            }
            .buttonStyle(.bordered)
            .pointingHandCursor()
        }
        .padding(14)
        .agentBarPanel(cornerRadius: 12)
    }

    private func footer(text: String) -> some View {
        Text(text)
            .font(.agentBar(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }

    private func paginationFooter(total: Int, page: Binding<Int>, itemName: String) -> some View {
        let currentPage = clampedPage(page.wrappedValue, total: total)
        let start = total == 0 ? 0 : currentPage * pageSize + 1
        let end = min(total, (currentPage + 1) * pageSize)
        let pageCount = max(1, Int(ceil(Double(total) / Double(pageSize))))

        return HStack(spacing: 10) {
            Button {
                page.wrappedValue = max(0, currentPage - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .disabled(currentPage == 0)
            .pointingHandCursor()

            Text("\(start)-\(end) / \(total) \(itemName) · \(localized("page")) \(currentPage + 1)/\(pageCount)")
                .font(.agentBar(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 190)

            Button {
                page.wrappedValue = min(pageCount - 1, currentPage + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .disabled(currentPage >= pageCount - 1)
            .pointingHandCursor()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func page<T>(_ values: [T], index: Int) -> [T] {
        let start = min(values.count, max(0, index) * pageSize)
        let end = min(values.count, start + pageSize)
        return Array(values[start..<end])
    }

    private func clampedPage(_ page: Int, total: Int) -> Int {
        min(max(0, page), max(0, (total - 1) / pageSize))
    }

    private func setSort(_ column: AuditSortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = column.defaultAscending
        }
        tasksPage = 0
        threadsPage = 0
    }

    private func applySessionSelection(to snapshot: AuditUsageSnapshot) {
        selectedTaskID = selectedTaskID ?? snapshot.taskIDs.first
        guard selectedSessionLabel != nil else { return }
        selectedTab = .threads
        tasksPage = 0
        threadsPage = 0
        expandedThreadID = snapshot.threadRows.first?.id
        selectedTaskID = snapshot.threadRows.first?.tasks.first?.id ?? snapshot.taskIDs.first
    }

    private func clearSessionSelection() {
        selectedTab = .threads
        selectedTaskID = nil
        expandedThreadID = nil
        tasksPage = 0
        threadsPage = 0
        onClearSessionSelection()
    }

    private func export(format: UsageExportFormat, snapshot: AuditUsageSnapshot) {
        let rows = selectedTab == .tasks
            ? snapshot.taskExportRows
            : snapshot.threadExportRows
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "AgentBar-audit-\(selectedTab.rawValue).\(format.rawValue)"
        panel.allowedContentTypes = format == .csv ? [.commaSeparatedText] : [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try UsageAuditReporter.serialize(rows: rows, format: format).write(to: url, atomically: true, encoding: .utf8)
            exportStatus = "\(localized("exported")) \(url.lastPathComponent)"
        } catch {
            exportStatus = "\(localized("export_failed")) \(error.localizedDescription)"
        }
    }

    private func tpsText(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.0f", value)
    }

    private func millisecondsText(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return "—" }
        if value < 1_000 { return String(format: "%.0f ms", value) }
        if value < 10_000 { return String(format: "%.2f s", value / 1_000) }
        return String(format: "%.1f s", value / 1_000)
    }

    private func modelText(_ models: [String]) -> String {
        summarizedText(models)
    }

    private func effortText(_ efforts: [String]) -> String {
        summarizedText(efforts)
    }

    private func summarizedText(_ values: [String]) -> String {
        let values = Array(Set(values)).sorted()
        guard let first = values.first else { return "—" }
        return values.count == 1 ? first : localized("mixed")
    }

    private func dateText(_ date: Date) -> String {
        DisplayFormatters.localizedDateString(for: date, template: "MMM d, h:mm a", language: store.language)
    }

    private func costText(_ value: Decimal?) -> String {
        guard let value else { return "-" }
        return DisplayFormatters.costString(value)
    }

    private func localized(_ key: String) -> String {
        L.text(key, store.language)
    }
}

struct AuditUsageSnapshot {
    var rangePoints: [UsagePoint]
    var rangeTasks: [AgentTask]
    var sortedCalls: [UsagePoint]
    var sortedTasks: [AgentTask]
    var threadRows: [AuditThreadRow]
    var sessionTitles: [String: String]
    var composition: TokenTotals
    var totalCost: Decimal?
    var callIDs: [String]
    var taskIDs: [String]

    static func make(
        points: [UsagePoint],
        tasks: [AgentTask] = [],
        range: UsageRange,
        customStart: Date?,
        customEnd: Date?,
        selectedSessionLabel: String? = nil,
        sortColumn: AuditSortColumn,
        sortAscending: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AuditUsageSnapshot {
        let sessionTitles = makeSessionTitles(points)
        let rangePoints = UsageRangeProjection.filteredPoints(
            points: points,
            range: range,
            now: now,
            calendar: calendar,
            customStart: customStart,
            customEnd: customEnd
        )
        .filter { point in
            guard let selectedSessionLabel else { return true }
            return sessionLabel(for: point) == selectedSessionLabel
        }
        .sorted { $0.date > $1.date }
        let interval = range.dateInterval(
            now: now,
            calendar: calendar,
            customStart: customStart,
            customEnd: customEnd
        )
        let rangeTasks = tasks.filter { task in
            guard interval?.contains(task.auditDate) ?? true else { return false }
            guard let selectedSessionLabel else { return true }
            return sessionLabel(for: task, titles: sessionTitles) == selectedSessionLabel
        }
        .sorted { $0.auditDate > $1.auditDate }
        let threadRows = sortedThreads(
            makeThreadRows(rangePoints, tasks: rangeTasks, sessionTitles: sessionTitles),
            sortColumn: sortColumn,
            sortAscending: sortAscending
        )

        return AuditUsageSnapshot(
            rangePoints: rangePoints,
            rangeTasks: rangeTasks,
            sortedCalls: sortedCalls(rangePoints, sortColumn: sortColumn, sortAscending: sortAscending),
            sortedTasks: sortedTasks(
                rangeTasks,
                sessionTitles: sessionTitles,
                sortColumn: sortColumn,
                sortAscending: sortAscending
            ),
            threadRows: threadRows,
            sessionTitles: sessionTitles,
            composition: rangePoints.reduce(TokenTotals.zero) { $0 + $1.tokens },
            totalCost: totalCost(rangePoints),
            callIDs: rangePoints.map(\.callID),
            taskIDs: rangeTasks.map(\.id)
        )
    }

    func sessionTitle(for task: AgentTask) -> String {
        Self.sessionLabel(for: task, titles: sessionTitles)
    }

    var taskExportRows: [UsageAuditPerformanceExportRow] {
        sortedTasks.map { task in
            UsageAuditPerformanceExportRow(
                kind: "task",
                date: task.auditDate,
                sessionID: task.sessionID,
                sessionTitle: sessionTitle(for: task),
                taskID: task.id,
                taskTitle: task.title,
                projectName: task.projectName,
                models: task.models.joined(separator: ", "),
                reasoningEffort: task.reasoningEffort,
                inputTokens: task.tokens.input,
                cachedInputTokens: task.tokens.cachedInput,
                outputTokens: task.tokens.output,
                reasoningOutputTokens: task.tokens.reasoningOutput,
                totalTokens: task.tokens.total,
                durationMilliseconds: task.reportedDurationSeconds.map { $0 * 1_000 },
                timeToFirstTokenMilliseconds: task.validTimeToFirstTokenMilliseconds,
                tokensPerSecond: task.tokensPerSecond,
                estimatedCostUSD: task.estimatedCostUSD
            )
        }
    }

    var threadExportRows: [UsageAuditPerformanceExportRow] {
        threadRows.map { thread in
            UsageAuditPerformanceExportRow(
                kind: "thread",
                date: thread.latest,
                sessionID: thread.tasks.first?.sessionID ?? thread.calls.first?.sessionID ?? thread.id,
                sessionTitle: thread.title,
                taskID: nil,
                taskTitle: nil,
                projectName: thread.projectName,
                models: thread.models.joined(separator: ", "),
                reasoningEffort: thread.reasoningEfforts.count == 1 ? thread.reasoningEfforts[0] : nil,
                inputTokens: thread.tokens.input,
                cachedInputTokens: thread.tokens.cachedInput,
                outputTokens: thread.tokens.output,
                reasoningOutputTokens: thread.tokens.reasoningOutput,
                totalTokens: thread.tokens.total,
                durationMilliseconds: thread.reportedDurationMilliseconds,
                timeToFirstTokenMilliseconds: thread.averageTimeToFirstTokenMilliseconds,
                tokensPerSecond: thread.tokensPerSecond,
                estimatedCostUSD: thread.cost
            )
        }
    }

    private static func sessionLabel(for point: UsagePoint) -> String {
        point.sessionTitle ?? point.sessionID ?? "Unknown session"
    }

    private static func makeSessionTitles(_ points: [UsagePoint]) -> [String: String] {
        points.sorted { $0.date > $1.date }.reduce(into: [:]) { titles, point in
            guard let sessionID = point.sessionID,
                  titles[sessionID] == nil
            else { return }
            titles[sessionID] = sessionLabel(for: point)
        }
    }

    private static func sessionLabel(for task: AgentTask, titles: [String: String]) -> String {
        titles[task.sessionID] ?? task.title ?? task.sessionID
    }

    private static func threadID(for point: UsagePoint) -> String {
        point.sessionID ?? sessionLabel(for: point)
    }

    private static func makeThreadRows(
        _ points: [UsagePoint],
        tasks: [AgentTask],
        sessionTitles: [String: String]
    ) -> [AuditThreadRow] {
        let pointGroups = Dictionary(grouping: points, by: threadID(for:))
        let taskGroups = Dictionary(grouping: tasks, by: \.sessionID)
        let threadIDs = Set(pointGroups.keys).union(taskGroups.keys)

        return threadIDs.map { threadID in
            let calls = pointGroups[threadID] ?? []
            let tasks = taskGroups[threadID] ?? []
            let sortedCalls = calls.sorted { $0.date > $1.date }
            let sortedTasks = tasks.sorted { $0.auditDate > $1.auditDate }
            let totals = tasks.isEmpty
                ? calls.reduce(TokenTotals.zero) { $0 + $1.tokens }
                : tasks.reduce(TokenTotals.zero) { $0 + $1.tokens }
            let durationSeconds = durationSeconds(calls: calls)
            let timedTasks = tasks.compactMap { task -> (task: AgentTask, durationMilliseconds: Double)? in
                guard let duration = task.reportedDurationMilliseconds,
                      task.reportedDurationSeconds != nil
                else { return nil }
                return (task, duration)
            }
            let hasCompleteDurationCoverage = !tasks.isEmpty && timedTasks.count == tasks.count
            let reportedDurationMilliseconds = hasCompleteDurationCoverage
                ? timedTasks.reduce(0) { $0 + $1.durationMilliseconds }
                : nil
            let timedOutputTokens = timedTasks.reduce(0) { $0 + $1.task.tokens.output }
            let tokensPerSecond = reportedDurationMilliseconds.map { milliseconds in
                Double(timedOutputTokens) / (milliseconds / 1_000)
            }
            let firstTokenValues = tasks.compactMap(\.validTimeToFirstTokenMilliseconds)
            let averageFirstToken = !tasks.isEmpty && firstTokenValues.count == tasks.count
                ? firstTokenValues.reduce(0, +) / Double(firstTokenValues.count)
                : nil
            let projectName = sortedTasks.first?.projectName
                ?? sortedCalls.first?.projectName
                ?? "Unknown project"
            let latest = (calls.map(\.date) + tasks.map(\.auditDate)).max() ?? .distantPast
            let title = sessionTitles[threadID]
                ?? sortedCalls.first.map(sessionLabel(for:))
                ?? sortedTasks.first?.title
                ?? threadID
            return AuditThreadRow(
                id: tasks.isEmpty ? title : threadID,
                title: title,
                subtitle: "\(tasks.count) tasks · \(projectName)",
                projectName: projectName,
                latest: latest,
                durationSeconds: durationSeconds,
                duration: durationText(seconds: durationSeconds),
                tokens: totals,
                cost: tasks.isEmpty ? totalCost(calls) : totalTaskCost(tasks),
                calls: sortedCalls,
                tasks: sortedTasks,
                models: Array(Set(tasks.flatMap(\.models))).sorted(),
                reasoningEfforts: Array(Set(tasks.compactMap(\.reasoningEffort))).sorted(),
                reportedDurationMilliseconds: reportedDurationMilliseconds,
                averageTimeToFirstTokenMilliseconds: averageFirstToken,
                tokensPerSecond: tokensPerSecond
            )
        }
    }

    private static func sortedCalls(_ calls: [UsagePoint], sortColumn: AuditSortColumn, sortAscending: Bool) -> [UsagePoint] {
        if sortColumn == .time && !sortAscending { return calls }
        return calls.sorted { lhs, rhs in
            if let ordered = callOrder(lhs, rhs, sortColumn: sortColumn, sortAscending: sortAscending) { return ordered }
            return lhs.date > rhs.date
        }
    }

    private static func sortedTasks(
        _ tasks: [AgentTask],
        sessionTitles: [String: String],
        sortColumn: AuditSortColumn,
        sortAscending: Bool
    ) -> [AgentTask] {
        if sortColumn == .time && !sortAscending { return tasks }
        return tasks.sorted { lhs, rhs in
            if let ordered = taskOrder(
                lhs,
                rhs,
                sessionTitles: sessionTitles,
                sortColumn: sortColumn,
                sortAscending: sortAscending
            ) { return ordered }
            return lhs.auditDate > rhs.auditDate
        }
    }

    private static func sortedThreads(_ threads: [AuditThreadRow], sortColumn: AuditSortColumn, sortAscending: Bool) -> [AuditThreadRow] {
        threads.sorted { lhs, rhs in
            if let ordered = threadOrder(lhs, rhs, sortColumn: sortColumn, sortAscending: sortAscending) { return ordered }
            return lhs.latest > rhs.latest
        }
    }

    private static func callOrder(_ lhs: UsagePoint, _ rhs: UsagePoint, sortColumn: AuditSortColumn, sortAscending: Bool) -> Bool? {
        switch sortColumn {
        case .time:
            ordered(lhs.date, rhs.date, sortAscending: sortAscending)
        case .thread:
            ordered(sessionLabel(for: lhs), sessionLabel(for: rhs), sortAscending: sortAscending)
        case .duration:
            nil
        case .tps, .firstToken:
            nil
        case .model:
            ordered(lhs.model, rhs.model, sortAscending: sortAscending)
        case .effort:
            ordered(lhs.reasoningEffort ?? "", rhs.reasoningEffort ?? "", sortAscending: sortAscending)
        case .tokens:
            ordered(lhs.tokens.total, rhs.tokens.total, sortAscending: sortAscending)
        case .cached:
            ordered(lhs.tokens.cachedInput, rhs.tokens.cachedInput, sortAscending: sortAscending)
        case .uncached:
            ordered(lhs.uncachedInputTokens, rhs.uncachedInputTokens, sortAscending: sortAscending)
        case .output:
            ordered(lhs.tokens.output, rhs.tokens.output, sortAscending: sortAscending)
        case .reasoning:
            ordered(lhs.tokens.reasoningOutput, rhs.tokens.reasoningOutput, sortAscending: sortAscending)
        }
    }

    private static func taskOrder(
        _ lhs: AgentTask,
        _ rhs: AgentTask,
        sessionTitles: [String: String],
        sortColumn: AuditSortColumn,
        sortAscending: Bool
    ) -> Bool? {
        switch sortColumn {
        case .time:
            ordered(lhs.auditDate, rhs.auditDate, sortAscending: sortAscending)
        case .thread:
            ordered(
                sessionLabel(for: lhs, titles: sessionTitles),
                sessionLabel(for: rhs, titles: sessionTitles),
                sortAscending: sortAscending
            )
        case .model:
            ordered(lhs.models.first ?? "", rhs.models.first ?? "", sortAscending: sortAscending)
        case .effort:
            ordered(lhs.reasoningEffort ?? "", rhs.reasoningEffort ?? "", sortAscending: sortAscending)
        case .tps:
            orderedOptional(lhs.tokensPerSecond, rhs.tokensPerSecond, sortAscending: sortAscending)
        case .firstToken:
            orderedOptional(
                lhs.validTimeToFirstTokenMilliseconds,
                rhs.validTimeToFirstTokenMilliseconds,
                sortAscending: sortAscending
            )
        case .duration:
            orderedOptional(lhs.reportedDurationSeconds, rhs.reportedDurationSeconds, sortAscending: sortAscending)
        case .tokens:
            ordered(lhs.tokens.total, rhs.tokens.total, sortAscending: sortAscending)
        case .cached:
            ordered(lhs.tokens.cachedInput, rhs.tokens.cachedInput, sortAscending: sortAscending)
        case .uncached:
            ordered(lhs.uncachedInputTokens, rhs.uncachedInputTokens, sortAscending: sortAscending)
        case .output:
            ordered(lhs.tokens.output, rhs.tokens.output, sortAscending: sortAscending)
        case .reasoning:
            ordered(lhs.tokens.reasoningOutput, rhs.tokens.reasoningOutput, sortAscending: sortAscending)
        }
    }

    private static func threadOrder(_ lhs: AuditThreadRow, _ rhs: AuditThreadRow, sortColumn: AuditSortColumn, sortAscending: Bool) -> Bool? {
        switch sortColumn {
        case .time:
            ordered(lhs.latest, rhs.latest, sortAscending: sortAscending)
        case .thread:
            ordered(lhs.title, rhs.title, sortAscending: sortAscending)
        case .duration:
            orderedOptional(
                lhs.reportedDurationMilliseconds,
                rhs.reportedDurationMilliseconds,
                sortAscending: sortAscending
            )
        case .tps:
            orderedOptional(lhs.tokensPerSecond, rhs.tokensPerSecond, sortAscending: sortAscending)
        case .firstToken:
            orderedOptional(
                lhs.averageTimeToFirstTokenMilliseconds,
                rhs.averageTimeToFirstTokenMilliseconds,
                sortAscending: sortAscending
            )
        case .model:
            ordered(lhs.models.first ?? "", rhs.models.first ?? "", sortAscending: sortAscending)
        case .effort:
            ordered(lhs.reasoningEfforts.first ?? "", rhs.reasoningEfforts.first ?? "", sortAscending: sortAscending)
        case .tokens:
            ordered(lhs.tokens.total, rhs.tokens.total, sortAscending: sortAscending)
        case .cached:
            ordered(lhs.tokens.cachedInput, rhs.tokens.cachedInput, sortAscending: sortAscending)
        case .uncached:
            ordered(max(0, lhs.tokens.input - lhs.tokens.cachedInput), max(0, rhs.tokens.input - rhs.tokens.cachedInput), sortAscending: sortAscending)
        case .output:
            ordered(lhs.tokens.output, rhs.tokens.output, sortAscending: sortAscending)
        case .reasoning:
            ordered(lhs.tokens.reasoningOutput, rhs.tokens.reasoningOutput, sortAscending: sortAscending)
        }
    }

    private static func ordered<T: Comparable>(_ lhs: T, _ rhs: T, sortAscending: Bool) -> Bool? {
        guard lhs != rhs else { return nil }
        return sortAscending ? lhs < rhs : lhs > rhs
    }

    private static func orderedOptional<T: Comparable>(
        _ lhs: T?,
        _ rhs: T?,
        sortAscending: Bool
    ) -> Bool? {
        switch (lhs, rhs) {
        case let (.some(lhs), .some(rhs)):
            ordered(lhs, rhs, sortAscending: sortAscending)
        case (.some, .none):
            true
        case (.none, .some):
            false
        case (.none, .none):
            nil
        }
    }

    private static func totalCost(_ calls: [UsagePoint]) -> Decimal? {
        let costs = calls.compactMap(\.estimatedCostUSD)
        return costs.isEmpty ? nil : costs.reduce(Decimal(0), +)
    }

    private static func totalTaskCost(_ tasks: [AgentTask]) -> Decimal? {
        let costs = tasks.compactMap(\.estimatedCostUSD)
        return costs.isEmpty ? nil : costs.reduce(Decimal(0), +)
    }

    private static func durationSeconds(calls: [UsagePoint]) -> Int {
        guard let first = calls.map(\.date).min(), let last = calls.map(\.date).max() else { return 0 }
        return max(0, Int(last.timeIntervalSince(first)))
    }

    private static func durationText(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}

private enum AuditUsageTab: String, CaseIterable, Identifiable {
    case threads
    case tasks

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.tasks, .chinese): "任务"
        case (.threads, .chinese): "线程"
        case (.tasks, _): "Tasks"
        case (.threads, _): "Threads"
        }
    }
}

enum AuditSortColumn {
    case time
    case thread
    case duration
    case model
    case effort
    case tps
    case firstToken
    case tokens
    case cached
    case uncached
    case output
    case reasoning

    var defaultAscending: Bool {
        switch self {
        case .thread, .model, .effort, .firstToken, .duration:
            true
        case .time, .tps, .tokens, .cached, .uncached, .output, .reasoning:
            false
        }
    }
}

struct AuditThreadRow: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var projectName: String
    var latest: Date
    var durationSeconds: Int
    var duration: String
    var tokens: TokenTotals
    var cost: Decimal?
    var calls: [UsagePoint]
    var tasks: [AgentTask]
    var models: [String]
    var reasoningEfforts: [String]
    var reportedDurationMilliseconds: Double?
    var averageTimeToFirstTokenMilliseconds: Double?
    var tokensPerSecond: Double?
}
