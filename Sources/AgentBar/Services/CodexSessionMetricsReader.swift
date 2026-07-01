import Foundation

struct CodexSessionMetricsReader {
    typealias Parser = (Data, String?, String?, String?) throws -> CodexSessionMetrics

    var fileManager: FileManager = .default
    var parseSessionJsonl: Parser = { data, sessionID, projectName, sourceFile in
        try CodexUsageReader.parseSessionJsonl(
            data: data,
            sessionID: sessionID,
            projectName: projectName,
            sourceFile: sourceFile
        )
    }

    private static let sessionMetricsCache = CodexSessionMetricsCache()

    func read(root: URL, maximumSessionFileBytes: Int, maximumSessionFiles: Int) -> CodexSessionMetrics {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return CodexSessionMetrics(eventCount: 0, tokenTotals: .zero, points: [], latestFiveHour: nil, latestWeekly: nil, latestRateLimitAt: nil)
        }

        var aggregate = CodexSessionMetrics(eventCount: 0, tokenTotals: .zero, points: [], latestFiveHour: nil, latestWeekly: nil, latestRateLimitAt: nil)
        var livePaths = Set<String>()
        var reviewedFileCount = 0

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            guard let signature = CodexSessionFileSignature(fileURL: fileURL) else { continue }
            guard signature.size <= maximumSessionFileBytes else { continue }
            guard reviewedFileCount < maximumSessionFiles else { break }
            reviewedFileCount += 1
            let path = fileURL.path
            livePaths.insert(path)
            let metrics: CodexSessionMetrics
            if let cachedMetrics = Self.sessionMetricsCache.metrics(for: path, signature: signature) {
                metrics = cachedMetrics
            } else {
                guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
                      let parsedMetrics = try? parseSessionJsonl(
                        data,
                        fileURL.deletingPathExtension().lastPathComponent,
                        nil,
                        fileURL.path
                      )
                else { continue }
                metrics = parsedMetrics
                Self.sessionMetricsCache.store(metrics, for: path, signature: signature)
            }

            aggregate.merge(metrics)
        }
        Self.sessionMetricsCache.retain(paths: livePaths)

        return aggregate
    }

    static func resetCacheForTesting() {
        sessionMetricsCache.removeAll()
    }
}

private struct CodexSessionFileSignature: Equatable {
    var size: Int
    var modifiedAt: Date?

    init?(fileURL: URL) {
        guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
              values.isRegularFile == true,
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
