import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AuditView: View {
    @ObservedObject var store: UsageStore
    var points: [UsagePoint]
    var dataSourceHealth: DataSourceHealthSummary
    var theme: AppThemeColor

    @State private var exportStatus: String?

    private var rangePoints: [UsagePoint] {
        UsageAuditReporter.filteredPoints(
            points: points,
            range: store.selectedRange,
            customStart: store.customStart,
            customEnd: store.customEnd
        )
    }

    private var composition: TokenComposition {
        UsageAuditReporter.tokenComposition(points: rangePoints)
    }

    private var report: AuditReport {
        UsageAuditReporter.makeReport(
            points: points,
            range: store.selectedRange,
            budgetStatus: budgetStatusForReport,
            dataSourceHealth: dataSourceHealth,
            language: store.language,
            customStart: store.customStart,
            customEnd: store.customEnd
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            compositionGrid

            HStack(alignment: .top, spacing: 14) {
                auditPanel(title: localized("service_breakdown")) {
                    breakdownRows(UsageAuditReporter.serviceRows(points: rangePoints))
                }
                auditPanel(title: localized("model_breakdown")) {
                    breakdownRows(UsageAuditReporter.modelRows(points: rangePoints))
                }
            }

            HStack(alignment: .top, spacing: 14) {
                auditPanel(title: localized("spike_explanation")) {
                    spikeExplanation
                }
                auditPanel(title: localized("report")) {
                    reportPanel
                }
            }

            auditPanel(title: localized("export_records")) {
                exportPanel
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L.text("audit", store.language))
                    .font(.system(size: 20, weight: .bold))
                Text(localized("subtitle"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(rangePoints.count) \(localized("records"))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.primary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var compositionGrid: some View {
        GeometryReader { proxy in
            LazyVGrid(columns: columns(for: proxy.size.width), spacing: 12) {
                metricCard(localized("total"), DisplayFormatters.compactTokenString(composition.total, language: store.language), accent: theme.primary)
                metricCard(localized("input"), DisplayFormatters.compactTokenString(composition.input, language: store.language), accent: theme.tertiary)
                metricCard(localized("cached"), DisplayFormatters.compactTokenString(composition.cachedInput, language: store.language), accent: theme.secondary)
                metricCard(localized("output"), DisplayFormatters.compactTokenString(composition.output, language: store.language), accent: theme.primary)
                metricCard(localized("reasoning"), DisplayFormatters.compactTokenString(composition.reasoningOutput, language: store.language), accent: .orange)
            }
        }
        .frame(height: 176)
    }

    private func columns(for width: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: width < 840 ? 3 : 5)
    }

    private func metricCard(_ title: String, _ value: String, accent: Color) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(accent.opacity(0.10))
                .frame(width: 108, height: 108)
                .offset(x: 30, y: 32)
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: iconName(for: title))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 38, height: 38)
                    .background(accent.opacity(0.10), in: Circle())
                Spacer()
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                Text(value)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 164, alignment: .leading)
        .background(
            LinearGradient(colors: [Color.white.opacity(0.84), accent.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .agentBarPanel(cornerRadius: 16)
    }

    private func iconName(for title: String) -> String {
        switch title {
        case localized("input"): return "mic"
        case localized("cached"): return "internaldrive"
        case localized("output"): return "arrow.up"
        case localized("reasoning"): return "bolt"
        default: return "cylinder.split.1x2"
        }
    }

    @ViewBuilder
    private func breakdownRows(_ rows: [AuditBreakdownRow]) -> some View {
        if rows.isEmpty {
            EmptyAuditMessage(text: L.text("no_usage_data", store.language))
        } else {
            VStack(spacing: 12) {
                ForEach(rows.prefix(8)) { row in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(row.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(DisplayFormatters.compactTokenString(row.tokens, language: store.language))
                                .font(.system(size: 13, weight: .bold))
                                .monospacedDigit()
                        }
                        ProgressView(value: row.share)
                            .tint(theme.primary)
                    }
                }
            }
        }
    }

    private var spikeExplanation: some View {
        let anomalies = UsageInsights.usageAnomalies(points: points).prefix(4)
        return VStack(alignment: .leading, spacing: 10) {
            if anomalies.isEmpty {
                EmptyAuditMessage(text: localized("no_spikes"))
            } else {
                ForEach(Array(anomalies), id: \.id) { anomaly in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(anomaly.label)
                                .font(.system(size: 13, weight: .bold))
                            Text("\(DisplayFormatters.compactTokenString(anomaly.tokens, language: store.language)) \(L.text("tokens", store.language)) · \(String(format: "%.1fx", anomaly.multiple)) \(localized("baseline"))")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                Text(localized("local_basis"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private var reportPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(report.body)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.86))
                .textSelection(.enabled)
                .lineSpacing(3)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report.body, forType: .string)
                exportStatus = localized("report_copied")
            } label: {
                Label(localized("copy_report"), systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .pointingHandCursor()
        }
    }

    private var exportPanel: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localized("export_detail"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                if let exportStatus {
                    Text(exportStatus)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.primary)
                }
            }
            Spacer()
            Button {
                export(format: .csv)
            } label: {
                Label("CSV", systemImage: "tablecells")
            }
            .buttonStyle(.bordered)
            .pointingHandCursor()

            Button {
                export(format: .json)
            } label: {
                Label("JSON", systemImage: "curlybraces")
            }
            .buttonStyle(.bordered)
            .pointingHandCursor()
        }
    }

    private func auditPanel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .agentBarPanel(cornerRadius: 16)
    }

    private var budgetStatusForReport: BudgetStatus? {
        switch store.selectedRange {
        case .today:
            return store.budgetStatus(for: .today)
        case .thisWeek, .last7Days:
            return store.budgetStatus(for: .thisWeek)
        case .yesterday, .thisMonth, .thisYear, .last30Days, .all, .custom:
            return nil
        }
    }

    private func export(format: UsageExportFormat) {
        let rows = UsageAuditReporter.exportRows(
            points: points,
            range: store.selectedRange,
            customStart: store.customStart,
            customEnd: store.customEnd
        )
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "AgentBar-\(store.selectedRange.rawValue)-usage.\(format.fileExtension)"
        panel.allowedContentTypes = format == .csv ? [.commaSeparatedText] : [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let text = UsageAuditReporter.serialize(rows: rows, format: format)
            try text.write(to: url, atomically: true, encoding: .utf8)
            exportStatus = "\(localized("exported")) \(url.lastPathComponent)"
        } catch {
            exportStatus = "\(localized("export_failed")) \(error.localizedDescription)"
        }
    }

    private func localized(_ key: String) -> String {
        switch (key, store.language) {
        case ("subtitle", .chinese): "解释 Token 去向、异常增长，并导出安全的解析记录。"
        case ("records", .chinese): "条记录"
        case ("service_breakdown", .chinese): "按服务"
        case ("model_breakdown", .chinese): "按模型"
        case ("spike_explanation", .chinese): "异常解释"
        case ("report", .chinese): "报告"
        case ("export_records", .chinese): "导出记录"
        case ("total", .chinese): "总量"
        case ("input", .chinese): "输入"
        case ("cached", .chinese): "缓存输入"
        case ("output", .chinese): "输出"
        case ("reasoning", .chinese): "推理输出"
        case ("no_spikes", .chinese): "当前没有检测到明显异常增长。"
        case ("baseline", .chinese): "高于基线"
        case ("local_basis", .chinese): "基于本地已解析 session logs，不代表官方账单。"
        case ("copy_report", .chinese): "复制报告"
        case ("report_copied", .chinese): "报告已复制。"
        case ("export_detail", .chinese): "导出当前服务筛选和时间范围内的解析记录，不包含原始 JSONL。"
        case ("exported", .chinese): "已导出"
        case ("export_failed", .chinese): "导出失败："
        case ("subtitle", _): "Explain token usage, spikes, and export safe parsed records."
        case ("records", _): "records"
        case ("service_breakdown", _): "By service"
        case ("model_breakdown", _): "By model"
        case ("spike_explanation", _): "Spike explanation"
        case ("report", _): "Report"
        case ("export_records", _): "Export records"
        case ("total", _): "Total"
        case ("input", _): "Input"
        case ("cached", _): "Cached input"
        case ("output", _): "Output"
        case ("reasoning", _): "Reasoning"
        case ("no_spikes", _): "No obvious usage spikes detected for this data set."
        case ("baseline", _): "over baseline"
        case ("local_basis", _): "Based on local parsed session logs, not official billing records."
        case ("copy_report", _): "Copy report"
        case ("report_copied", _): "Report copied."
        case ("export_detail", _): "Exports parsed records for the current service filter and time range, without raw JSONL lines."
        case ("exported", _): "Exported"
        case ("export_failed", _): "Export failed:"
        default: key
        }
    }
}

private struct EmptyAuditMessage: View {
    var text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.blue.opacity(0.36))
                .frame(width: 86, height: 70)
                .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .center)
    }
}
