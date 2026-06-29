import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AuditView: View {
    @ObservedObject var store: UsageStore
    var points: [UsagePoint]
    var dataSourceHealth: DataSourceHealthSummary
    var theme: AppThemeColor

    @State private var selectedTab: AuditUsageTab = .threads
    @State private var selectedCallID: String?
    @State private var expandedThreadID: String?
    @State private var exportStatus: String?
    @State private var callsPage = 0
    @State private var threadsPage = 0
    @State private var kpiGridWidth: CGFloat = 980

    private let pageSize = 20
    nonisolated private static let kpiCardCount = 6
    nonisolated private static let kpiCardHeight: CGFloat = 96
    nonisolated private static let kpiGridSpacing: CGFloat = 12

    private var rangePoints: [UsagePoint] {
        UsageAuditReporter.filteredPoints(
            points: points.filter { $0.service == .codex },
            range: store.selectedRange,
            customStart: store.customStart,
            customEnd: store.customEnd
        )
        .sorted { $0.date > $1.date }
    }

    private var threadRows: [AuditThreadRow] {
        Dictionary(grouping: rangePoints) { point in
            point.sessionTitle ?? point.sessionID ?? "Unknown thread"
        }
        .map { title, calls in
            let sorted = calls.sorted { $0.date > $1.date }
            let totals = calls.reduce(TokenTotals.zero) { $0 + $1.tokens }
            return AuditThreadRow(
                id: title,
                title: title,
                subtitle: "\(calls.count) calls · \(sorted.first?.projectName ?? "Unknown project")",
                latest: sorted.first?.date ?? .distantPast,
                duration: durationText(calls: calls),
                tokens: totals,
                cost: totalCost(calls),
                calls: sorted
            )
        }
        .sorted { lhs, rhs in
            if lhs.tokens.total != rhs.tokens.total { return lhs.tokens.total > rhs.tokens.total }
            return lhs.latest > rhs.latest
        }
    }

    private var composition: TokenComposition {
        UsageAuditReporter.tokenComposition(points: rangePoints)
    }

    private var pagedCalls: [UsagePoint] {
        page(rangePoints, index: clampedPage(callsPage, total: rangePoints.count))
    }

    private var pagedThreads: [AuditThreadRow] {
        page(threadRows, index: clampedPage(threadsPage, total: threadRows.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            kpiGrid
            tablePanel
            exportPanel
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            selectedCallID = selectedCallID ?? rangePoints.first?.callID
        }
        .onChange(of: rangePoints.map(\.callID)) { _, ids in
            callsPage = clampedPage(callsPage, total: ids.count)
            threadsPage = clampedPage(threadsPage, total: threadRows.count)
            guard let selectedCallID, ids.contains(selectedCallID) else {
                self.selectedCallID = ids.first
                return
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(localized("title"))
                    .font(.system(size: 20, weight: .bold))
                Text(localized("subtitle"))
                    .font(.system(size: 12, weight: .semibold))
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
            statusPill
        }
    }

    private var statusPill: some View {
        Text("\(rangePoints.count) \(localized("calls")) · JSONL")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(theme.primary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var kpiGrid: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.kpiGridSpacing), count: Self.kpiGridColumns(for: width)), spacing: Self.kpiGridSpacing) {
                metricCard(localized("visible_calls"), "\(rangePoints.count)")
                metricCard(localized("total_tokens"), DisplayFormatters.compactTokenString(composition.total, language: store.language))
                metricCard(localized("cached_input"), DisplayFormatters.compactTokenString(composition.cachedInput, language: store.language))
                metricCard(localized("uncached_input"), DisplayFormatters.compactTokenString(max(0, composition.input - composition.cachedInput), language: store.language))
                metricCard(localized("reasoning_output"), DisplayFormatters.compactTokenString(composition.reasoningOutput, language: store.language))
                metricCard(localized("estimated_cost"), costText(totalCost(rangePoints)))
            }
            .onAppear { kpiGridWidth = width }
            .onChange(of: width) { _, width in
                kpiGridWidth = width
            }
        }
        .frame(height: Self.kpiGridHeight(for: kpiGridWidth))
    }

    nonisolated static func kpiGridColumns(for width: CGFloat) -> Int {
        width < 980 ? 3 : 6
    }

    nonisolated static func kpiGridHeight(for width: CGFloat) -> CGFloat {
        let columns = kpiGridColumns(for: width)
        let rows = CGFloat((kpiCardCount + columns - 1) / columns)
        return rows * kpiCardHeight + max(0, rows - 1) * kpiGridSpacing
    }

    private func metricCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: Self.kpiCardHeight, alignment: .topLeading)
        .agentBarPanel(cornerRadius: 12)
    }

    private var tablePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(selectedTab == .calls ? localized("model_calls") : localized("threads"))
                    .font(.system(size: 16, weight: .bold))
                Picker("", selection: $selectedTab) {
                    ForEach(AuditUsageTab.allCases) { tab in
                        Text(tab.title(language: store.language)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                Spacer()
                Button {
                    export(format: .csv)
                } label: {
                    Label("CSV", systemImage: "tablecells")
                }
                .buttonStyle(.bordered)
                .pointingHandCursor()
            }
            .padding(16)

            Divider()

            Text(selectedTab == .calls ? localized("calls_caption") : localized("threads_caption"))
                .font(.system(size: 12, weight: .semibold))
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
                    callsTable
                } else {
                    threadsTable
                }
            }
        }
        .agentBarPanel(cornerRadius: 14)
    }

    private var tableHeader: some View {
        HStack(spacing: 8) {
            column(localized("time"), width: 108, alignment: .leading)
            threadColumn(localized("thread"), strong: true)
            column(localized("duration"), width: 60)
            column(localized("initiated"), width: 58)
            column(localized("model"), width: 76)
            column(localized("effort"), width: 50)
            column(localized("tokens"), width: 68)
            column(localized("cached"), width: 68)
            column(localized("uncached"), width: 68)
            column(localized("output"), width: 58)
            column(localized("reasoning"), width: 58)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.secondary)
    }

    private var callsTable: some View {
        VStack(spacing: 0) {
            ForEach(pagedCalls) { point in
                callRow(point, nested: false)
                if selectedCallID == point.callID {
                    callDetail(point: point)
                }
                Divider()
            }
            paginationFooter(total: rangePoints.count, page: $callsPage, itemName: localized("calls"))
        }
    }

    private var threadsTable: some View {
        VStack(spacing: 0) {
            ForEach(pagedThreads) { thread in
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
            paginationFooter(total: threadRows.count, page: $threadsPage, itemName: localized("threads"))
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
                column(point.initiator ?? "Codex", width: 58)
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
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(2)
                        Text(thread.subtitle)
                            .font(.system(size: 11, weight: .medium))
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
            .font(.system(size: 12, weight: strong ? .bold : .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.62)
            .padding(.horizontal, pill ? 8 : 0)
            .frame(width: width, alignment: alignment)
            .foregroundStyle(pill ? theme.primary : .primary.opacity(0.9))
            .background(pill ? theme.primary.opacity(0.10) : Color.clear, in: Capsule())
    }

    private func threadColumn(_ text: String, strong: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 12, weight: strong ? .bold : .semibold))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.primary.opacity(0.9))
    }

    private func callDetail(point: UsagePoint) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localized("call_investigator"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(point.sessionTitle ?? point.sessionID ?? localized("unknown_thread"))
                        .font(.system(size: 16, weight: .bold))
                    Text("\(dateText(point.date)) · \(point.model) · \(point.reasoningEffort ?? "-")")
                        .font(.system(size: 12, weight: .semibold))
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
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.68)
                .textSelection(.enabled)
            Text(subtitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var exportPanel: some View {
        HStack(spacing: 10) {
            Text(localized("privacy_note"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let exportStatus {
                Text(exportStatus)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.primary)
            }
            Button {
                export(format: .json)
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
            .font(.system(size: 11, weight: .bold))
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
                .font(.system(size: 11, weight: .bold))
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

    private func export(format: UsageExportFormat) {
        let rows = UsageAuditReporter.exportRows(
            points: rangePoints,
            range: .all
        )
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "AgentBar-codex-usage.\(format.fileExtension)"
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
        let formatter = DateFormatter()
        formatter.locale = store.language == .chinese ? Locale(identifier: "zh_Hans") : Locale(identifier: "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func costText(_ value: Decimal?) -> String {
        guard let value else { return "-" }
        return "$\(NSDecimalNumber(decimal: value).stringValue)"
    }

    private func totalCost(_ calls: [UsagePoint]) -> Decimal? {
        let costs = calls.compactMap(\.estimatedCostUSD)
        return costs.isEmpty ? nil : costs.reduce(Decimal(0), +)
    }

    private func durationText(calls: [UsagePoint]) -> String {
        guard let first = calls.map(\.date).min(), let last = calls.map(\.date).max() else { return "-" }
        let seconds = max(0, Int(last.timeIntervalSince(first)))
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    private func localized(_ key: String) -> String {
        L.text(key, store.language)
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

private struct AuditThreadRow: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var latest: Date
    var duration: String
    var tokens: TokenTotals
    var cost: Decimal?
    var calls: [UsagePoint]
}
