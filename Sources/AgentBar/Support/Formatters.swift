import Foundation

enum DisplayFormatters {
    static let integer: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
    private static let dateFormatterCache = DateFormatterCache()

    static func tokenString(_ value: Int) -> String {
        integer.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func compactTokenString(_ value: Int, language: AppLanguage) -> String {
        guard language == .chinese else {
            return englishCompactTokenString(value)
        }
        let absolute = abs(value)
        if absolute >= 100_000_000 {
            return String(format: "%.2f亿", Double(value) / 100_000_000)
        }
        if absolute >= 10_000 {
            return String(format: "%.2f万", Double(value) / 10_000)
        }
        return tokenString(value)
    }

    private static func englishCompactTokenString(_ value: Int) -> String {
        let absolute = abs(value)
        if absolute >= 1_000_000_000 {
            return String(format: "%.4f bil", Double(value) / 1_000_000_000)
        }
        if absolute >= 1_000_000 {
            return String(format: "%.4f mil", Double(value) / 1_000_000)
        }
        if absolute >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return tokenString(value)
    }

    static func costString(_ value: Decimal?) -> String {
        guard let value else { return "N/A" }
        return currency.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    static func costString(_ value: Decimal) -> String {
        costString(Optional(value))
    }

    static func percentString(_ value: Double?) -> String {
        guard let value else { return "--%" }
        return "\(Int(value.rounded()))%"
    }

    static func changePercentString(_ value: Double?) -> String {
        guard let value else { return "--" }
        if value > 0 {
            return String(format: "↑ %.1f%%", value)
        }
        if value < 0 {
            return String(format: "↓ %.1f%%", abs(value))
        }
        return "0.0%"
    }

    static func relativeString(for date: Date, language: AppLanguage? = nil) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        if let language {
            formatter.locale = language == .chinese ? Locale(identifier: "zh_Hans") : Locale(identifier: "en_US")
        }
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func shortDateTimeString(for date: Date, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = language == .chinese ? Locale(identifier: "zh_Hans") : Locale(identifier: "en_US")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func shortDayString(for date: Date, language: AppLanguage = .english) -> String {
        localizedDateString(for: date, template: "MMM d", language: language)
    }

    static func localizedDateString(
        for date: Date,
        template: String,
        language: AppLanguage,
        timeZone: TimeZone? = nil
    ) -> String {
        dateFormatterCache.string(for: date, template: template, language: language, timeZone: timeZone)
    }
}

private final class DateFormatterCache: @unchecked Sendable {
    private let lock = NSLock()
    private var formatters: [String: DateFormatter] = [:]

    func string(for date: Date, template: String, language: AppLanguage, timeZone: TimeZone?) -> String {
        let key = "\(language.rawValue)|\(template)|\(timeZone?.identifier ?? "current")"
        lock.lock()
        defer { lock.unlock() }

        let formatter = formatters[key] ?? {
            let formatter = DateFormatter()
            formatter.locale = language == .chinese ? Locale(identifier: "zh_Hans") : Locale(identifier: "en_US")
            formatter.timeZone = timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            formatters[key] = formatter
            return formatter
        }()
        return formatter.string(from: date)
    }
}

extension String {
    var redactedForCredentialWords: String {
        replacingOccurrences(of: #"(?i)(access_token|refresh_token|id_token|session|cookie|secret|private_key)"#, with: "[redacted]", options: .regularExpression)
    }
}
