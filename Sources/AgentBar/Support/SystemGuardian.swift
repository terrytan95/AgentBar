import Foundation

struct GuardianProcessRow: Equatable, Identifiable, Sendable {
    var id: Int32 { pid }
    var pid: Int32
    var name: String
    var cpuPercent: Double?
    var memoryBytes: UInt64?
    var command: String

    var redactedCommand: String {
        Self.redactedCommand(command)
    }

    var severity: InsightSeverity {
        guard let cpuPercent else { return .ok }
        if cpuPercent >= 80 { return .critical }
        if cpuPercent >= 25 { return .warning }
        return .ok
    }

    static func redactedCommand(_ command: String) -> String {
        let patterns = [
            #"(?i)(access_token|refresh_token|id_token|cookie|secret|private_key)(=|\s+)(\"[^\"]*\"|'[^']*'|[^\s]+)"#,
            #"(?i)(bearer\s+)([^\s]+)"#
        ]
        var redacted = command
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(redacted.startIndex..<redacted.endIndex, in: redacted)
            if pattern.localizedCaseInsensitiveContains("bearer") {
                redacted = regex.stringByReplacingMatches(in: redacted, range: range, withTemplate: "$1[redacted]")
            } else {
                redacted = regex.stringByReplacingMatches(in: redacted, range: range, withTemplate: "$1$2[redacted]")
            }
        }
        return redacted
    }
}

struct SessionStoreHealth: Equatable, Sendable {
    var path: String
    var exists: Bool
    var totalBytes: UInt64
    var jsonlFileCount: Int
    var recentFileCount: Int
    var oldFileCount: Int
    var largeFileCount: Int
    var latestWriteAt: Date?
    var severity: InsightSeverity
    var summary: String

    static func missing(path: String) -> SessionStoreHealth {
        SessionStoreHealth(
            path: path,
            exists: false,
            totalBytes: 0,
            jsonlFileCount: 0,
            recentFileCount: 0,
            oldFileCount: 0,
            largeFileCount: 0,
            latestWriteAt: nil,
            severity: .warning,
            summary: "Codex session store not found."
        )
    }

    static func unreadable(path: String, error: Error) -> SessionStoreHealth {
        SessionStoreHealth(
            path: path,
            exists: true,
            totalBytes: 0,
            jsonlFileCount: 0,
            recentFileCount: 0,
            oldFileCount: 0,
            largeFileCount: 0,
            latestWriteAt: nil,
            severity: .critical,
            summary: "Codex session store could not be read: \(error.localizedDescription)"
        )
    }

    static func classify(
        path: String,
        totalBytes: UInt64,
        jsonlFileCount: Int,
        recentFileCount: Int,
        oldFileCount: Int,
        largeFileCount: Int,
        latestWriteAt: Date?
    ) -> SessionStoreHealth {
        let severity: InsightSeverity
        if totalBytes >= 1_000_000_000 || oldFileCount >= 50 || largeFileCount >= 10 {
            severity = .critical
        } else if totalBytes >= 250_000_000 || oldFileCount >= 20 || largeFileCount > 0 {
            severity = .warning
        } else {
            severity = .ok
        }

        let size = byteCount(totalBytes)
        let summary: String
        switch severity {
        case .critical:
            summary = "High storage pressure: \(size), \(jsonlFileCount) JSONL files, \(oldFileCount) old files."
        case .warning:
            summary = "Growing session store: \(size), \(jsonlFileCount) JSONL files."
        case .ok:
            summary = "Session store looks healthy: \(size), \(jsonlFileCount) JSONL files."
        }

        return SessionStoreHealth(
            path: path,
            exists: true,
            totalBytes: totalBytes,
            jsonlFileCount: jsonlFileCount,
            recentFileCount: recentFileCount,
            oldFileCount: oldFileCount,
            largeFileCount: largeFileCount,
            latestWriteAt: latestWriteAt,
            severity: severity,
            summary: summary
        )
    }

    static func byteCount(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(clamping: bytes))
    }
}

struct SystemGuardianSnapshot: Equatable, Sendable {
    var capturedAt: Date
    var processes: [GuardianProcessRow]
    var sessionStore: SessionStoreHealth
    var dataSourceHealth: DataSourceHealthSummary
}

enum GuardianAction: Equatable, Sendable {
    case refreshUsage
    case openCodexLogin
    case openClaudeLogin
    case openSessionFolder
    case openActivityMonitor
    case copyDiagnostics
    case recommendationOnly
}

struct GuardianRecommendation: Equatable, Identifiable, Sendable {
    var id: String { title + detail }
    var severity: InsightSeverity
    var title: String
    var detail: String
    var action: GuardianAction
    var requiresConfirmation: Bool
}

