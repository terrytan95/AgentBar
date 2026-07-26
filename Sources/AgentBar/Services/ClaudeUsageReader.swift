import Foundation

enum ClaudeUsageReader {
    private static let maximumSessionFiles = 1_000
    private static let maximumSessionFileBytes = 512 * 1024 * 1024
    private static let maximumSessionLineBytes = 1024 * 1024
    private static let readChunkBytes = 64 * 1024

    static func discover(homeDirectory: URL) -> UsageSnapshot {
        let claudeCliDirectory = homeDirectory.appending(path: ".claude")
        let projectsDirectory = claudeCliDirectory.appending(path: "projects")
        let desktopDirectory = homeDirectory.appending(path: "Library/Application Support/Claude")
        let now = Date()

        guard FileManager.default.fileExists(atPath: claudeCliDirectory.path) else {
            let source = FileManager.default.fileExists(atPath: desktopDirectory.path)
                ? "Claude Desktop found, Claude Code local usage records not found."
                : "Claude Code not found on this Mac."
            return snapshot(status: .unavailable, points: [], note: source, refreshedAt: now)
        }

        let discovery = sessionFiles(in: projectsDirectory)
        var accessIssueNote = discovery.accessIssueNote
        let candidates = discovery.files
        var points: [UsagePoint] = []
        var seenMessageIDs = Set<String>()

        for candidate in candidates.prefix(maximumSessionFiles) where candidate.size <= maximumSessionFileBytes {
            do {
                try parse(
                    candidate.url,
                    projectsDirectory: projectsDirectory,
                    points: &points,
                    seenMessageIDs: &seenMessageIDs
                )
            } catch {
                accessIssueNote = accessIssueNote
                    ?? LocalFileAccessWarning.claudeNote(for: error, path: candidate.url.path)
            }
        }

        if let accessIssueNote {
            return snapshot(status: .needsAuthorization, points: points, note: accessIssueNote, refreshedAt: now)
        }
        let note = points.isEmpty
            ? "Claude Code local usage records were not found."
            : "Read-only local Claude Code session usage; prompt content and credentials are not extracted or retained."
        return snapshot(
            status: points.isEmpty ? .unavailable : .live,
            points: points.sorted { $0.date < $1.date },
            note: note,
            refreshedAt: now
        )
    }

    private static func sessionFiles(
        in projectsDirectory: URL
    ) -> (files: [ClaudeSessionFile], accessIssueNote: String?) {
        var accessIssueNote: String?
        guard let enumerator = FileManager.default.enumerator(
            at: projectsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                accessIssueNote = accessIssueNote
                    ?? LocalFileAccessWarning.claudeNote(for: error, path: url.path)
                return true
            }
        ) else {
            return ([], accessIssueNote)
        }

