import CryptoKit
import Foundation

struct CodexSessionMetricsReader {
    var fileManager: FileManager = .default

    private static let sessionMetricsCache = CodexSessionMetricsCache()
    private static let readChunkBytes = 64 * 1024

    func read(
        root: URL,
        maximumSessionFileBytes: Int,
        maximumSessionFiles: Int,
        cacheDirectory: URL? = nil,
        prunesCache: Bool = true
    ) -> CodexSessionMetrics {
        var accessIssueNote: String?
        do {
            let values = try root.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                return CodexSessionMetrics(eventCount: 0, tokenTotals: .zero, points: [], latestFiveHour: nil, latestWeekly: nil, latestRateLimitAt: nil)
            }
        } catch {
            if let note = LocalFileAccessWarning.codexNote(for: error, path: root.path) {
                var empty = CodexSessionMetrics(eventCount: 0, tokenTotals: .zero, points: [], latestFiveHour: nil, latestWeekly: nil, latestRateLimitAt: nil)
                empty.accessIssueNote = note
                return empty
            }
        }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                accessIssueNote = accessIssueNote ?? LocalFileAccessWarning.codexNote(for: error, path: url.path)
                return true
            }
        ) else {
            var empty = CodexSessionMetrics(eventCount: 0, tokenTotals: .zero, points: [], latestFiveHour: nil, latestWeekly: nil, latestRateLimitAt: nil)
            empty.accessIssueNote = accessIssueNote
            return empty
        }

        var aggregate = CodexSessionMetrics(eventCount: 0, tokenTotals: .zero, points: [], latestFiveHour: nil, latestWeekly: nil, latestRateLimitAt: nil)
        var candidates: [CodexSessionFileCandidate] = []
        var seenPoints = Set<CodexUsagePointIdentity>()
        var taskIndexes: [String: Int] = [:]

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            guard !Task.isCancelled else { break }
            do {
                guard let fileSignature = try CodexSessionFileSignature(
                    fileURL: fileURL,
                    fileManager: fileManager
                ) else { continue }
                candidates.append(CodexSessionFileCandidate(url: fileURL, signature: fileSignature))
            } catch {
                accessIssueNote = accessIssueNote ?? LocalFileAccessWarning.codexNote(for: error, path: fileURL.path)
            }
        }

        let selectedCandidates = candidates
            .sorted { lhs, rhs in
                if lhs.signature.modifiedAt != rhs.signature.modifiedAt {
                    return lhs.signature.modifiedAt > rhs.signature.modifiedAt
                }
                return lhs.url.path > rhs.url.path
            }
            .prefix(maximumSessionFiles)
        aggregate.skippedSessionFileCapCount = max(0, candidates.count - selectedCandidates.count)
        let livePaths = Set(selectedCandidates.map(\.url.path))

        for candidate in selectedCandidates {
            guard !Task.isCancelled else { break }
            guard candidate.signature.size <= UInt64(CodexUsageReader.maximumReasonableSessionFileBytes) else {
                aggregate.skippedOversizedSessionFileCount += 1
                continue
            }
            do {
                let metrics = try metrics(for: candidate, cacheDirectory: cacheDirectory)
                if candidate.signature.size > UInt64(maximumSessionFileBytes),
                   metrics.eventCount == 0,
                   metrics.latestRateLimitAt == nil {
                    aggregate.skippedOversizedSessionFileCount += 1
                    continue
                }
                aggregate.merge(metrics, seenPoints: &seenPoints, taskIndexes: &taskIndexes)
            } catch {
                accessIssueNote = accessIssueNote ??
                    LocalFileAccessWarning.codexNote(for: error, path: candidate.url.path)
            }
        }
        if prunesCache {
            Self.sessionMetricsCache.retain(paths: livePaths, cacheDirectory: cacheDirectory)
        }

        aggregate.accessIssueNote = accessIssueNote
        return aggregate
    }

    static func resetCacheForTesting() {
        sessionMetricsCache.removeAll()
    }

    private func metrics(
        for candidate: CodexSessionFileCandidate,
        cacheDirectory: URL?
    ) throws -> CodexSessionMetrics {
        let path = candidate.url.path
        let signature = candidate.signature
        let cachedIndex = Self.sessionMetricsCache.index(for: path, cacheDirectory: cacheDirectory)

        if let cachedIndex,
           cachedIndex.fileID == signature.fileID,
           cachedIndex.parserVersion == CodexUsageReader.sessionParserVersion,
           cachedIndex.modifiedAt == signature.modifiedAt,
           cachedIndex.size == signature.size,
           cachedIndex.parsedOffset == signature.size {
            return cachedIndex.aggregate.metrics
        }

        let resumableIndex: CodexSessionFileIndex? = cachedIndex.flatMap { index in
            guard index.fileID == signature.fileID,
                  index.parserVersion == CodexUsageReader.sessionParserVersion,
                  index.parsedOffset <= signature.size,
                  (signature.size > index.size ||
                    signature.size == index.size && signature.modifiedAt == index.modifiedAt)
            else { return nil }
            return index
        }
        var aggregate = resumableIndex?.aggregate ?? CodexSessionParseAggregate()
        let parsedOffset = try parse(
            candidate.url,
            through: signature.size,
            from: resumableIndex?.parsedOffset ?? 0,
            aggregate: &aggregate
        )
        aggregate.finalizeTasks()
        aggregate.metrics = RepositoryIdentityResolver.resolve(in: aggregate.metrics, fileManager: fileManager)

        let index = CodexSessionFileIndex(
            fileID: signature.fileID,
            path: path,
            modifiedAt: signature.modifiedAt,
            size: signature.size,
            parsedOffset: parsedOffset,
            parserVersion: CodexUsageReader.sessionParserVersion,
            aggregate: aggregate
        )
        Self.sessionMetricsCache.store(index, cacheDirectory: cacheDirectory)
        return aggregate.metrics
    }

    private func parse(
        _ fileURL: URL,
        through endOffset: UInt64,
        from startOffset: UInt64,
        aggregate: inout CodexSessionParseAggregate
    ) throws -> UInt64 {
        guard startOffset < endOffset else { return startOffset }
        guard !aggregate.reachedMalformedLineLimit(CodexUsageReader.maximumMalformedSessionLines) else {
            return endOffset
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: startOffset)

        let context = CodexSessionParserContext()
        var committedOffset = startOffset
        var streamOffset = startOffset
        var buffer = Data()
        var discardedLineBytes: UInt64 = 0

        while streamOffset < endOffset,
              !Task.isCancelled,
              !aggregate.reachedMalformedLineLimit(CodexUsageReader.maximumMalformedSessionLines) {
            let requestedBytes = Int(min(UInt64(Self.readChunkBytes), endOffset - streamOffset))
            guard let chunk = try handle.read(upToCount: requestedBytes), !chunk.isEmpty else { break }
            buffer.append(chunk)
            streamOffset += UInt64(chunk.count)

            var lineStart = buffer.startIndex
            while !Task.isCancelled,
                  !aggregate.reachedMalformedLineLimit(CodexUsageReader.maximumMalformedSessionLines),
                  let newline = buffer[lineStart...].firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[lineStart..<newline]
                let consumedBytes = discardedLineBytes + UInt64(line.count) + 1
                if discardedLineBytes > 0 || line.count > CodexUsageReader.maximumSessionLineBytes {
                    aggregate.skipOversizedLine()
                } else {
                    autoreleasepool {
                        _ = aggregate.consumeLine(
                            Data(line),
                            sessionID: fileURL.deletingPathExtension().lastPathComponent,
                            projectName: nil,
                            sourceFile: fileURL.path,
                            maximumPayloadBytes: CodexUsageReader.maximumSessionPayloadBytes,
                            maximumMalformedLines: CodexUsageReader.maximumMalformedSessionLines,
                            context: context
                        )
                    }
                }
                committedOffset += consumedBytes
                discardedLineBytes = 0
                lineStart = buffer.index(after: newline)
            }
            if lineStart > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<lineStart)
            }
            if buffer.count > CodexUsageReader.maximumSessionLineBytes {
                discardedLineBytes += UInt64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
            }
        }

        if aggregate.reachedMalformedLineLimit(CodexUsageReader.maximumMalformedSessionLines) {
            return endOffset
        }
        guard !Task.isCancelled else { return committedOffset }

        if discardedLineBytes > 0 {
            aggregate.skipOversizedLine()
            return committedOffset + discardedLineBytes + UInt64(buffer.count)
        }
        guard !buffer.isEmpty else { return committedOffset }

        var trailingAggregate = aggregate
        let trailingOutcome = autoreleasepool {
            trailingAggregate.consumeLine(
                buffer,
                sessionID: fileURL.deletingPathExtension().lastPathComponent,
                projectName: nil,
                sourceFile: fileURL.path,
                maximumPayloadBytes: CodexUsageReader.maximumSessionPayloadBytes,
                maximumMalformedLines: CodexUsageReader.maximumMalformedSessionLines,
                context: context
            )
        }
        guard trailingOutcome != .malformed else { return committedOffset }
        aggregate = trailingAggregate
        return committedOffset + UInt64(buffer.count)
    }
}

