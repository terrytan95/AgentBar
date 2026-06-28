import Foundation
@preconcurrency import UserNotifications

struct QuotaResetNotification: Equatable, Sendable {
    var id: String
    var title: String
    var body: String
}

enum QuotaResetNotifications {
    static func refreshedQuotaWindows(
        previous previousAccounts: [UsageAccount],
        current currentAccounts: [UsageAccount],
        now: Date,
        language: AppLanguage
    ) -> [QuotaResetNotification] {
        var previousByID: [String: UsageAccount] = [:]
        for account in previousAccounts where account.service == .codex {
            previousByID[account.id] = account
        }

        return currentAccounts
            .filter { $0.service == .codex }
            .sorted { $0.displayName < $1.displayName }
            .flatMap { account -> [QuotaResetNotification] in
                guard let previous = previousByID[account.id] else { return [] }
                return [
                    notification(
                        account: account,
                        kind: .fiveHour,
                        previousReset: previous.fiveHourWindow?.resetsAt,
                        currentReset: account.fiveHourWindow?.resetsAt,
                        now: now,
                        language: language
                    ),
                    notification(
                        account: account,
                        kind: .weekly,
                        previousReset: previous.weeklyWindow?.resetsAt,
                        currentReset: account.weeklyWindow?.resetsAt,
                        now: now,
                        language: language
                    )
                ].compactMap { $0 }
            }
    }

    private static func notification(
        account: UsageAccount,
        kind: UsageWindow.Kind,
        previousReset: Date?,
        currentReset: Date?,
        now: Date,
        language: AppLanguage
    ) -> QuotaResetNotification? {
        guard let previousReset,
              let currentReset,
              previousReset <= now,
              currentReset > now,
              currentReset > previousReset
        else { return nil }

        let window = title(for: kind, language: language)
        let nextReset = DisplayFormatters.shortDateTimeString(for: currentReset, language: language)
        let title = language == .chinese ? "\(window)额度已刷新" : "\(window) quota refreshed"
        let body = language == .chinese
            ? "\(account.displayName) 的额度已重置。下次重置：\(nextReset)"
            : "\(account.displayName) quota reset. Next reset: \(nextReset)"
        return QuotaResetNotification(
            id: "quota-reset-\(account.id)-\(kind.rawValue)-\(Int(currentReset.timeIntervalSince1970))",
            title: title,
            body: body
        )
    }

    private static func title(for kind: UsageWindow.Kind, language: AppLanguage) -> String {
        switch kind {
        case .fiveHour:
            L.text("five_hour", language)
        case .weekly:
            L.text("weekly", language)
        }
    }
}

enum QuotaResetDesktopNotifier {
    static func notify(_ notification: QuotaResetNotification) {
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
