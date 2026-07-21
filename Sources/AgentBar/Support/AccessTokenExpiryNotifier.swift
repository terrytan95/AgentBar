import Foundation
@preconcurrency import UserNotifications

struct AccessTokenExpiryReminder: Equatable, Sendable {
    var accountID: String
    var expiry: Date
    var deliveryDate: Date
    var title: String
    var body: String

    var notificationID: String { "access-token-expiry-\(accountID)" }
}

struct AccessTokenExpiryReminderPlan: Equatable, Sendable {
    var reminders: [AccessTokenExpiryReminder]
    var notificationIDsToRemove: [String]
    var registrations: [String: TimeInterval]
}

enum AccessTokenExpiryReminderPlanner {
    static let warningInterval: TimeInterval = 86_400

    static func plan(
        accounts: [UsageAccount],
        registeredExpirations: [String: TimeInterval],
        enabled: Bool,
        now: Date,
        language: AppLanguage
    ) -> AccessTokenExpiryReminderPlan {
        guard enabled else {
            return AccessTokenExpiryReminderPlan(
                reminders: [],
                notificationIDsToRemove: registeredExpirations.keys.map(notificationID).sorted(),
                registrations: [:]
            )
        }

        var reminders: [AccessTokenExpiryReminder] = []
        var registrations: [String: TimeInterval] = [:]
        var notificationIDsToRemove = Set<String>()

        for account in accounts.sorted(by: { $0.id < $1.id }) where account.service == .codex {
            guard let expiry = account.accessTokenExpiresAt, expiry > now else { continue }
            let expiration = expiry.timeIntervalSince1970
            registrations[account.id] = expiration
            guard registeredExpirations[account.id] != expiration else { continue }
            if registeredExpirations[account.id] != nil {
                notificationIDsToRemove.insert(notificationID(account.id))
            }
            reminders.append(AccessTokenExpiryReminder(
                accountID: account.id,
                expiry: expiry,
                deliveryDate: max(now, expiry.addingTimeInterval(-warningInterval)),
                title: L.text("access_token_expiry_notification_title", language),
                body: notificationBody(account: account, expiry: expiry, language: language)
            ))
        }

        for accountID in registeredExpirations.keys where registrations[accountID] == nil {
            notificationIDsToRemove.insert(notificationID(accountID))
        }

        return AccessTokenExpiryReminderPlan(
            reminders: reminders,
            notificationIDsToRemove: notificationIDsToRemove.sorted(),
            registrations: registrations
        )
    }

    private static func notificationID(_ accountID: String) -> String {
        "access-token-expiry-\(accountID)"
    }

    private static func notificationBody(account: UsageAccount, expiry: Date, language: AppLanguage) -> String {
        let date = DisplayFormatters.shortDateTimeString(for: expiry, language: language)
        return String(
            format: L.text("access_token_expiry_notification_body", language),
            account.displayName,
            date
        )
    }
}

@MainActor
final class AccessTokenExpiryDesktopScheduler {
    static let shared = AccessTokenExpiryDesktopScheduler()

    private static let registrationsKey = "accessTokenExpiryReminderRegistrations"
    private let defaults: UserDefaults
    private let centerProvider: @MainActor () -> UNUserNotificationCenter

    init(
        defaults: UserDefaults = .standard,
        centerProvider: @escaping @MainActor () -> UNUserNotificationCenter = { .current() }
    ) {
        self.defaults = defaults
        self.centerProvider = centerProvider
    }

    func reconcile(accounts: [UsageAccount], enabled: Bool, language: AppLanguage) {
        let registered = registeredExpirations
        let plan = AccessTokenExpiryReminderPlanner.plan(
            accounts: accounts,
            registeredExpirations: registered,
            enabled: enabled,
            now: Date(),
            language: language
        )
        let retained = registered.filter { plan.registrations[$0.key] == $0.value }

        guard !plan.notificationIDsToRemove.isEmpty || !plan.reminders.isEmpty else { return }
        let center = centerProvider()
        center.removePendingNotificationRequests(withIdentifiers: plan.notificationIDsToRemove)
        guard enabled else {
            registeredExpirations = [:]
            return
        }

        Task { @MainActor in
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
                registeredExpirations = retained
                return
            }

            var successful = retained
            for reminder in plan.reminders {
                let content = UNMutableNotificationContent()
                content.title = reminder.title
                content.body = reminder.body
                content.sound = .default
                let interval = reminder.deliveryDate.timeIntervalSinceNow
                let trigger = interval > 0
                    ? UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
                    : nil
                let request = UNNotificationRequest(
                    identifier: reminder.notificationID,
                    content: content,
                    trigger: trigger
                )
                if (try? await center.add(request)) != nil {
                    successful[reminder.accountID] = reminder.expiry.timeIntervalSince1970
                }
            }
            registeredExpirations = successful
        }
    }

    private var registeredExpirations: [String: TimeInterval] {
        get {
            defaults.dictionary(forKey: Self.registrationsKey)?.compactMapValues {
                ($0 as? NSNumber)?.doubleValue
            } ?? [:]
        }
        set {
            defaults.set(newValue, forKey: Self.registrationsKey)
        }
    }
}
