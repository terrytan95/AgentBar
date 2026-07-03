import Foundation

struct QuotaCapacitySample: Codable, Equatable, Identifiable, Sendable {
    var id: Date { capturedAt }
    var capturedAt: Date
    var accountID: String
    var fiveHourUsedPercent: Double?
    var weeklyUsedPercent: Double?
    var fiveHourResetAt: Date?
    var weeklyResetAt: Date?
    var tokensSincePreviousSample: Int
    var estimatedFiveHourTotalTokens: Int?
    var estimatedWeeklyTotalTokens: Int?
}

struct QuotaCapacityHistory: Equatable, Sendable {
    var samples: [QuotaCapacitySample]

    init(samples: [QuotaCapacitySample]) {
        self.samples = Self.sanitized(samples)
    }

    var latestEstimate: QuotaCapacitySample? {
        samples.last { $0.estimatedFiveHourTotalTokens != nil || $0.estimatedWeeklyTotalTokens != nil }
    }

    func appendingSample(
        account: UsageAccount?,
        points: [UsagePoint],
        now: Date,
        minimumInterval: TimeInterval
    ) -> QuotaCapacityHistory {
        guard let account, account.service == .codex else { return self }
        guard samples.last.map({ now.timeIntervalSince($0.capturedAt) >= minimumInterval }) ?? true else {
            return self
        }

        let previous = samples.last?.accountID == account.id ? samples.last : nil
        let tokensSincePrevious = previous.map { previous in
            points
                .filter { point in
                    point.service == .codex &&
                        point.date > previous.capturedAt &&
                        point.date <= now
                }
                .reduce(0) { $0 + $1.tokens.total }
        } ?? 0

        let next = QuotaCapacitySample(
            capturedAt: now,
            accountID: account.id,
            fiveHourUsedPercent: account.fiveHourWindow?.usedPercent,
            weeklyUsedPercent: account.weeklyWindow?.usedPercent,
            fiveHourResetAt: account.fiveHourWindow?.resetsAt,
            weeklyResetAt: account.weeklyWindow?.resetsAt,
            tokensSincePreviousSample: tokensSincePrevious,
            estimatedFiveHourTotalTokens: Self.estimate(
                previousPercent: previous?.fiveHourUsedPercent,
                currentPercent: account.fiveHourWindow?.usedPercent,
                previousReset: previous?.fiveHourResetAt,
                currentReset: account.fiveHourWindow?.resetsAt,
                tokens: tokensSincePrevious
            ),
            estimatedWeeklyTotalTokens: Self.estimate(
                previousPercent: previous?.weeklyUsedPercent,
                currentPercent: account.weeklyWindow?.usedPercent,
                previousReset: previous?.weeklyResetAt,
                currentReset: account.weeklyWindow?.resetsAt,
                tokens: tokensSincePrevious
            )
        )

        return QuotaCapacityHistory(samples: (samples + [next]).suffix(720))
    }

    private static func sanitized(_ samples: [QuotaCapacitySample]) -> [QuotaCapacitySample] {
        var previous: QuotaCapacitySample?
        return samples.map { sample in
            defer { previous = sample }
            guard previous?.accountID != sample.accountID else { return sample }
            var baseline = sample
            baseline.tokensSincePreviousSample = 0
            baseline.estimatedFiveHourTotalTokens = nil
            baseline.estimatedWeeklyTotalTokens = nil
            return baseline
        }
    }

    private static func estimate(
        previousPercent: Double?,
        currentPercent: Double?,
        previousReset: Date?,
        currentReset: Date?,
        tokens: Int
    ) -> Int? {
        guard tokens > 0,
              let previousReset,
              let currentReset,
              previousReset == currentReset,
              let previousPercent,
              let currentPercent
        else { return nil }

        let percentDelta = currentPercent - previousPercent
        guard percentDelta > 0 else { return nil }
        return Int((Double(tokens) * 100 / percentDelta).rounded())
    }
}

struct QuotaCapacityHistoryStore {
    var defaults: UserDefaults = .standard
    var key: String = "quotaCapacityHistorySamples"

    func load() -> QuotaCapacityHistory {
        guard let data = defaults.data(forKey: key),
              let samples = try? JSONDecoder().decode([QuotaCapacitySample].self, from: data)
        else { return QuotaCapacityHistory(samples: []) }
        return QuotaCapacityHistory(samples: samples)
    }

    func save(_ history: QuotaCapacityHistory) {
        guard let data = try? JSONEncoder().encode(history.samples) else { return }
        defaults.set(data, forKey: key)
    }
}
