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
                && !account.needsLogin
                && account.supportsAccountSwitching
                && account.fiveHourWindow?.remainingPercent != nil
        }
        guard !candidates.isEmpty else { return nil }

        if let resetCreditAccount = candidates
            .filter({ ($0.resetCredits?.visibleCount ?? 0) > 0 })
            .sorted(by: { lhs, rhs in
                let lhsCredits = lhs.resetCredits?.visibleCount ?? 0
                let rhsCredits = rhs.resetCredits?.visibleCount ?? 0
                if lhsCredits != rhsCredits { return lhsCredits > rhsCredits }
                let lhsRemaining = lhs.fiveHourWindow?.remainingPercent ?? -.infinity
                let rhsRemaining = rhs.fiveHourWindow?.remainingPercent ?? -.infinity
                if lhsRemaining != rhsRemaining { return lhsRemaining > rhsRemaining }
                return lhs.stableRotationSortKey < rhs.stableRotationSortKey
            })
            .first {
            return resetCreditAccount
        }

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
    case skippedActivityUnknown
    case restartFailed
}

struct CodexAppRestarter {
    var activityDetector: @Sendable () -> Bool? = {
        CodexWorkActivityDetector().hasRunningCodexWork()
    }
    var restartCodexApp: @Sendable () -> Bool = {
        AccountLoginLauncher.forceRestartCodexApp()
    }

    func restartIfNoWorkIsRunning() -> CodexAppRestartResult {
        guard let hasRunningWork = activityDetector() else { return .skippedActivityUnknown }
        guard !hasRunningWork else { return .skippedWorkRunning }
        return restartCodexApp() ? .restarted : .restartFailed
    }
}

struct CodexWorkActivityDetector {
    var processLines: @Sendable () -> [String]? = {
        do {
            let result = try AsyncProcessRunner.runBlocking(
                executableURL: URL(fileURLWithPath: "/bin/ps"),
                arguments: ["-axo", "command="],
                maximumOutputBytes: 8 * 1_048_576,
                timeout: 5
            )
            guard result.exitStatus == 0,
                  !result.timedOut,
                  !result.wasCancelled,
                  !result.stdoutTruncated
            else { return nil }
            guard let output = String(data: result.stdout, encoding: .utf8) else { return nil }
            return output.split(separator: "\n").map(String.init)
        } catch {
            return nil
        }
    }

    func hasRunningCodexWork() -> Bool? {
        processLines()?.contains { line in
            let command = line.lowercased()
            if command.contains("/chatgpt.app/") || command.contains(".app/contents/macos/chatgpt")
                || command.contains("/codex.app/") || command.contains(".app/contents/macos/codex") {
                return false
            }
            guard command.range(of: #"(^|[/\s])codex($|\s)"#, options: .regularExpression) != nil else {
                return false
            }
            if command.contains("agentbar") {
                return false
            }
            return true
        }
    }
}
