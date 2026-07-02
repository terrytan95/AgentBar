import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AuditView: View {
    @ObservedObject var store: UsageStore
    var points: [UsagePoint]
    var selectedSessionLabel: String?
    var dataSourceHealth: DataSourceHealthSummary
    var theme: AppThemeColor
    var onClearSessionSelection: () -> Void = {}

    @State private var selectedTab: AuditUsageTab = .threads
    @State private var selectedCallID: String?
    @State private var expandedThreadID: String?
    @State private var exportStatus: String?
    @State private var callsPage = 0
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
        .onChange(of: preparedSnapshot.callIDs) { _, ids in
            callsPage = clampedPage(callsPage, total: ids.count)
            threadsPage = clampedPage(threadsPage, total: preparedSnapshot.threadRows.count)
            guard let selectedCallID, ids.contains(selectedCallID) else {
                self.selectedCallID = ids.first
                return
            }
        }
    }

    private func header(_ snapshot: AuditUsageSnapshot) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(localized("title"))
                    .font(.agentBar(size: 20, weight: .bold))
                Text(localized("subtitle"))
                    .font(.agentBar(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.refresh(force: true, showManualFeedback: true)
            } label: {
                Label(L.text("refresh", store.language), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .pointingHandCursor()
            statusPill(snapshot)
        }
    }

    private func statusPill(_ snapshot: AuditUsageSnapshot) -> some View {
        Text("\(snapshot.rangePoints.count) \(localized("calls")) · JSONL")
            .font(.agentBar(size: 12, weight: .bold))
            .foregroundStyle(theme.primary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var codexSessionScanNote: String? {
        guard let note = dataSourceHealth.rows.first(where: { $0.service == .codex })?.note,
              note.hasPrefix("Codex session scan skipped")
        else { return nil }
        return note
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
                metricCard(localized("visible_calls"), "\(snapshot.rangePoints.count)")
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
                Text(selectedTab == .calls ? localized("model_calls") : localized("threads"))
                    .font(.agentBar(size: 16, weight: .bold))
                Picker("", selection: $selectedTab) {
                    ForEach(AuditUsageTab.allCases) { tab in
                        Text(tab.title(language: store.language)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                if let selectedSessionLabel {
                    Button {
                        onClearSessionSelection()
                    } label: {
                        Label("\(localized("session_drilldown")): \(selectedSessionLabel)", systemImage: "xmark.circle.fill")
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .help(localized("clear_drilldown"))
                    .pointingHandCursor()
                }
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

            Text(selectedTab == .calls ? localized("calls_caption") : localized("threads_caption"))
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

                if selectedTab == .calls {
                    callsTable(snapshot)
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
            sortHeader(.duration, localized("duration"), width: 60)
            sortHeader(.initiated, localized("initiated"), width: 58)
            sortHeader(.model, localized("model"), width: 76)
            sortHeader(.effort, localized("effort"), width: 50)
            sortHeader(.tokens, localized("tokens"), width: 68)
            sortHeader(.cached, localized("cached"), width: 68)
            sortHeader(.uncached, localized("uncached"), width: 68)
            sortHeader(.output, localized("output"), width: 58)
            sortHeader(.reasoning, localized("reasoning"), width: 58)
        }
        .font(.agentBar(size: 11, weight: .bold))
        .foregroundStyle(.secondary)
    }

    private func callsTable(_ snapshot: AuditUsageSnapshot) -> some View {
        VStack(spacing: 0) {
            ForEach(page(snapshot.sortedCalls, index: clampedPage(callsPage, total: snapshot.rangePoints.count))) { point in
                callRow(point, nested: false)
                if selectedCallID == point.callID {
                    callDetail(point: point)
                }
                Divider()
            }
            paginationFooter(total: snapshot.rangePoints.count, page: $callsPage, itemName: localized("calls"))
        }
    }

    private func threadsTable(_ snapshot: AuditUsageSnapshot) -> some View {
        VStack(spacing: 0) {
            ForEach(page(snapshot.threadRows, index: clampedPage(threadsPage, total: snapshot.threadRows.count))) { thread in
                threadRow(thread)
                if expandedThreadID == thread.id {
                    ForEach(thread.calls.prefix(20)) { point in
                        callRow(point, nested: true)
                        if selectedCallID == point.callID {
                            callDetail(point: point)
                        }
                    }
                }
                Divider()
            }
            paginationFooter(total: snapshot.threadRows.count, page: $threadsPage, itemName: localized("threads"))
        }
    }

    private func callRow(_ point: UsagePoint, nested: Bool) -> some View {
        Button {
            selectedCallID = point.callID
        } label: {
            HStack(spacing: 8) {
                column(dateText(point.date), width: 108, alignment: .leading)
                threadColumn((nested ? "  " : "") + (point.sessionTitle ?? point.sessionID ?? localized("unknown_thread")), strong: true)
                column("1", width: 60)
                column(point.initiator ?? point.service.rawValue, width: 58)
                column(point.model, width: 76, pill: true)
                column(point.reasoningEffort ?? "-", width: 50)
                column(DisplayFormatters.compactTokenString(point.tokens.total, language: store.language), width: 68)
                column(DisplayFormatters.compactTokenString(point.tokens.cachedInput, language: store.language), width: 68)
                column(DisplayFormatters.compactTokenString(point.uncachedInputTokens, language: store.language), width: 68)
                column(DisplayFormatters.compactTokenString(point.tokens.output, language: store.language), width: 58)
                column(DisplayFormatters.compactTokenString(point.tokens.reasoningOutput, language: store.language), width: 58)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, nested ? 8 : 11)
            .background(selectedCallID == point.callID ? theme.primary.opacity(0.10) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func threadRow(_ thread: AuditThreadRow) -> some View {
        Button {
            expandedThreadID = expandedThreadID == thread.id ? nil : thread.id
            selectedCallID = thread.calls.first?.callID
        } label: {
            HStack(spacing: 8) {
                column(dateText(thread.latest), width: 108, alignment: .leading)
                HStack(spacing: 8) {
                    Image(systemName: expandedThreadID == thread.id ? "minus.circle.fill" : "plus.circle.fill")
                        .foregroundStyle(theme.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(thread.title)
                            .font(.agentBar(size: 12, weight: .bold))
                            .lineLimit(2)
                        Text(thread.subtitle)
                            .font(.agentBar(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                column(thread.duration, width: 60)
                column("\(thread.calls.count)", width: 58)
                column(thread.calls.first?.model ?? "-", width: 76, pill: true)
                column(thread.calls.first?.reasoningEffort ?? "-", width: 50)
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
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func column(_ text: String, width: CGFloat? = nil, alignment: Alignment = .trailing, strong: Bool = false, pill: Bool = false) -> some View {
        Text(text)
            .font(.agentBar(size: 12, weight: strong ? .bold : .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.62)
            .padding(.horizontal, pill ? 8 : 0)
            .frame(width: width, alignment: alignment)
            .foregroundStyle(pill ? theme.primary : .primary.opacity(0.9))
            .background(pill ? theme.primary.opacity(0.10) : Color.clear, in: Capsule())
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
        .buttonStyle(.plain)
        .pointingHandCursor()
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
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func callDetail(point: UsagePoint) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localized("call_investigator"))
                        .font(.agentBar(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(point.sessionTitle ?? point.sessionID ?? localized("unknown_thread"))
                        .font(.agentBar(size: 16, weight: .bold))
                    Text("\(dateText(point.date)) · \(point.model) · \(point.reasoningEffort ?? "-")")
                        .font(.agentBar(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let sourceFile = point.sourceFile {
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
                detailCard(localized("last_call_input"), DisplayFormatters.tokenString(point.tokens.input), localized("exact_from_callback"))
                detailCard(localized("cached_input"), DisplayFormatters.tokenString(point.tokens.cachedInput), "\(Int(point.cacheRatio * 100))%")
                detailCard(localized("uncached_input"), DisplayFormatters.tokenString(point.uncachedInputTokens), localized("fresh_context"))
                detailCard(localized("output"), DisplayFormatters.tokenString(point.tokens.output), localized("assistant_output"))
                detailCard(localized("reasoning_output"), DisplayFormatters.tokenString(point.tokens.reasoningOutput), localized("reasoning"))
                detailCard(localized("estimated_cost"), costText(point.estimatedCostUSD), localized("configured_price"))
                detailCard(localized("source_line"), sourceLineText(point), localized("source_file_line"))
                detailCard("Cwd", point.cwd ?? "-", point.projectName ?? "-")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.primary.opacity(0.06))
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
                    .foregroundStyle(theme.primary)
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
        callsPage = 0
        threadsPage = 0
    }

    private func applySessionSelection(to snapshot: AuditUsageSnapshot) {
        selectedCallID = selectedCallID ?? snapshot.callIDs.first
        guard selectedSessionLabel != nil else { return }
        selectedTab = .threads
        callsPage = 0
        threadsPage = 0
        expandedThreadID = snapshot.threadRows.first?.id
        selectedCallID = snapshot.threadRows.first?.calls.first?.callID ?? snapshot.callIDs.first
    }

    private func export(format: UsageExportFormat, snapshot: AuditUsageSnapshot) {
        let rows = UsageAuditReporter.exportRows(
            points: snapshot.rangePoints,
            range: .all
        )
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "AgentBar-usage.\(format.rawValue)"
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

    private func sourceLineText(_ point: UsagePoint) -> String {
        guard let sourceFile = point.sourceFile else { return "-" }
        if let sourceLine = point.sourceLine {
            return "\(sourceFile):\(sourceLine)"
        }
        return sourceFile
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
    var sortedCalls: [UsagePoint]
    var threadRows: [AuditThreadRow]
    var composition: TokenTotals
    var totalCost: Decimal?
    var callIDs: [String]

    static func make(
        points: [UsagePoint],
        range: UsageRange,
        customStart: Date?,
        customEnd: Date?,
        selectedSessionLabel: String? = nil,
        sortColumn: AuditSortColumn,
        sortAscending: Bool
    ) -> AuditUsageSnapshot {
        let rangePoints = UsageRangeProjection.filteredPoints(
            points: points,
            range: range,
            customStart: customStart,
            customEnd: customEnd
        )
        .filter { point in
            guard let selectedSessionLabel else { return true }
            return sessionLabel(for: point) == selectedSessionLabel
        }
        .sorted { $0.date > $1.date }
        let threadRows = sortedThreads(
            makeThreadRows(rangePoints),
            sortColumn: sortColumn,
            sortAscending: sortAscending
        )

        return AuditUsageSnapshot(
            rangePoints: rangePoints,
            sortedCalls: sortedCalls(rangePoints, sortColumn: sortColumn, sortAscending: sortAscending),
            threadRows: threadRows,
            composition: UsageAuditReporter.tokenComposition(points: rangePoints),
            totalCost: totalCost(rangePoints),
            callIDs: rangePoints.map(\.callID)
        )
    }

    private static func sessionLabel(for point: UsagePoint) -> String {
        point.sessionTitle ?? point.sessionID ?? "Unknown session"
    }

    private static func makeThreadRows(_ points: [UsagePoint]) -> [AuditThreadRow] {
        Dictionary(grouping: points) { point in
            sessionLabel(for: point)
        }
        .map { title, calls in
            let sorted = calls.sorted { $0.date > $1.date }
            let totals = calls.reduce(TokenTotals.zero) { $0 + $1.tokens }
            let durationSeconds = durationSeconds(calls: calls)
            return AuditThreadRow(
                id: title,
                title: title,
                subtitle: "\(calls.count) calls · \(sorted.first?.projectName ?? "Unknown project")",
                latest: sorted.first?.date ?? .distantPast,
                durationSeconds: durationSeconds,
                duration: durationText(seconds: durationSeconds),
                tokens: totals,
                cost: totalCost(calls),
                calls: sorted
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
        case .initiated:
            ordered(lhs.initiator ?? lhs.service.rawValue, rhs.initiator ?? rhs.service.rawValue, sortAscending: sortAscending)
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

    private static func threadOrder(_ lhs: AuditThreadRow, _ rhs: AuditThreadRow, sortColumn: AuditSortColumn, sortAscending: Bool) -> Bool? {
        switch sortColumn {
        case .time:
            ordered(lhs.latest, rhs.latest, sortAscending: sortAscending)
        case .thread:
            ordered(lhs.title, rhs.title, sortAscending: sortAscending)
        case .duration:
            ordered(lhs.durationSeconds, rhs.durationSeconds, sortAscending: sortAscending)
        case .initiated:
            ordered(lhs.calls.first?.initiator ?? lhs.calls.first?.service.rawValue ?? "", rhs.calls.first?.initiator ?? rhs.calls.first?.service.rawValue ?? "", sortAscending: sortAscending)
        case .model:
            ordered(lhs.calls.first?.model ?? "", rhs.calls.first?.model ?? "", sortAscending: sortAscending)
        case .effort:
            ordered(lhs.calls.first?.reasoningEffort ?? "", rhs.calls.first?.reasoningEffort ?? "", sortAscending: sortAscending)
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

    private static func totalCost(_ calls: [UsagePoint]) -> Decimal? {
        let costs = calls.compactMap(\.estimatedCostUSD)
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
    case calls

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.calls, .chinese): "调用"
        case (.threads, .chinese): "线程"
        case (.calls, _): "Calls"
        case (.threads, _): "Threads"
        }
    }
}

enum AuditSortColumn {
    case time
    case thread
    case duration
    case initiated
    case model
    case effort
    case tokens
    case cached
    case uncached
    case output
    case reasoning

    var defaultAscending: Bool {
        switch self {
        case .thread, .initiated, .model, .effort:
            true
        case .time, .duration, .tokens, .cached, .uncached, .output, .reasoning:
            false
        }
    }
}

struct AuditThreadRow: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var latest: Date
    var durationSeconds: Int
    var duration: String
    var tokens: TokenTotals
    var cost: Decimal?
    var calls: [UsagePoint]
}
