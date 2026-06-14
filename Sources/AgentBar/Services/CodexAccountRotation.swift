import Foundation

struct CodexAccountRotationPolicy {
    var thresholdRemainingPercent: Double = 10

    func selectedAccount(from accounts: [UsageAccount], now: Date = Date()) -> UsageAccount? {
        guard let active = accounts.first(where: { $0.service == .codex && $0.isActive }),
              let activeRemaining = active.fiveHourWindow?.remainingPercent,
              activeRemaining <= thresholdRemainingPercent
        else {
            return nil
        }

        let candidates = accounts.filter { account in
            account.service == .codex
                && !account.isActive
                && account.fiveHourWindow?.remainingPercent != nil
        }
        guard !candidates.isEmpty else { return nil }

        if let unused = candidates
            .filter({ $0.isUnusedSinceCurrentFiveHourReset(now: now) })
            .sorted(by: { lhs, rhs in
                let lhsReset = lhs.fiveHourWindow?.resetsAt ?? .distantFuture
                let rhsReset = rhs.fiveHourWindow?.resetsAt ?? .distantFuture
                if lhsReset != rhsReset { return lhsReset < rhsReset }
                return lhs.stableRotationSortKey < rhs.stableRotationSortKey
            })
            .first {
            return unused
        }

        return candidates.sorted(by: { lhs, rhs in
            let lhsRemaining = lhs.fiveHourWindow?.remainingPercent ?? -.infinity
            let rhsRemaining = rhs.fiveHourWindow?.remainingPercent ?? -.infinity
            if lhsRemaining != rhsRemaining { return lhsRemaining > rhsRemaining }
            return lhs.stableRotationSortKey < rhs.stableRotationSortKey
        }).first
    }
}

private extension UsageAccount {
    var stableRotationSortKey: String {
        "\(displayName.lowercased())|\(id)"
    }

    func isUnusedSinceCurrentFiveHourReset(now: Date) -> Bool {
        guard let window = fiveHourWindow,
              let resetsAt = window.resetsAt,
              resetsAt >= now
        else {
            return false
        }

        let windowStart = resetsAt.addingTimeInterval(TimeInterval(-window.windowMinutes * 60))
        guard let lastUpdated else { return false }
        return lastUpdated < windowStart
    }
}

enum CodexAppRestartResult: Equatable {
    case restarted
    case skippedWorkRunning
}

struct CodexAppRestarter {
    var activityDetector: @Sendable () -> Bool = {
        CodexWorkActivityDetector().hasRunningCodexWork()
    }
    var restartCodexApp: @Sendable () -> Void = {
        AccountLoginLauncher.forceRestartCodexApp()
    }

    func restartIfNoWorkIsRunning() -> CodexAppRestartResult {
        guard !activityDetector() else { return .skippedWorkRunning }
        restartCodexApp()
        return .restarted
    }
}

struct CodexWorkActivityDetector {
    var processLines: @Sendable () -> [String] = {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "command="]
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output.split(separator: "\n").map(String.init)
    }

    func hasRunningCodexWork() -> Bool {
        processLines().contains { line in
            let command = line.lowercased()
            guard command.range(of: #"(^|[/\s])codex($|\s)"#, options: .regularExpression) != nil else {
                return false
            }
            if command.contains("/codex.app/") || command.contains(".app/contents/macos/codex") {
                return false
            }
            if command.contains("agentbar") {
                return false
            }
            return true
        }
    }
}
