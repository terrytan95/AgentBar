import CryptoKit
import Foundation

struct CodexSessionMetricsReader {
    var fileManager: FileManager = .default

    private static let sessionMetricsCache = CodexSessionMetricsCache()

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
            do {
                guard let fileSignature = try CodexSessionFileSignature(fileURL: fileURL) else { continue }
                candidates.append(CodexSessionFileCandidate(url: fileURL, signature: fileSignature))
            } catch {
                accessIssueNote = accessIssueNote ?? LocalFileAccessWarning.codexNote(for: error, path: fileURL.path)
            }
        }

        let selectedCandidates = candidates
            .sorted { lhs, rhs in
                let lhsDate = lhs.signature.modifiedAt ?? .distantPast
                let rhsDate = rhs.signature.modifiedAt ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.url.path > rhs.url.path
            }
            .prefix(maximumSessionFiles)
        aggregate.skippedSessionFileCapCount = max(0, candidates.count - selectedCandidates.count)
        let livePaths = Set(selectedCandidates.map(\.url.path))

        for candidate in selectedCandidates {
            let fileURL = candidate.url
            let signature = candidate.signature
            let path = fileURL.path
            let metrics: CodexSessionMetrics
            if let cachedMetrics = Self.sessionMetricsCache.metrics(
                for: path,
                signature: signature,
                cacheDirectory: cacheDirectory
            ) {
                metrics = cachedMetrics
            } else {
                let data: Data
                do {
                    data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
                } catch {
                    accessIssueNote = accessIssueNote ?? LocalFileAccessWarning.codexNote(for: error, path: fileURL.path)
                    continue
                }
                guard let parsedMetrics = try? CodexUsageReader.parseSessionJsonl(
                        data: data,
                        sessionID: fileURL.deletingPathExtension().lastPathComponent,
                        projectName: nil,
                        sourceFile: fileURL.path
                      )
                else { continue }
                metrics = RepositoryIdentityResolver.resolve(in: parsedMetrics, fileManager: fileManager)
                if signature.size > maximumSessionFileBytes,
                   metrics.eventCount == 0,
                   metrics.latestRateLimitAt == nil {
                    aggregate.skippedOversizedSessionFileCount += 1
                    continue
                }
                Self.sessionMetricsCache.store(
                    metrics,
                    for: path,
                    signature: signature,
                    cacheDirectory: cacheDirectory
                )
            }

            aggregate.merge(metrics, seenPoints: &seenPoints, taskIndexes: &taskIndexes)
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
}

private struct CodexSessionFileCandidate {
    var url: URL
    var signature: CodexSessionFileSignature
}

private struct CodexSessionFileSignature: Codable, Equatable {
    var size: Int
    var modifiedAt: Date?

    init?(fileURL: URL) throws {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              let size = values.fileSize
        else { return nil }
        self.size = size
        self.modifiedAt = values.contentModificationDate
    }
}

private final class CodexSessionMetricsCache: @unchecked Sendable {
    private struct Entry {
        var signature: CodexSessionFileSignature
        var metrics: CodexSessionMetrics
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func metrics(
        for path: String,
        signature: CodexSessionFileSignature,
        cacheDirectory: URL?
    ) -> CodexSessionMetrics? {
        lock.lock()
        let memoryEntry = entries[path]
        lock.unlock()
        if let memoryEntry, memoryEntry.signature == signature {
            return memoryEntry.metrics
        }

        guard let cacheDirectory,
              let data = try? Data(contentsOf: cacheFileURL(for: path, in: cacheDirectory)),
              let record = try? JSONDecoder().decode(CodexSessionMetricsDiskRecord.self, from: data),
              record.path == path,
              record.signature == signature
        else { return nil }

        lock.lock()
        entries[path] = Entry(signature: signature, metrics: record.metrics)
        lock.unlock()
        return record.metrics
    }

    func store(
        _ metrics: CodexSessionMetrics,
        for path: String,
        signature: CodexSessionFileSignature,
        cacheDirectory: URL?
    ) {
        lock.lock()
        entries[path] = Entry(signature: signature, metrics: metrics)
        lock.unlock()

        guard let cacheDirectory else { return }
        let record = CodexSessionMetricsDiskRecord(path: path, signature: signature, metrics: metrics)
        guard let data = try? JSONEncoder().encode(record) else { return }
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cacheDirectory.path)
            let cacheURL = cacheFileURL(for: path, in: cacheDirectory)
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

private struct CodexSessionMetricsDiskRecord: Codable {
    var path: String
    var signature: CodexSessionFileSignature
    var metrics: CodexSessionMetrics
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
