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
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 4
        return formatter
    }()

    static func tokenString(_ value: Int) -> String {
        integer.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func compactTokenString(_ value: Int) -> String {
        let absolute = abs(value)
        if absolute >= 100_000_000 {
            return String(format: "%.2f亿", Double(value) / 100_000_000)
        }
        if absolute >= 10_000 {
            return String(format: "%.2f万", Double(value) / 10_000)
        }
        return tokenString(value)
    }

    static func costString(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        return currency.string(from: NSNumber(value: value)) ?? String(format: "$%.4f", value)
    }

    static func percentString(_ value: Double?) -> String {
        guard let value else { return "--%" }
        return "\(Int(value.rounded()))%"
    }

    static func relativeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

extension String {
    var redactedForCredentialWords: String {
        replacingOccurrences(of: #"(?i)(access_token|refresh_token|id_token|session|cookie|secret|private_key)"#, with: "[redacted]", options: .regularExpression)
    }
}
