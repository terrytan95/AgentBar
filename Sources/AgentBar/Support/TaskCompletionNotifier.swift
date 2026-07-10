import Foundation
@preconcurrency import UserNotifications

struct TaskCompletionNotification: Equatable, Sendable {
    var id: String
    var title: String
    var body: String
}

enum TaskCompletionNotifications {
    static func newlyCompleted(
        previous: [AgentTask],
        current: [AgentTask],
        completedAfter: Date,
        language: AppLanguage
    ) -> [TaskCompletionNotification] {
        let previousCompletedIDs = Set(
            previous.filter { $0.terminalState == .completed }.map(\.id)
        )

        return current
            .filter { task in
                task.terminalState == .completed
                    && !previousCompletedIDs.contains(task.id)
                    && (task.completedAt ?? .distantPast) > completedAfter
            }
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
            .map { task in
                let duration = DisplayFormatters.durationString(seconds: task.duration(at: task.completedAt ?? Date()))
                let tokens = DisplayFormatters.compactTokenString(task.tokens.total, language: language)
                let title = language == .chinese ? "Codex 任务已完成" : "Codex task completed"
                let taskTitle = task.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let label = taskTitle.flatMap { $0.isEmpty ? nil : $0 } ?? task.displayProjectName
                let body = language == .chinese
                    ? "\(label) · \(duration) · \(tokens) Tokens"
                    : "\(label) · \(duration) · \(tokens) tokens"
                return TaskCompletionNotification(
                    id: "task-complete-\(task.id)",
                    title: title,
                    body: body
                )
            }
    }
}

enum TaskCompletionDesktopNotifier {
    static func notify(_ notification: TaskCompletionNotification) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: notification.id, content: content, trigger: nil))
        }
    }
}
