import Foundation

struct CodexSessionMetricsReader {
    var fileManager: FileManager = .default

    private static let sessionMetricsCache = CodexSessionMetricsCache()

    func read(root: URL, maximumSessionFileBytes: Int, maximumSessionFiles: Int) -> CodexSessionMetrics {
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
        var livePaths = Set<String>()
        var reviewedFileCount = 0

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            let signature: CodexSessionFileSignature
            do {
                guard let fileSignature = try CodexSessionFileSignature(fileURL: fileURL) else { continue }
                signature = fileSignature
            } catch {
                accessIssueNote = accessIssueNote ?? LocalFileAccessWarning.codexNote(for: error, path: fileURL.path)
                continue
            }
            guard signature.size <= maximumSessionFileBytes else {
                aggregate.skippedOversizedSessionFileCount += 1
                continue
            }
            guard reviewedFileCount < maximumSessionFiles else {
                aggregate.skippedSessionFileCapCount += 1
                continue
            }
            reviewedFileCount += 1
            let path = fileURL.path
            livePaths.insert(path)
            let metrics: CodexSessionMetrics
            if let cachedMetrics = Self.sessionMetricsCache.metrics(for: path, signature: signature) {
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
                metrics = parsedMetrics
                Self.sessionMetricsCache.store(metrics, for: path, signature: signature)
            }

            aggregate.merge(metrics)
        }
        Self.sessionMetricsCache.retain(paths: livePaths)

        aggregate.accessIssueNote = accessIssueNote
        return aggregate
    }

    static func resetCacheForTesting() {
        sessionMetricsCache.removeAll()
    }
}

private struct CodexSessionFileSignature: Equatable {
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

    func metrics(for path: String, signature: CodexSessionFileSignature) -> CodexSessionMetrics? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[path], entry.signature == signature else { return nil }
        return entry.metrics
    }

    func store(_ metrics: CodexSessionMetrics, for path: String, signature: CodexSessionFileSignature) {
        lock.lock()
        entries[path] = Entry(signature: signature, metrics: metrics)
        lock.unlock()
    }

    func retain(paths: Set<String>) {
        lock.lock()
        entries = entries.filter { paths.contains($0.key) }
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}

private extension CodexSessionMetrics {
    mutating func merge(_ metrics: CodexSessionMetrics) {
        eventCount += metrics.eventCount
        if metrics.tokenTotals.total > 0 {
            tokenTotals = tokenTotals + metrics.tokenTotals
        }
        points.append(contentsOf: metrics.points)
        if let latestRateLimitAt = metrics.latestRateLimitAt,
           self.latestRateLimitAt == nil || latestRateLimitAt >= (self.latestRateLimitAt ?? .distantPast) {
            latestFiveHour = metrics.latestFiveHour
            latestWeekly = metrics.latestWeekly
            latestResetCredits = metrics.latestResetCredits
            self.latestRateLimitAt = latestRateLimitAt
        }
    }
}
