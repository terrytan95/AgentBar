import AppKit
import SwiftUI

struct GuardianView: View {
    @ObservedObject var store: UsageStore
    var dataSourceHealth: DataSourceHealthSummary
    var theme: AppThemeColor

    @State private var snapshot: SystemGuardianSnapshot?
    @State private var isRefreshing = false
    @State private var statusMessage: String?

    private var recommendations: [GuardianRecommendation] {
        snapshot.map(GuardianRecommendationEngine.recommendations) ?? []
    }

    private var overallSeverity: InsightSeverity {
        snapshot.map(GuardianRecommendationEngine.overallSeverity) ?? .ok
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            summaryGrid

            HStack(alignment: .top, spacing: 14) {
                guardianPanel(title: localized("processes")) {
                    processPanel
                }
                guardianPanel(title: localized("session_store")) {
                    sessionPanel
                }
            }

            HStack(alignment: .top, spacing: 14) {
                guardianPanel(title: localized("data_sources")) {
                    dataSourcePanel
                }
                guardianPanel(title: localized("recommendations")) {
                    recommendationsPanel
                }
            }

            guardianPanel(title: localized("safe_actions")) {
                safeActionsPanel
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            if snapshot == nil {
                refreshSnapshot()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Guardian")
                    .font(.system(size: 20, weight: .bold))
                Text(localized("subtitle"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                refreshSnapshot()
            } label: {
                Label(L.text("refresh", store.language), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshing)
            .pointingHandCursor(enabled: !isRefreshing)
        }
    }

    private var summaryGrid: some View {
        GeometryReader { proxy in
            LazyVGrid(columns: columns(for: proxy.size.width), spacing: 12) {
                summaryCard(localized("overall"), severityText(overallSeverity), color: severityColor(overallSeverity))
                summaryCard(localized("agent_processes"), "\(snapshot?.processes.count ?? 0)", color: theme.primary)
                summaryCard(localized("session_size"), snapshot.map { SessionStoreHealth.byteCount($0.sessionStore.totalBytes) } ?? "--", color: severityColor(snapshot?.sessionStore.severity ?? .ok))
                summaryCard(localized("source_issues"), "\(dataSourceHealth.issueCount)", color: dataSourceHealth.issueCount > 0 ? .orange : theme.primary)
            }
        }
        .frame(height: 82)
    }

    private func columns(for width: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: width < 760 ? 2 : 4)
    }

    private func summaryCard(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .guardianCard()
    }

    @ViewBuilder
    private var processPanel: some View {
        if isRefreshing && snapshot == nil {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 100)
        } else if let processes = snapshot?.processes, !processes.isEmpty {
            VStack(spacing: 0) {
                ForEach(processes.prefix(10)) { process in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(process.name)
                                .font(.system(size: 13, weight: .bold))
                            Text("PID \(process.pid)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(cpuText(process.cpuPercent))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(severityColor(process.severity))
                                .monospacedDigit()
                        }
                        Text(process.redactedCommand)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 8)
                    if process.id != processes.prefix(10).last?.id {
                        Divider()
                    }
                }
            }
        } else {
            EmptyGuardianMessage(text: localized("no_processes"))
        }
    }

    @ViewBuilder
    private var sessionPanel: some View {
        if let session = snapshot?.sessionStore {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(severityText(session.severity))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(severityColor(session.severity))
                    Spacer()
                    Text(SessionStoreHealth.byteCount(session.totalBytes))
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                }
                Text(session.summary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                metricLine(localized("jsonl_files"), "\(session.jsonlFileCount)")
                metricLine(localized("recent_files"), "\(session.recentFileCount)")
                metricLine(localized("old_files"), "\(session.oldFileCount)")
                metricLine(localized("large_files"), "\(session.largeFileCount)")
                Text(session.path)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            EmptyGuardianMessage(text: localized("snapshot_pending"))
        }
    }

