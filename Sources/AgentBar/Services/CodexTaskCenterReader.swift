import Foundation

struct CodexTaskCenterReader {
    static let maximumTaskFiles = 100

    var homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    var fileManager: FileManager = .default

    func read() -> [AgentTask] {
        let sessionRoot = homeDirectory.appending(path: ".codex/sessions")
        let cacheDirectory = homeDirectory.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
            ? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appending(path: CodexUsageReader.sessionMetricsCacheDirectoryName, directoryHint: .isDirectory)
            : nil
        return CodexSessionMetricsReader(fileManager: fileManager).read(
            root: sessionRoot,
            maximumSessionFileBytes: CodexUsageReader.maximumSessionFileBytes,
            maximumSessionFiles: Self.maximumTaskFiles,
            cacheDirectory: cacheDirectory,
            prunesCache: false
        ).tasks
            .sorted { lhs, rhs in
                (lhs.completedAt ?? lhs.lastActivityAt) > (rhs.completedAt ?? rhs.lastActivityAt)
            }
            .prefix(Self.maximumTaskFiles)
            .map { $0 }
    }
}
