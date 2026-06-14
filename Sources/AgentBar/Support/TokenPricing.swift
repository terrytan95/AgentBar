import Foundation

enum TokenPricing {
    struct Rate: Sendable {
        var inputPerMillion: Double
        var cachedInputPerMillion: Double?
        var outputPerMillion: Double
    }

    static func estimate(service: UsageService, model: String, tokens: TokenTotals) -> Double? {
        guard let rate = rate(for: service, model: model) else { return nil }

        let uncachedInput = max(0, tokens.input - tokens.cachedInput)
        let inputCost = Double(uncachedInput) / 1_000_000 * rate.inputPerMillion
        let cachedCost = Double(tokens.cachedInput) / 1_000_000 * (rate.cachedInputPerMillion ?? rate.inputPerMillion)
        let outputCost = Double(tokens.output + tokens.reasoningOutput) / 1_000_000 * rate.outputPerMillion
        return inputCost + cachedCost + outputCost
    }

    static func rate(for service: UsageService, model: String) -> Rate? {
        let normalized = normalize(model)
        switch service {
        case .codex:
            return openAIRates[normalized]
        case .claudeCode:
            return anthropicRates[normalized]
        }
    }

    private static func normalize(_ model: String) -> String {
        model
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // USD per 1M tokens from the public OpenAI API pricing table.
    private static let openAIRates: [String: Rate] = [
        "gpt-5.1": Rate(inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.0),
        "gpt-5.1-codex": Rate(inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.0),
        "gpt-5.1-codex-mini": Rate(inputPerMillion: 0.25, cachedInputPerMillion: 0.025, outputPerMillion: 2.0),
        "gpt-5-mini": Rate(inputPerMillion: 0.25, cachedInputPerMillion: 0.025, outputPerMillion: 2.0),
        "gpt-5-nano": Rate(inputPerMillion: 0.05, cachedInputPerMillion: 0.005, outputPerMillion: 0.4),
        "gpt-5": Rate(inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.0),
        "gpt-4.1": Rate(inputPerMillion: 2.0, cachedInputPerMillion: 0.5, outputPerMillion: 8.0),
        "gpt-4.1-mini": Rate(inputPerMillion: 0.4, cachedInputPerMillion: 0.1, outputPerMillion: 1.6),
        "gpt-4.1-nano": Rate(inputPerMillion: 0.1, cachedInputPerMillion: 0.025, outputPerMillion: 0.4),
        "gpt-4o": Rate(inputPerMillion: 2.5, cachedInputPerMillion: 1.25, outputPerMillion: 10.0),
        "gpt-4o-mini": Rate(inputPerMillion: 0.15, cachedInputPerMillion: 0.075, outputPerMillion: 0.6),
        "o3": Rate(inputPerMillion: 2.0, cachedInputPerMillion: 0.5, outputPerMillion: 8.0),
        "o4-mini": Rate(inputPerMillion: 1.1, cachedInputPerMillion: 0.275, outputPerMillion: 4.4),
        "codex-mini-latest": Rate(inputPerMillion: 1.5, cachedInputPerMillion: 0.375, outputPerMillion: 6.0)
    ]

    // USD per 1M tokens from the public Anthropic API pricing table.
    private static let anthropicRates: [String: Rate] = [
        "claude-opus-4-1": Rate(inputPerMillion: 15.0, cachedInputPerMillion: 1.5, outputPerMillion: 75.0),
        "claude-opus-4.1": Rate(inputPerMillion: 15.0, cachedInputPerMillion: 1.5, outputPerMillion: 75.0),
        "claude-opus-4": Rate(inputPerMillion: 15.0, cachedInputPerMillion: 1.5, outputPerMillion: 75.0),
        "claude-sonnet-4-5": Rate(inputPerMillion: 3.0, cachedInputPerMillion: 0.3, outputPerMillion: 15.0),
        "claude-sonnet-4.5": Rate(inputPerMillion: 3.0, cachedInputPerMillion: 0.3, outputPerMillion: 15.0),
        "claude-sonnet-4": Rate(inputPerMillion: 3.0, cachedInputPerMillion: 0.3, outputPerMillion: 15.0),
        "claude-haiku-4-5": Rate(inputPerMillion: 0.8, cachedInputPerMillion: 0.08, outputPerMillion: 4.0),
        "claude-haiku-4.5": Rate(inputPerMillion: 0.8, cachedInputPerMillion: 0.08, outputPerMillion: 4.0),
        "claude-3-5-haiku": Rate(inputPerMillion: 0.8, cachedInputPerMillion: 0.08, outputPerMillion: 4.0),
        "claude-3-7-sonnet": Rate(inputPerMillion: 3.0, cachedInputPerMillion: 0.3, outputPerMillion: 15.0)
    ]
}