private struct CodexSessionFileCandidate {
    var url: URL
    var signature: CodexSessionFileSignature
}

private struct CodexSessionFileSignature {
    var fileID: Data
    var modifiedAt: Date
    var size: UInt64

    init?(fileURL: URL, fileManager: FileManager) throws {
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let modifiedAt = attributes[.modificationDate] as? Date,
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let systemNumber = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        else { return nil }
        fileID = Data("\(systemNumber):\(fileNumber)".utf8)
        self.modifiedAt = modifiedAt
        self.size = size
    }
}

private struct CodexSessionFileIndex: Codable {
    let fileID: Data
    let path: String
    let modifiedAt: Date
    let size: UInt64
    let parsedOffset: UInt64
    let parserVersion: Int
    let aggregate: CodexSessionParseAggregate
}

private final class CodexSessionMetricsCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: CodexSessionFileIndex] = [:]

    func index(
        for path: String,
        cacheDirectory: URL?
    ) -> CodexSessionFileIndex? {
        lock.lock()
        let memoryIndex = entries[path]
        lock.unlock()
        if let memoryIndex,
           memoryIndex.parserVersion == CodexUsageReader.sessionParserVersion {
            return memoryIndex
        }

        guard let cacheDirectory,
              let data = try? Data(contentsOf: cacheFileURL(for: path, in: cacheDirectory)),
              let index = try? JSONDecoder().decode(CodexSessionFileIndex.self, from: data),
              index.parserVersion == CodexUsageReader.sessionParserVersion,
              index.path == path
        else { return nil }

        lock.lock()
        entries[path] = index
        lock.unlock()
        return index
    }

    func store(
        _ index: CodexSessionFileIndex,
        cacheDirectory: URL?
    ) {
        lock.lock()
        entries[index.path] = index
        lock.unlock()

        guard let cacheDirectory else { return }
        guard let data = try? JSONEncoder().encode(index) else { return }
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cacheDirectory.path)
            let cacheURL = cacheFileURL(for: index.path, in: cacheDirectory)
            try data.write(to: cacheURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
        } catch {
            // The cache is an optimization; source JSONL remains authoritative.
        }
    }

    func retain(paths: Set<String>, cacheDirectory: URL?) {
        lock.lock()
        entries = entries.filter { paths.contains($0.key) }
        lock.unlock()

        guard let cacheDirectory,
              let cachedFiles = try? FileManager.default.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              )
        else { return }
        let liveFileNames = Set(paths.map { cacheFileURL(for: $0, in: cacheDirectory).lastPathComponent })
        for cachedFile in cachedFiles where !liveFileNames.contains(cachedFile.lastPathComponent) {
            try? FileManager.default.removeItem(at: cachedFile)
        }
    }

    func removeAll() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    private func cacheFileURL(for path: String, in directory: URL) -> URL {
        let digest = SHA256.hash(data: Data(path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appending(path: "\(digest).json")
    }
}

private extension CodexSessionMetrics {
    mutating func merge(
        _ metrics: CodexSessionMetrics,
        seenPoints: inout Set<CodexUsagePointIdentity>,
        taskIndexes: inout [String: Int]
    ) {
        for point in metrics.points {
            guard seenPoints.insert(CodexUsagePointIdentity(point: point)).inserted else { continue }
            points.append(point)
            eventCount += 1
            tokenTotals = tokenTotals + point.tokens
        }
        for task in metrics.tasks {
            if let index = taskIndexes[task.id] {
                if task.isMoreComplete(than: tasks[index]) {
                    tasks[index] = task
                }
            } else {
                taskIndexes[task.id] = tasks.count
                tasks.append(task)
            }
        }
        if let latestRateLimitAt = metrics.latestRateLimitAt,
           self.latestRateLimitAt == nil || latestRateLimitAt >= (self.latestRateLimitAt ?? .distantPast) {
            latestFiveHour = metrics.latestFiveHour
            latestWeekly = metrics.latestWeekly
            latestResetCredits = metrics.latestResetCredits
            self.latestRateLimitAt = latestRateLimitAt
        }
    }
}

private struct CodexUsagePointIdentity: Hashable {
    var taskID: String?
    var cumulativeTokens: TokenTotals?
    var fallbackDate: Date?
    var model: String
    var tokens: TokenTotals
    var cwd: String?
    var reasoningEffort: String?
    var initiator: String?

    init(point: UsagePoint) {
        taskID = point.taskID
        cumulativeTokens = point.cumulativeTokens
        fallbackDate = point.taskID != nil && point.cumulativeTokens != nil ? nil : point.date
        model = point.model
        tokens = point.tokens
        cwd = point.cwd
        reasoningEffort = point.reasoningEffort
        initiator = point.initiator
    }
}

private extension AgentTask {
    func isMoreComplete(than other: AgentTask) -> Bool {
        if terminalState == .completed, other.terminalState != .completed { return true }
        if terminalState == .interrupted, other.terminalState == nil { return true }
        if terminalState == nil, other.terminalState != nil { return false }
        let timingCount = [reportedDurationSeconds, validTimeToFirstTokenMilliseconds]
            .compactMap { $0 }
            .count
        let otherTimingCount = [other.reportedDurationSeconds, other.validTimeToFirstTokenMilliseconds]
            .compactMap { $0 }
            .count
        if timingCount != otherTimingCount { return timingCount > otherTimingCount }
        if lastActivityAt != other.lastActivityAt { return lastActivityAt > other.lastActivityAt }
        return tokens.total > other.tokens.total
    }
}
