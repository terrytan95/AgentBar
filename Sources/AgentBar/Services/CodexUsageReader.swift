import Foundation

enum UsageReadError: Error {
    case invalidRegistry
}

struct CodexUsageReader {
    var homeDirectory: URL
    var fileManager: FileManager = .default

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    func read() -> UsageSnapshot {
        let now = Date()
        let registryURL = homeDirectory.appending(path: ".codex/accounts/registry.json")
        var accounts: [UsageAccount] = []
        var points: [UsagePoint] = []
        var notes = [
            "Read-only local Codex registry and usage JSONL; credential auth files are not opened."
        ]

        if let data = try? Data(contentsOf: registryURL),
           let snapshot = try? Self.parseRegistry(data: data, now: now) {
            accounts = snapshot.accounts
            notes.append(contentsOf: snapshot.securityNotes)
        } else {
            notes.append("Codex registry not found at ~/.codex/accounts/registry.json.")
        }

        let sessionRoot = homeDirectory.appending(path: ".codex/sessions")
        let metrics = readSessionMetrics(root: sessionRoot)
        points.append(contentsOf: metrics.points)

        if !accounts.isEmpty {
            accounts = accounts.map { account in
                var account = account
                if account.isActive, let latestFiveHour = metrics.latestFiveHour {
                    account.fiveHourWindow = latestFiveHour
                } else if account.fiveHourWindow == nil {
                    account.fiveHourWindow = metrics.latestFiveHour
                }
                if account.isActive, let latestWeekly = metrics.latestWeekly {
                    account.weeklyWindow = latestWeekly
                } else if account.weeklyWindow == nil {
                    account.weeklyWindow = metrics.latestWeekly
                }
                if account.tokens.total == 0 {
                    account.tokens = metrics.tokenTotals
                }
                if account.isActive {
                    account.lastUpdated = metrics.latestRateLimitAt ?? account.lastUpdated ?? now
                } else {
                    account.lastUpdated = account.lastUpdated ?? now
                }
                return account
            }
        }

        let status: DataSourceStatus = accounts.isEmpty && metrics.eventCount == 0 ? .unavailable : .live
        return UsageSnapshot(
            service: .codex,
            status: status,
            accounts: accounts,
            points: points,
            securityNotes: notes,
            refreshedAt: now,
            pricingFingerprint: Pricing.fingerprint
        )
    }

    static func parseRegistry(data: Data, now: Date) throws -> UsageSnapshot {
        let registry = try JSONDecoder().decode(CodexRegistry.self, from: data)
        let accounts = registry.accounts.map { raw in
            let username = firstNonEmptyOptional([raw.email, raw.accountName, raw.alias])
            let displayName = username ?? "Codex Account"
            let primary = raw.lastUsage?.primary.map {
                UsageWindow(kind: .fiveHour, usedPercent: $0.usedPercent, windowMinutes: $0.windowMinutes, resetsAt: epochDate($0.resetsAt))
            }
            let secondary = raw.lastUsage?.secondary.map {
                UsageWindow(kind: .weekly, usedPercent: $0.usedPercent, windowMinutes: $0.windowMinutes, resetsAt: epochDate($0.resetsAt))
            }

            return UsageAccount(
                id: raw.accountKey,
                service: .codex,
                displayName: displayName,
                username: username,
                maskedEmail: maskEmail(raw.email),
                plan: raw.plan ?? raw.lastUsage?.planType,
                sourceDescription: "Local Codex account registry",
                status: .live,
                fiveHourWindow: primary,
                weeklyWindow: secondary,
                tokens: .zero,
                estimatedCostUSD: nil,
                lastUpdated: epochDate(raw.lastUsageAt) ?? now,
                isActive: raw.accountKey == registry.activeAccountKey
            )
        }

        return UsageSnapshot(
            service: .codex,
            status: accounts.isEmpty ? .unavailable : .live,
            accounts: accounts,
            points: [],
            securityNotes: ["Parsed account metadata only; credential auth files are excluded."],
            refreshedAt: now,
            pricingFingerprint: Pricing.fingerprint
        )
    }

    static func parseSessionJsonl(data: Data) throws -> CodexSessionMetrics {
        guard let body = String(data: data, encoding: .utf8) else {
            return CodexSessionMetrics(eventCount: 0, tokenTotals: .zero, points: [], latestFiveHour: nil, latestWeekly: nil, latestRateLimitAt: nil)
        }

        var eventCount = 0
        var latestTotal = TokenTotals.zero
        var points: [UsagePoint] = []
        var fiveHour: UsageWindow?
        var weekly: UsageWindow?
        var latestRateLimitAt: Date?
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for line in body.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let event = try? decoder.decode(CodexSessionEvent.self, from: lineData)
            else { continue }

            guard let payload = event.payload else { continue }
            let eventDate = event.parsedDate ?? Date()
            if let cumulativeUsage = payload.info?.totalTokenUsage ?? payload.info?.lastTokenUsage {
                latestTotal = cumulativeUsage.toTotals()
                eventCount += 1
                let model = payload.info?.model ?? "Codex local"
                let pointUsage = payload.info?.lastTokenUsage ?? cumulativeUsage
                let tokens = pointUsage.toTotals()
                points.append(
                    UsagePoint(
                        service: .codex,
                        model: model,
                        date: eventDate,
                        tokens: tokens,
                        estimatedCostUSD: Pricing.cost(model: model, tokens: tokens)
                    )
                )
            }

            if payload.rateLimits != nil,
               latestRateLimitAt == nil || eventDate >= (latestRateLimitAt ?? .distantPast) {
                if let primary = payload.rateLimits?.primary {
                    fiveHour = UsageWindow(kind: .fiveHour, usedPercent: primary.usedPercent, windowMinutes: primary.windowMinutes, resetsAt: epochDate(primary.resetsAt))
                }
                if let secondary = payload.rateLimits?.secondary {
                    weekly = UsageWindow(kind: .weekly, usedPercent: secondary.usedPercent, windowMinutes: secondary.windowMinutes, resetsAt: epochDate(secondary.resetsAt))
                }
                latestRateLimitAt = eventDate
            }
        }

