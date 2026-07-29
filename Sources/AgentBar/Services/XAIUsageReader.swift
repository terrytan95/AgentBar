import AppKit
import Foundation
import Security

struct XAIConfiguration: Sendable {
    var teamID: String
    var managementKey: String
}

enum XAIConfigurationStore {
    static let teamIDDefaultsKey = "xaiTeamID"

    private static let keychainService = "com.terrytan.AgentBar.xai"
    private static let keychainAccount = "management-api-key"

    static var teamID: String? {
        UserDefaults.standard.string(forKey: teamIDDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
    }

    static var isConfigured: Bool {
        configuration != nil
    }

    static var configuration: XAIConfiguration? {
        guard let teamID, let managementKey = try? readManagementKey(), !managementKey.isEmpty else {
            return nil
        }
        return XAIConfiguration(teamID: teamID, managementKey: managementKey)
    }

    static func save(teamID: String, managementKey: String?) throws {
        let teamID = teamID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !teamID.isEmpty else { throw XAIConfigurationError.missingTeamID }
        if let managementKey {
            let managementKey = managementKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !managementKey.isEmpty else { throw XAIConfigurationError.missingManagementKey }
            try saveManagementKey(managementKey)
        } else if (try? readManagementKey())?.isEmpty != false {
            throw XAIConfigurationError.missingManagementKey
        }
        UserDefaults.standard.set(teamID, forKey: teamIDDefaultsKey)
    }

    static func clear() throws {
        let status = SecItemDelete(keychainQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw XAIConfigurationError.keychain(status)
        }
        UserDefaults.standard.removeObject(forKey: teamIDDefaultsKey)
    }

    private static var keychainQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }

    private static func readManagementKey() throws -> String {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw XAIConfigurationError.keychain(status)
        }
        return value
    }

    private static func saveManagementKey(_ value: String) throws {
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            keychainQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw XAIConfigurationError.keychain(updateStatus)
        }

        var item = keychainQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw XAIConfigurationError.keychain(addStatus)
        }
    }
}

enum XAIConfigurationError: LocalizedError {
    case missingTeamID
    case missingManagementKey
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingTeamID:
            "Enter the xAI team ID."
        case .missingManagementKey:
            "Enter an xAI Management API key."
        case let .keychain(status):
            "The xAI Management API key could not be stored in Keychain (status \(status))."
        }
    }
}

@MainActor
enum XAIConfigurationPrompter {
    static func prompt(language: AppLanguage) throws -> Bool {
        let alert = NSAlert()
        alert.messageText = L.text("configure_xai", language)
        alert.informativeText = L.text("configure_xai_message", language)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L.text("save", language))
        alert.addButton(withTitle: L.text("cancel", language))

        let teamField = NSTextField(string: XAIConfigurationStore.teamID ?? "")
        teamField.placeholderString = L.text("xai_team_id", language)
        let keyField = NSSecureTextField(string: "")
        keyField.placeholderString = XAIConfigurationStore.isConfigured
            ? L.text("xai_key_keep_placeholder", language)
            : L.text("xai_management_key", language)

        let stack = NSStackView(views: [teamField, keyField])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 420, height: 54)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = teamField

        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        try XAIConfigurationStore.save(
            teamID: teamField.stringValue,
            managementKey: key.isEmpty ? nil : key
        )
        return true
    }

    static func confirmRemoval(language: AppLanguage) -> Bool {
        let alert = NSAlert()
        alert.messageText = L.text("disconnect_xai", language)
        alert.informativeText = L.text("disconnect_xai_message", language)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.text("disconnect", language))
        alert.addButton(withTitle: L.text("cancel", language))
        return alert.runModal() == .alertFirstButtonReturn
    }
}

struct XAIUsageReader {
    typealias Client = @Sendable (URLRequest, TimeInterval) async throws -> (statusCode: Int, data: Data)

    var now: @Sendable () -> Date = Date.init
    var client: Client = Self.defaultClient
    var timeout: TimeInterval = 15

    func read() async -> UsageSnapshot? {
        guard let configuration = XAIConfigurationStore.configuration else { return nil }
        let refreshedAt = now()

        do {
            let request = try makeRequest(configuration: configuration, refreshedAt: refreshedAt)
            let response = try await client(request, timeout)
            switch response.statusCode {
            case 200:
                return try liveSnapshot(
                    data: response.data,
                    configuration: configuration,
                    refreshedAt: refreshedAt
                )
            case 401, 403:
                return issueSnapshot(
                    status: .needsAuthorization,
                    configuration: configuration,
                    refreshedAt: refreshedAt,
                    note: "xAI Management API rejected the configured credentials (HTTP \(response.statusCode)). Update the management key and verify its billing read access."
                )
            default:
                return issueSnapshot(
                    status: .unavailable,
                    configuration: configuration,
                    refreshedAt: refreshedAt,
                    note: "xAI Management API usage is unavailable (HTTP \(response.statusCode))."
                )
            }
        } catch {
            return issueSnapshot(
                status: .unavailable,
                configuration: configuration,
                refreshedAt: refreshedAt,
                note: "xAI Management API usage could not be refreshed: \(error.localizedDescription.redactedForCredentialWords)"
            )
        }
    }

