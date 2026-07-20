import SwiftUI

struct LiveTaskCenterView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var taskChangeAnimation: Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: AgentBarDesign.durationNormal)
    }

    private var taskChangeTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }

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
            let activeTaskIDs = activeTasks.map(\.id)
            let recentTaskIDs = recentTasks.map(\.id)
            let taskStateSignature = store.tasks.map {
                "\($0.id):\($0.state(at: timeline.date).rawValue)"
            }

            VStack(alignment: .leading, spacing: 16) {
                header(activeTasks: activeTasks, now: timeline.date)
                summary(activeTasks: activeTasks, recentTasks: recentTasks, now: timeline.date)

                if activeTasks.isEmpty && recentTasks.isEmpty {
                    emptyState
                } else {
                    if !activeTasks.isEmpty {
                        taskSection(
                            title: L.text("active_tasks", store.language),
                            tasks: activeTasks,
                            now: timeline.date
                        )
                        .transition(taskChangeTransition)
                    }
                    if !recentTasks.isEmpty {
                        taskSection(
                            title: L.text("recent_activity", store.language),
                            tasks: Array(recentTasks.prefix(20)),
                            now: timeline.date
                        )
                        .transition(taskChangeTransition)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .animation(taskChangeAnimation, value: activeTaskIDs)
            .animation(taskChangeAnimation, value: recentTaskIDs)
            .animation(taskChangeAnimation, value: taskStateSignature)
        }
    }

    private func header(activeTasks: [AgentTask], now: Date) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L.text("live_tasks", store.language))
                    .font(.agentBar(size: 20, weight: .bold))
                Text(L.text("live_tasks_subtitle", store.language))
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
            taskMetric(L.text("working", store.language), "\(working)", color: .green)
            taskMetric(L.text("task_waiting", store.language), "\(waiting)", color: .orange)
            taskMetric(L.text("completed", store.language), "\(completed)", color: AgentBarPalette.primary)
            taskMetric(L.text("active_tokens", store.language), DisplayFormatters.compactTokenString(activeTokens, language: store.language), color: .blue)
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
                    .transition(taskChangeTransition)
                if index < tasks.count - 1 { Divider() }
            }
        }
        .agentBarPanel(cornerRadius: 14)
    }

    private func taskRow(_ task: AgentTask, now: Date) -> some View {
        let state = task.state(at: now)
        let presentation = statePresentation(state)
        return HStack(spacing: 16) {
            stateIndicator(presentation)

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title?.trimmedNonEmpty ?? L.text("untitled_task", store.language))
                    .font(.agentBar(size: 13, weight: .bold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label(task.displayProjectName(language: store.language), systemImage: "folder")
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

            taskValue(L.text("task_duration", store.language), DisplayFormatters.durationString(seconds: task.duration(at: now)), width: 90)
            taskValue("Tokens", DisplayFormatters.compactTokenString(task.tokens.total, language: store.language), width: 90)
            taskValue(L.text("task_cost", store.language), DisplayFormatters.costString(task.estimatedCostUSD), width: 84)
            taskValue(L.text("task_model", store.language), modelText(for: task), width: 164)

            Text(presentation.title)
                .font(.agentBar(size: 11, weight: .bold))
                .foregroundStyle(presentation.color)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(presentation.color.opacity(0.12), in: Capsule())
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

    private func modelText(for task: AgentTask) -> String {
        let model = task.models.first ?? "--"
        guard let effort = task.reasoningEffort?.trimmedNonEmpty else { return model }
        return "\(model) · \(displayEffort(effort))"
    }

    private func displayEffort(_ effort: String) -> String {
        switch effort.lowercased() {
        case "xhigh": return "Extra High"
        default: return effort.capitalized
        }
    }

    private func stateIndicator(_ presentation: TaskStatePresentation) -> some View {
        ZStack {
            Circle().fill(presentation.color.opacity(0.14)).frame(width: 34, height: 34)
            Image(systemName: presentation.icon)
                .font(.agentBar(size: 13, weight: .bold))
                .foregroundStyle(presentation.color)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 36))
                .foregroundStyle(AgentBarPalette.primary)
            Text(L.text("no_codex_tasks", store.language))
                .font(.agentBar(size: 16, weight: .bold))
            Text(L.text("no_codex_tasks_subtitle", store.language))
                .font(.agentBar(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .agentBarPanel(cornerRadius: 14)
    }

    private func statePresentation(_ state: AgentTaskState) -> TaskStatePresentation {
        switch state {
        case .working:
            TaskStatePresentation(title: L.text("working", store.language), color: .green, icon: "bolt.fill")
        case .waiting:
            TaskStatePresentation(title: L.text("task_waiting", store.language), color: .orange, icon: "pause.fill")
        case .completed:
            TaskStatePresentation(title: L.text("completed", store.language), color: AgentBarPalette.primary, icon: "checkmark")
        case .interrupted:
            TaskStatePresentation(title: L.text("interrupted", store.language), color: .red, icon: "xmark")
        }
    }
}

private struct TaskStatePresentation {
    var title: String
    var color: Color
    var icon: String
}
