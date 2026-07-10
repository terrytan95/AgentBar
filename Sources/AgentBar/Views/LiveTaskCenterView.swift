import SwiftUI

struct LiveTaskCenterView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let activeTasks = store.tasks.filter { task in
                let state = task.state(at: timeline.date)
                return state == .working || state == .waiting
            }
            let recentTasks = store.tasks.filter { task in
                let state = task.state(at: timeline.date)
                return state == .completed || state == .interrupted
            }

            VStack(alignment: .leading, spacing: 16) {
                header(activeTasks: activeTasks, now: timeline.date)
                summary(activeTasks: activeTasks, recentTasks: recentTasks, now: timeline.date)

                if activeTasks.isEmpty && recentTasks.isEmpty {
                    emptyState
                } else {
                    if !activeTasks.isEmpty {
                        taskSection(
                            title: localized("Active tasks", "当前任务"),
                            tasks: activeTasks,
                            now: timeline.date
                        )
                    }
                    if !recentTasks.isEmpty {
                        taskSection(
                            title: localized("Recent activity", "最近任务"),
                            tasks: Array(recentTasks.prefix(20)),
                            now: timeline.date
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func header(activeTasks: [AgentTask], now: Date) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(localized("Live Tasks", "实时任务"))
                    .font(.agentBar(size: 20, weight: .bold))
                Text(localized("Codex activity refreshes every 5 seconds.", "Codex 活动每 5 秒刷新一次。"))
                    .font(.agentBar(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.refreshTaskCenter()
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

    private func summary(activeTasks: [AgentTask], recentTasks: [AgentTask], now: Date) -> some View {
        let working = activeTasks.filter { $0.state(at: now) == .working }.count
        let waiting = activeTasks.filter { $0.state(at: now) == .waiting }.count
        let completed = recentTasks.filter { $0.state(at: now) == .completed }.count
        let activeTokens = activeTasks.reduce(0) { $0 + $1.tokens.total }

        return HStack(spacing: 14) {
            taskMetric(localized("Working", "运行中"), "\(working)", color: .green)
            taskMetric(localized("Waiting", "等待中"), "\(waiting)", color: .orange)
            taskMetric(localized("Completed", "已完成"), "\(completed)", color: AgentBarPalette.primary)
            taskMetric(localized("Active tokens", "当前 Tokens"), DisplayFormatters.compactTokenString(activeTokens, language: store.language), color: .blue)
        }
    }

    private func taskMetric(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title)
                    .font(.agentBar(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.agentBarMono(size: 24, weight: .bold))
                .monospacedDigit()
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .agentBarPanel(cornerRadius: 12)
    }

    private func taskSection(title: String, tasks: [AgentTask], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.agentBar(size: 15, weight: .bold))
                .padding(16)

            Divider()

            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                taskRow(task, now: now)
                if index < tasks.count - 1 { Divider() }
            }
        }
        .agentBarPanel(cornerRadius: 14)
    }

    private func taskRow(_ task: AgentTask, now: Date) -> some View {
        let state = task.state(at: now)
        return HStack(spacing: 16) {
            stateIndicator(state)

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? localized("Untitled task", "未命名任务"))
                    .font(.agentBar(size: 13, weight: .bold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label(task.displayProjectName, systemImage: "folder")
                    if let path = task.repositoryPath ?? task.cwd {
                        Text(path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.agentBar(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            taskValue(localized("Duration", "运行时长"), DisplayFormatters.durationString(seconds: task.duration(at: now)), width: 90)
            taskValue("Tokens", DisplayFormatters.compactTokenString(task.tokens.total, language: store.language), width: 90)
            taskValue(localized("Cost", "费用"), DisplayFormatters.costString(task.estimatedCostUSD), width: 84)
            taskValue(localized("Model", "模型"), task.models.first ?? "--", width: 116)

            Text(stateTitle(state))
                .font(.agentBar(size: 11, weight: .bold))
                .foregroundStyle(stateColor(state))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(stateColor(state).opacity(0.12), in: Capsule())
                .frame(width: 86)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 72)
    }

    private func taskValue(_ title: String, _ value: String, width: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(title)
                .font(.agentBar(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.agentBarMono(size: 11, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(width: width, alignment: .trailing)
    }

    private func stateIndicator(_ state: AgentTaskState) -> some View {
        ZStack {
            Circle().fill(stateColor(state).opacity(0.14)).frame(width: 34, height: 34)
            Image(systemName: stateIcon(state))
                .font(.agentBar(size: 13, weight: .bold))
                .foregroundStyle(stateColor(state))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 36))
                .foregroundStyle(AgentBarPalette.primary)
            Text(localized("No Codex tasks found", "暂未发现 Codex 任务"))
                .font(.agentBar(size: 16, weight: .bold))
            Text(localized("Start a Codex task and it will appear here automatically.", "启动 Codex 任务后会自动显示在这里。"))
                .font(.agentBar(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .agentBarPanel(cornerRadius: 14)
    }

    private func stateTitle(_ state: AgentTaskState) -> String {
        switch state {
        case .working: localized("Working", "运行中")
        case .waiting: localized("Waiting", "等待中")
        case .completed: localized("Completed", "已完成")
        case .interrupted: localized("Interrupted", "已中断")
        }
    }

    private func stateColor(_ state: AgentTaskState) -> Color {
        switch state {
        case .working: .green
        case .waiting: .orange
        case .completed: AgentBarPalette.primary
        case .interrupted: .red
        }
    }

    private func stateIcon(_ state: AgentTaskState) -> String {
        switch state {
        case .working: "bolt.fill"
        case .waiting: "pause.fill"
        case .completed: "checkmark"
        case .interrupted: "xmark"
        }
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        store.language == .chinese ? chinese : english
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
