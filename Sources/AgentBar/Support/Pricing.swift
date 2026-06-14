import CryptoKit
import Foundation

/// Model prices in USD per million tokens. Unknown models cost 0 while token usage is still recorded.
struct ModelPrice: Sendable {
    var input: Decimal
    var output: Decimal
    var cacheRead: Decimal
    var cacheCreation: Decimal
}

enum Pricing {
    static let table: [String: ModelPrice] = [
        "claude-fable-5": .init(input: 10, output: 50, cacheRead: 1.00, cacheCreation: 12.50),
        "claude-opus-4-8": .init(input: 5, output: 25, cacheRead: 0.50, cacheCreation: 6.25),
        "claude-opus-4-7": .init(input: 5, output: 25, cacheRead: 0.50, cacheCreation: 6.25),
        "claude-opus-4-6": .init(input: 5, output: 25, cacheRead: 0.50, cacheCreation: 6.25),
        "claude-opus-4-5": .init(input: 5, output: 25, cacheRead: 0.50, cacheCreation: 6.25),
        "claude-opus-4-1": .init(input: 15, output: 75, cacheRead: 1.50, cacheCreation: 18.75),
        "claude-opus-4": .init(input: 15, output: 75, cacheRead: 1.50, cacheCreation: 18.75),
        "claude-sonnet-4-7": .init(input: 3, output: 15, cacheRead: 0.30, cacheCreation: 3.75),
        "claude-sonnet-4-6": .init(input: 3, output: 15, cacheRead: 0.30, cacheCreation: 3.75),
        "claude-sonnet-4-5": .init(input: 3, output: 15, cacheRead: 0.30, cacheCreation: 3.75),
        "claude-sonnet-4": .init(input: 3, output: 15, cacheRead: 0.30, cacheCreation: 3.75),
        "claude-haiku-4-5": .init(input: 1, output: 5, cacheRead: 0.10, cacheCreation: 1.25),
        "claude-haiku-4": .init(input: 0.8, output: 4, cacheRead: 0.08, cacheCreation: 1.0),

        "gpt-5": .init(input: 1.25, output: 10, cacheRead: 0.125, cacheCreation: 0),
        "gpt-5-mini": .init(input: 0.25, output: 2, cacheRead: 0.025, cacheCreation: 0),
        "gpt-5-nano": .init(input: 0.05, output: 0.40, cacheRead: 0.005, cacheCreation: 0),
        "gpt-5-codex": .init(input: 1.25, output: 10, cacheRead: 0.125, cacheCreation: 0),
        "gpt-5.1": .init(input: 1.25, output: 10, cacheRead: 0.125, cacheCreation: 0),
        "gpt-5.1-codex": .init(input: 1.25, output: 10, cacheRead: 0.125, cacheCreation: 0),
        "gpt-5.1-codex-mini": .init(input: 0.25, output: 2, cacheRead: 0.025, cacheCreation: 0),
        "gpt-5.2": .init(input: 1.25, output: 10, cacheRead: 0.125, cacheCreation: 0),
        "gpt-5.3": .init(input: 1.25, output: 10, cacheRead: 0.125, cacheCreation: 0),
        "gpt-5.4": .init(input: 2.50, output: 15, cacheRead: 0.25, cacheCreation: 0),
        "gpt-5.4-codex": .init(input: 2.50, output: 15, cacheRead: 0.25, cacheCreation: 0),
        "gpt-5.5": .init(input: 5, output: 30, cacheRead: 0.50, cacheCreation: 0),
        "gpt-5.5-codex": .init(input: 5, output: 30, cacheRead: 0.50, cacheCreation: 0),
        "gpt-5.5-pro": .init(input: 5, output: 30, cacheRead: 0.50, cacheCreation: 0),
        "gpt-5.6": .init(input: 5, output: 30, cacheRead: 0.50, cacheCreation: 0),
        "gpt-4.1": .init(input: 2.0, output: 8.0, cacheRead: 0.5, cacheCreation: 0),
        "gpt-4.1-mini": .init(input: 0.4, output: 1.6, cacheRead: 0.1, cacheCreation: 0),
        "gpt-4.1-nano": .init(input: 0.1, output: 0.4, cacheRead: 0.025, cacheCreation: 0),
        "gpt-4o": .init(input: 2.5, output: 10.0, cacheRead: 1.25, cacheCreation: 0),
        "gpt-4o-mini": .init(input: 0.15, output: 0.6, cacheRead: 0.075, cacheCreation: 0),
        "o3": .init(input: 2.0, output: 8.0, cacheRead: 0.5, cacheCreation: 0),
        "o4-mini": .init(input: 1.1, output: 4.4, cacheRead: 0.275, cacheCreation: 0),
        "codex-mini-latest": .init(input: 1.50, output: 6, cacheRead: 0.375, cacheCreation: 0)
    ]

    static func normalize(model: String) -> String {
        var normalized = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("openai/") {
            normalized.removeFirst("openai/".count)
        }
        if let at = normalized.firstIndex(of: "@") {
            normalized = String(normalized[..<at])
        }
        for pattern in [#"-\d{4}-\d{2}-\d{2}$"#, #"-\d{8}$"#] {
            if let range = normalized.range(of: pattern, options: .regularExpression) {
                normalized.removeSubrange(range)
                break
            }
        }
        return normalized.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static let perMillion: Decimal = 1_000_000

    static func cost(
        model: String,
        input: Int,
        output: Int,
        cacheRead: Int,
        cacheCreation: Int
    ) -> Decimal {
        guard let price = table[normalize(model: model)] else { return 0 }
        return Decimal(input) * price.input / perMillion
            + Decimal(output) * price.output / perMillion
            + Decimal(cacheRead) * price.cacheRead / perMillion
            + Decimal(cacheCreation) * price.cacheCreation / perMillion
    }

    static func cost(model: String, tokens: TokenTotals) -> Decimal {
        let uncachedInput = max(0, tokens.input - tokens.cachedInput)
        return cost(
            model: model,
            input: uncachedInput,
            output: tokens.output + tokens.reasoningOutput,
            cacheRead: tokens.cachedInput,
            cacheCreation: 0
        )
    }

    static func hasPrice(model: String) -> Bool {
        table[normalize(model: model)] != nil
    }

    static let fingerprint: String = {
        let body = table.keys.sorted().map { key -> String in
            let price = table[key]!
            return "\(key):\(price.input)/\(price.output)/\(price.cacheRead)/\(price.cacheCreation)"
        }.joined(separator: ";")
        let digest = SHA256.hash(data: Data(body.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }()
}