    private func makeRequest(configuration: XAIConfiguration, refreshedAt: Date) throws -> URLRequest {
        let encodedTeamID = configuration.teamID.addingPercentEncoding(withAllowedCharacters: Self.urlPathSegmentAllowed)
            ?? configuration.teamID
        guard let url = URL(string: "https://management-api.x.ai/v1/billing/teams/\(encodedTeamID)/usage") else {
            throw XAIUsageError.invalidTeamID
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: refreshedAt)) ?? refreshedAt
        let start = calendar.date(byAdding: .day, value: -365, to: end) ?? refreshedAt

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.managementKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            XAIUsageRequest(
                analyticsRequest: .init(
                    timeRange: .init(
                        startTime: Self.apiDate(start),
                        endTime: Self.apiDate(end),
                        timezone: "Etc/GMT"
                    ),
                    timeUnit: "TIME_UNIT_DAY",
                    values: [.init(name: "usd", aggregation: "AGGREGATION_SUM")],
                    groupBy: ["description"],
                    filters: []
                )
            )
        )
        return request
    }

    private func liveSnapshot(
        data: Data,
        configuration: XAIConfiguration,
        refreshedAt: Date
    ) throws -> UsageSnapshot {
        let response = try JSONDecoder().decode(XAIUsageResponse.self, from: data)
        let points = response.timeSeries.flatMap { series -> [UsagePoint] in
            let model = series.groupLabels.first ?? series.group.first ?? "xAI API"
            return series.dataPoints.compactMap { point in
                guard let date = ISO8601DateFormatter().date(from: point.timestamp),
                      let cost = point.values.first,
                      cost != 0
                else { return nil }
                return UsagePoint(
                    service: .xaiAPI,
                    model: model,
                    date: date,
                    tokens: .zero,
                    estimatedCostUSD: cost,
                    sessionID: "xai-api-\(point.timestamp)",
                    sessionTitle: "xAI API billing",
                    projectName: model
                )
            }
        }
        .sorted { $0.date < $1.date }
        let totalCost = points.compactMap(\.estimatedCostUSD).reduce(Decimal(0), +)
        let note = response.limitReached
            ? "xAI Management API returned a cardinality-limited cost result; totals may be incomplete."
            : "Exact billed xAI API cost from the Management API; the management key is stored in macOS Keychain and is never retained in usage records."
        let account = account(
            configuration: configuration,
            status: .live,
            estimatedCostUSD: totalCost,
            lastUpdated: points.last?.date ?? refreshedAt
        )
        return UsageSnapshot(
            service: .xaiAPI,
            status: .live,
            accounts: [account],
            points: points,
            securityNotes: [note],
            refreshedAt: refreshedAt,
            pricingFingerprint: "xai-management-api-billed-usd-v1"
        )
    }

    private func issueSnapshot(
        status: DataSourceStatus,
        configuration: XAIConfiguration,
        refreshedAt: Date,
        note: String
    ) -> UsageSnapshot {
        UsageSnapshot(
            service: .xaiAPI,
            status: status,
            accounts: [
                account(
                    configuration: configuration,
                    status: status,
                    estimatedCostUSD: nil,
                    lastUpdated: nil
                )
            ],
            points: [],
            securityNotes: [note],
            refreshedAt: refreshedAt,
            pricingFingerprint: "xai-management-api-billed-usd-v1"
        )
    }

    private func account(
        configuration: XAIConfiguration,
        status: DataSourceStatus,
        estimatedCostUSD: Decimal?,
        lastUpdated: Date?
    ) -> UsageAccount {
        UsageAccount(
            id: "xai-\(configuration.teamID)",
            service: .xaiAPI,
            displayName: "xAI API",
            username: nil,
            maskedEmail: nil,
            plan: "API",
            sourceDescription: "xAI Management API · billed USD",
            status: status,
            fiveHourWindow: nil,
            weeklyWindow: nil,
            tokens: .zero,
            estimatedCostUSD: estimatedCostUSD,
            lastUpdated: lastUpdated,
            isActive: false,
            workspaceName: "Team",
            workspaceID: configuration.teamID
        )
    }

    private static func apiDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private static var urlPathSegmentAllowed: CharacterSet {
        CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    }

    private static func defaultClient(
        request: URLRequest,
        timeout: TimeInterval
    ) async throws -> (statusCode: Int, data: Data) {
        var request = request
        request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw XAIUsageError.invalidResponse
        }
        return (response.statusCode, data)
    }
}

private enum XAIUsageError: LocalizedError {
    case invalidTeamID
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidTeamID: "The xAI team ID is invalid."
        case .invalidResponse: "xAI returned an invalid response."
        }
    }
}

private struct XAIUsageRequest: Encodable {
    struct AnalyticsRequest: Encodable {
        struct TimeRange: Encodable {
            var startTime: String
            var endTime: String
            var timezone: String
        }

        struct Value: Encodable {
            var name: String
            var aggregation: String
        }

        var timeRange: TimeRange
        var timeUnit: String
        var values: [Value]
        var groupBy: [String]
        var filters: [String]
    }

    var analyticsRequest: AnalyticsRequest
}

private struct XAIUsageResponse: Decodable {
    struct TimeSeries: Decodable {
        struct DataPoint: Decodable {
            var timestamp: String
            var values: [Decimal]
        }

        var group: [String]
        var groupLabels: [String]
        var dataPoints: [DataPoint]
    }

    var timeSeries: [TimeSeries]
    var limitReached: Bool
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