        var files: [ClaudeSessionFile] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
            ), values.isRegularFile == true else { continue }
            files.append(
                ClaudeSessionFile(
                    url: url,
                    size: values.fileSize ?? 0,
                    modifiedAt: values.contentModificationDate ?? .distantPast
                )
            )
        }
        let sortedFiles = files.sorted {
            $0.modifiedAt == $1.modifiedAt ? $0.url.path > $1.url.path : $0.modifiedAt > $1.modifiedAt
        }
        return (sortedFiles, accessIssueNote)
    }

    private static func parse(
        _ fileURL: URL,
        projectsDirectory: URL,
        points: inout [UsagePoint],
        seenMessageIDs: inout Set<String>
    ) throws {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var buffer = Data()
        var discardingOversizedLine = false
        var lineNumber = 0
        let decoder = JSONDecoder()
        let dateParser = ISO8601TimestampParser()

        // ponytail: bounded streaming has no incremental cache; add one only if refresh profiling requires it.
        while let chunk = try handle.read(upToCount: readChunkBytes), !chunk.isEmpty {
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                lineNumber += 1
                if discardingOversizedLine {
                    discardingOversizedLine = false
                    continue
                }
                consume(
                    line,
                    lineNumber: lineNumber,
                    fileURL: fileURL,
                    projectsDirectory: projectsDirectory,
                    decoder: decoder,
                    dateParser: dateParser,
                    points: &points,
                    seenMessageIDs: &seenMessageIDs
                )
            }
            if buffer.count > maximumSessionLineBytes {
                buffer.removeAll(keepingCapacity: true)
                discardingOversizedLine = true
            }
        }

        if !discardingOversizedLine, !buffer.isEmpty {
            consume(
                buffer[...],
                lineNumber: lineNumber + 1,
                fileURL: fileURL,
                projectsDirectory: projectsDirectory,
                decoder: decoder,
                dateParser: dateParser,
                points: &points,
                seenMessageIDs: &seenMessageIDs
            )
        }
    }

    private static func consume(
        _ line: Data.SubSequence,
        lineNumber: Int,
        fileURL: URL,
        projectsDirectory: URL,
        decoder: JSONDecoder,
        dateParser: ISO8601TimestampParser,
        points: inout [UsagePoint],
        seenMessageIDs: inout Set<String>
    ) {
        guard line.count <= maximumSessionLineBytes,
              let event = try? decoder.decode(ClaudeSessionEvent.self, from: Data(line)),
              event.type == "assistant",
              let message = event.message,
              let usage = message.usage,
              let timestamp = event.timestamp,
              let date = dateParser.date(from: timestamp),
              let tokens = usage.tokens,
              tokens.total > 0
        else { return }

        if let messageID = message.id, !seenMessageIDs.insert(messageID).inserted {
            return
        }

        let model = Pricing.normalize(model: message.model ?? "Claude local")
        let projectName = event.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? projectDirectoryName(for: fileURL, projectsDirectory: projectsDirectory)
        points.append(
            UsagePoint(
                service: .claudeCode,
                model: model,
                date: date,
                tokens: tokens,
                estimatedCostUSD: Pricing.cost(
                    model: model,
                    input: usage.inputTokens,
                    output: usage.outputTokens,
                    cacheRead: usage.cacheReadInputTokens,
                    cacheCreation: usage.cacheCreationInputTokens
                ),
                sessionID: event.sessionID,
                projectName: projectName,
                cwd: event.cwd,
                sourceFile: fileURL.path,
                sourceLine: lineNumber
            )
        )
    }

    private static func projectDirectoryName(for fileURL: URL, projectsDirectory: URL) -> String? {
        let relativePath = fileURL.path.dropFirst(projectsDirectory.path.count)
        return relativePath.split(separator: "/").first.map(String.init)
    }

    private static func snapshot(
        status: DataSourceStatus,
        points: [UsagePoint],
        note: String,
        refreshedAt: Date
    ) -> UsageSnapshot {
        UsageSnapshot(
            service: .claudeCode,
            status: status,
            accounts: [],
            points: points,
            securityNotes: [note],
            refreshedAt: refreshedAt,
            pricingFingerprint: Pricing.fingerprint
        )
    }
}

private struct ClaudeSessionFile {
    var url: URL
    var size: Int
    var modifiedAt: Date
}

private struct ClaudeSessionEvent: Decodable {
    var type: String?
    var sessionID: String?
    var timestamp: String?
    var cwd: String?
    var message: ClaudeSessionMessage?

    enum CodingKeys: String, CodingKey {
        case type
        case sessionID = "sessionId"
        case legacySessionID = "session_id"
        case timestamp
        case cwd
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
            ?? container.decodeIfPresent(String.self, forKey: .legacySessionID)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        message = try container.decodeIfPresent(ClaudeSessionMessage.self, forKey: .message)
    }
}

private struct ClaudeSessionMessage: Decodable {
    var id: String?
    var model: String?
    var usage: ClaudeSessionUsage?
}

private struct ClaudeSessionUsage: Decodable {
    var inputTokens: Int
    var cacheCreationInputTokens: Int
    var cacheReadInputTokens: Int
    var outputTokens: Int

    var tokens: TokenTotals? {
        guard inputTokens >= 0,
              cacheCreationInputTokens >= 0,
              cacheReadInputTokens >= 0,
              outputTokens >= 0,
              let totalInput = safeSum([inputTokens, cacheCreationInputTokens, cacheReadInputTokens]),
              let total = safeSum([totalInput, outputTokens])
        else { return nil }
        return TokenTotals(
            input: totalInput,
            cachedInput: cacheReadInputTokens,
            output: outputTokens,
            reasoningOutput: 0,
            total: total
        )
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case outputTokens = "output_tokens"
    }
}

private func safeSum(_ values: [Int]) -> Int? {
    var total = 0
    for value in values {
        let result = total.addingReportingOverflow(value)
        guard !result.overflow else { return nil }
        total = result.partialValue
    }
    return total
}