        return CodexSessionMetrics(eventCount: eventCount, tokenTotals: latestTotal, points: points, latestFiveHour: fiveHour, latestWeekly: weekly, latestRateLimitAt: latestRateLimitAt)
    }

    private func readSessionMetrics(root: URL) -> CodexSessionMetrics {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return CodexSessionMetrics(eventCount: 0, tokenTotals: .zero, points: [], latestFiveHour: nil, latestWeekly: nil, latestRateLimitAt: nil)
        }

        var aggregate = CodexSessionMetrics(eventCount: 0, tokenTotals: .zero, points: [], latestFiveHour: nil, latestWeekly: nil, latestRateLimitAt: nil)

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            guard let data = try? Data(contentsOf: fileURL),
                  let metrics = try? Self.parseSessionJsonl(data: data)
            else { continue }

            aggregate.eventCount += metrics.eventCount
            if metrics.tokenTotals.total > 0 {
                aggregate.tokenTotals = aggregate.tokenTotals + metrics.tokenTotals
            }
            aggregate.points.append(contentsOf: metrics.points)
            if let latestRateLimitAt = metrics.latestRateLimitAt,
               aggregate.latestRateLimitAt == nil || latestRateLimitAt >= (aggregate.latestRateLimitAt ?? .distantPast) {
                aggregate.latestFiveHour = metrics.latestFiveHour
                aggregate.latestWeekly = metrics.latestWeekly
                aggregate.latestRateLimitAt = latestRateLimitAt
            }
        }

        return aggregate
    }
}

private struct CodexRegistry: Decodable {
    var activeAccountKey: String?
    var accounts: [CodexRegistryAccount]

    enum CodingKeys: String, CodingKey {
        case activeAccountKey = "active_account_key"
        case accounts
    }
}

private struct CodexRegistryAccount: Decodable {
    var accountKey: String
    var accountName: String?
    var alias: String?
    var email: String?
    var plan: String?
    var lastUsage: CodexLastUsage?
    var lastUsageAt: Double?

    enum CodingKeys: String, CodingKey {
        case accountKey = "account_key"
        case accountName = "account_name"
        case alias
        case email
        case plan
        case lastUsage = "last_usage"
        case lastUsageAt = "last_usage_at"
    }
}

private struct CodexLastUsage: Decodable {
    var planType: String?
    var primary: CodexRateWindow?
    var secondary: CodexRateWindow?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case primary
        case secondary
    }
}

private struct CodexRateWindow: Decodable {
    var usedPercent: Double
    var windowMinutes: Int
    var resetsAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}

private struct CodexSessionEvent: Decodable {
    var timestamp: String?
    var payload: CodexSessionPayload?

    var parsedDate: Date? {
        guard let timestamp else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp)
    }
}

private struct CodexSessionPayload: Decodable {
    var info: CodexInfo?
    var rateLimits: CodexRateLimits?

    enum CodingKeys: String, CodingKey {
        case info
        case rateLimits = "rate_limits"
    }
}

private struct CodexInfo: Decodable {
    var model: String?
    var lastTokenUsage: CodexTokenUsage?
    var totalTokenUsage: CodexTokenUsage?

    enum CodingKeys: String, CodingKey {
        case model
        case lastTokenUsage = "last_token_usage"
        case totalTokenUsage = "total_token_usage"
    }
}

private struct CodexRateLimits: Decodable {
    var primary: CodexRateWindow?
    var secondary: CodexRateWindow?
}

private struct CodexTokenUsage: Decodable {
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var reasoningOutputTokens: Int
    var totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
        case totalTokens = "total_tokens"
    }

    func toTotals() -> TokenTotals {
        TokenTotals(input: inputTokens, cachedInput: cachedInputTokens, output: outputTokens, reasoningOutput: reasoningOutputTokens, total: totalTokens)
    }
}

private func firstNonEmptyOptional(_ values: [String?]) -> String? {
    values.compactMap { value -> String? in
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }.first
}

private func maskEmail(_ email: String?) -> String? {
    guard let email, let atIndex = email.firstIndex(of: "@") else { return email }
    let local = String(email[..<atIndex])
    let domain = String(email[email.index(after: atIndex)...])
    let first = local.first.map(String.init) ?? "*"
    return "\(first)***@\(domain)"
}

private func epochDate(_ value: Double?) -> Date? {
    guard let value else { return nil }
    return Date(timeIntervalSince1970: value)
}