    private var dataSourcePanel: some View {
        VStack(spacing: 10) {
            if dataSourceHealth.rows.isEmpty {
                EmptyGuardianMessage(text: localized("no_sources"))
            } else {
                ForEach(dataSourceHealth.rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle()
                            .fill(row.status == .live ? theme.primary : .orange)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.service.rawValue)
                                .font(.system(size: 13, weight: .bold))
                            Text(row.note ?? row.status.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text(row.status.label)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(row.status == .live ? theme.primary : .orange)
                    }
                }
            }
        }
    }

    private var recommendationsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(recommendations) { recommendation in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: recommendation.requiresConfirmation ? "exclamationmark.triangle" : "checkmark.shield")
                        .foregroundStyle(severityColor(recommendation.severity))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recommendation.title)
                            .font(.system(size: 13, weight: .bold))
                        Text(recommendation.detail)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }

    private var safeActionsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], alignment: .leading, spacing: 10) {
                Button {
                    store.refresh(force: true, showManualFeedback: true)
                    refreshSnapshot()
                    statusMessage = localized("refreshed")
                } label: {
                    Label(L.text("refresh", store.language), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    store.openLogin(for: .codex)
                } label: {
                    Label("Codex", systemImage: "person.crop.circle.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    store.openLogin(for: .claudeCode)
                } label: {
                    Label("Claude", systemImage: "person.crop.circle.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    openSessionFolder()
                } label: {
                    Label(localized("open_sessions"), systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                } label: {
                    Label(localized("activity_monitor"), systemImage: "waveform.path.ecg")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    copyDiagnostics()
                } label: {
                    Label(localized("copy_diagnostics"), systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.primary)
            }
        }
        .buttonStyle(.bordered)
        .pointingHandCursor()
    }

    private func guardianPanel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .guardianCard()
    }

    private func metricLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
        }
        .font(.system(size: 12, weight: .medium))
    }

    private func refreshSnapshot() {
        isRefreshing = true
        let dataSourceHealth = dataSourceHealth
        DispatchQueue.global(qos: .utility).async {
            let next = SystemGuardianReader().snapshot(dataSourceHealth: dataSourceHealth)
            DispatchQueue.main.async {
                snapshot = next
                isRefreshing = false
            }
        }
    }

    private func openSessionFolder() {
        let path = snapshot?.sessionStore.path ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/sessions").path
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func copyDiagnostics() {
        let text = diagnosticText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusMessage = localized("diagnostics_copied")
    }

    private func diagnosticText() -> String {
        guard let snapshot else { return "AgentBar Guardian: snapshot pending." }
        return [
            "AgentBar Guardian",
            "Captured: \(DisplayFormatters.shortDateTimeString(for: snapshot.capturedAt, language: store.language))",
            "Overall: \(severityText(overallSeverity))",
            "Processes: \(snapshot.processes.count)",
            "Session store: \(snapshot.sessionStore.summary)",
            "Data sources: \(snapshot.dataSourceHealth.liveCount) live, \(snapshot.dataSourceHealth.issueCount) issue(s)",
            "Recommendations:",
            recommendations.map { "- \($0.title): \($0.detail)" }.joined(separator: "\n")
        ].joined(separator: "\n")
    }

    private func cpuText(_ cpu: Double?) -> String {
        guard let cpu else { return "--%" }
        return String(format: "%.1f%% CPU", cpu)
    }

    private func severityText(_ severity: InsightSeverity) -> String {
        switch (severity, store.language) {
        case (.ok, .chinese): "正常"
        case (.warning, .chinese): "注意"
        case (.critical, .chinese): "严重"
        case (.ok, _): "OK"
        case (.warning, _): "Warning"
        case (.critical, _): "Critical"
        }
    }

    private func severityColor(_ severity: InsightSeverity) -> Color {
        switch severity {
        case .ok: theme.primary
        case .warning: .orange
        case .critical: .red
        }
    }

    private func localized(_ key: String) -> String {
        switch (key, store.language) {
        case ("subtitle", .chinese): "检查本机 agent 进程、Codex session、数据源和存储风险。"
        case ("overall", .chinese): "总体"
        case ("agent_processes", .chinese): "Agent 进程"
        case ("session_size", .chinese): "Session 大小"
        case ("source_issues", .chinese): "数据源问题"
        case ("processes", .chinese): "进程"
        case ("session_store", .chinese): "Session 存储"
        case ("data_sources", .chinese): "数据源"
        case ("recommendations", .chinese): "建议"
        case ("safe_actions", .chinese): "安全操作"
        case ("no_processes", .chinese): "未检测到相关 AgentBar/Codex/Claude 进程。"
        case ("snapshot_pending", .chinese): "正在获取系统快照。"
        case ("no_sources", .chinese): "暂无数据源状态。"
        case ("jsonl_files", .chinese): "JSONL 文件"
        case ("recent_files", .chinese): "最近文件"
        case ("old_files", .chinese): "旧文件"
        case ("large_files", .chinese): "大文件"
        case ("open_sessions", .chinese): "打开 Sessions"
        case ("activity_monitor", .chinese): "活动监视器"
        case ("copy_diagnostics", .chinese): "复制诊断"
        case ("refreshed", .chinese): "已刷新。"
        case ("diagnostics_copied", .chinese): "诊断已复制。"
        case ("subtitle", _): "Inspect local agent processes, Codex sessions, data sources, and storage risk."
        case ("overall", _): "Overall"
        case ("agent_processes", _): "Agent processes"
        case ("session_size", _): "Session size"
        case ("source_issues", _): "Source issues"
        case ("processes", _): "Processes"
        case ("session_store", _): "Session store"
        case ("data_sources", _): "Data sources"
        case ("recommendations", _): "Recommendations"
        case ("safe_actions", _): "Safe actions"
        case ("no_processes", _): "No related AgentBar, Codex, or Claude processes detected."
        case ("snapshot_pending", _): "Collecting system snapshot."
        case ("no_sources", _): "No data-source state yet."
        case ("jsonl_files", _): "JSONL files"
        case ("recent_files", _): "Recent files"
        case ("old_files", _): "Old files"
        case ("large_files", _): "Large files"
        case ("open_sessions", _): "Open sessions"
        case ("activity_monitor", _): "Activity Monitor"
        case ("copy_diagnostics", _): "Copy diagnostics"
        case ("refreshed", _): "Refreshed."
        case ("diagnostics_copied", _): "Diagnostics copied."
        default: key
        }
    }
}

private struct EmptyGuardianMessage: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
    }
}

private extension View {
    func guardianCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.86))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