enum GuardianRecommendationEngine {
    static func recommendations(for snapshot: SystemGuardianSnapshot) -> [GuardianRecommendation] {
        var recommendations: [GuardianRecommendation] = []

        if snapshot.processes.contains(where: { $0.severity != .ok }) {
            recommendations.append(
                GuardianRecommendation(
                    severity: .warning,
                    title: "Inspect CPU activity",
                    detail: "One or more agent processes are using elevated CPU. Open Activity Monitor before terminating anything.",
                    action: .openActivityMonitor,
                    requiresConfirmation: false
                )
            )
        }

        if snapshot.processes.count > 6 {
            recommendations.append(
                GuardianRecommendation(
                    severity: .warning,
                    title: "Review duplicate agent processes",
                    detail: "Several Codex or Claude-related processes are running. Verify which sessions are active before stopping helpers.",
                    action: .recommendationOnly,
                    requiresConfirmation: true
                )
            )
        }

        if snapshot.sessionStore.severity != .ok {
            recommendations.append(
                GuardianRecommendation(
                    severity: snapshot.sessionStore.severity,
                    title: "Review Codex session storage",
                    detail: snapshot.sessionStore.summary + " Compaction or cleanup requires explicit confirmation.",
                    action: .openSessionFolder,
                    requiresConfirmation: true
                )
            )
        }

        if snapshot.dataSourceHealth.issueCount > 0 {
            recommendations.append(
                GuardianRecommendation(
                    severity: .warning,
                    title: "Refresh data source health",
                    detail: "\(snapshot.dataSourceHealth.issueCount) data source issue\(snapshot.dataSourceHealth.issueCount == 1 ? "" : "s") detected. Refresh usage or reopen the login flow.",
                    action: .refreshUsage,
                    requiresConfirmation: false
                )
            )
        }

        if recommendations.isEmpty {
            recommendations.append(
                GuardianRecommendation(
                    severity: .ok,
                    title: "System looks healthy",
                    detail: "No elevated process, storage, or data-source issues were detected in this snapshot.",
                    action: .copyDiagnostics,
                    requiresConfirmation: false
                )
            )
        }

        return recommendations
    }

    static func overallSeverity(for snapshot: SystemGuardianSnapshot) -> InsightSeverity {
        let severities = recommendations(for: snapshot).map(\.severity) + [snapshot.sessionStore.severity] + snapshot.processes.map(\.severity)
        if severities.contains(.critical) { return .critical }
        if severities.contains(.warning) { return .warning }
        return .ok
    }
}

struct SystemGuardianReader {
    var homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    var now: () -> Date = Date.init
    var processOutput: () throws -> String = SystemGuardianReader.defaultProcessOutput
    var fileManager: FileManager = .default

    func snapshot(dataSourceHealth: DataSourceHealthSummary) -> SystemGuardianSnapshot {
        SystemGuardianSnapshot(
            capturedAt: now(),
            processes: readProcesses(),
            sessionStore: readSessionStore(),
            dataSourceHealth: dataSourceHealth
        )
    }

    func readProcesses() -> [GuardianProcessRow] {
        guard let output = try? processOutput() else { return [] }
        return output
            .split(separator: "\n")
            .compactMap(parseProcessLine)
            .filter { row in
                let lower = "\(row.name) \(row.command)".lowercased()
                return lower.contains("agentbar") || lower.contains("codex") || lower.contains("claude")
            }
            .sorted { lhs, rhs in
                (lhs.cpuPercent ?? 0, lhs.name) > (rhs.cpuPercent ?? 0, rhs.name)
            }
    }

    func readSessionStore() -> SessionStoreHealth {
        let sessionsURL = homeDirectory.appending(path: ".codex/sessions")
        let path = sessionsURL.path
        guard fileManager.fileExists(atPath: path) else {
            return .missing(path: path)
        }

        guard let enumerator = fileManager.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .missing(path: path)
        }

        var totalBytes: UInt64 = 0
        var jsonlFileCount = 0
        var recentFileCount = 0
        var oldFileCount = 0
        var largeFileCount = 0
        var latestWriteAt: Date?
        let recentCutoff = now().addingTimeInterval(-24 * 60 * 60)
        let oldCutoff = now().addingTimeInterval(-14 * 24 * 60 * 60)

        for case let fileURL as URL in enumerator {
            do {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
                guard values.isRegularFile == true else { continue }
                let size = UInt64(max(0, values.fileSize ?? 0))
                totalBytes += size

                guard fileURL.pathExtension == "jsonl" else { continue }
                jsonlFileCount += 1
                if size >= 25_000_000 {
                    largeFileCount += 1
                }
                if let modified = values.contentModificationDate {
                    if modified >= recentCutoff {
                        recentFileCount += 1
                    }
                    if modified < oldCutoff {
                        oldFileCount += 1
                    }
                    if latestWriteAt == nil || modified > latestWriteAt! {
                        latestWriteAt = modified
                    }
                }
            } catch {
                return .unreadable(path: path, error: error)
            }
        }

        return .classify(
            path: path,
            totalBytes: totalBytes,
            jsonlFileCount: jsonlFileCount,
            recentFileCount: recentFileCount,
            oldFileCount: oldFileCount,
            largeFileCount: largeFileCount,
            latestWriteAt: latestWriteAt
        )
    }

    private func parseProcessLine(_ line: Substring) -> GuardianProcessRow? {
        let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
        guard parts.count >= 4,
              let pid = Int32(parts[0]),
              let cpu = Double(parts[1])
        else { return nil }
        let rssKilobytes = UInt64(parts[2]) ?? 0
        let commandName = String(parts[3])
        let command = parts.count >= 5 ? String(parts[4]) : commandName
        let name = URL(fileURLWithPath: commandName).lastPathComponent.isEmpty
            ? commandName
            : URL(fileURLWithPath: commandName).lastPathComponent
        return GuardianProcessRow(
            pid: pid,
            name: name,
            cpuPercent: cpu,
            memoryBytes: rssKilobytes * 1024,
            command: command
        )
    }

    private static func defaultProcessOutput() throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,pcpu=,rss=,comm=,args="]
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
