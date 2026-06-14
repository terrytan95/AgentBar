import Foundation

struct ClaudeUsageReader {
    var homeDirectory: URL
    var fileManager: FileManager = .default

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    func read() -> UsageSnapshot {
        Self.discover(homeDirectory: homeDirectory)
    }

    static func discover(homeDirectory: URL) -> UsageSnapshot {
        let claudeCliDir = homeDirectory.appending(path: ".claude")
        let desktopDir = homeDirectory.appending(path: "Library/Application Support/Claude")
        let now = Date()

        if FileManager.default.fileExists(atPath: claudeCliDir.path) {
            return UsageSnapshot(
                service: .claudeCode,
                status: .needsAuthorization,
                accounts: [],
                points: [],
                securityNotes: ["Claude Code requires explicit local CLI data or Anthropic Admin API authorization for live usage and costs."],
                refreshedAt: now,
                pricingFingerprint: Pricing.fingerprint
            )
        }

        let desktopExists = FileManager.default.fileExists(atPath: desktopDir.path)
        let source = desktopExists
            ? "Claude Desktop found, Claude Code local usage cache not found."
            : "Claude Code not found on this Mac."

        return UsageSnapshot(
            service: .claudeCode,
            status: .unavailable,
            accounts: [],
            points: [],
            securityNotes: ["\(source) Official usage/cost APIs require user-provided Anthropic authorization."],
            refreshedAt: now,
            pricingFingerprint: Pricing.fingerprint
        )
    }
}
