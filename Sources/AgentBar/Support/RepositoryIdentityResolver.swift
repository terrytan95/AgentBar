import Foundation

enum RepositoryIdentityResolver {
    static func repositoryPath(for cwd: String?, fileManager: FileManager = .default) -> String? {
        guard let cwd = cwd?.trimmingCharacters(in: .whitespacesAndNewlines), !cwd.isEmpty else { return nil }
        var directory = URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL

        while directory.path != "/" {
            let gitMarker = directory.appending(path: ".git")
            if fileManager.fileExists(atPath: gitMarker.path) {
                return directory.path
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    static func resolve(in metrics: CodexSessionMetrics, fileManager: FileManager = .default) -> CodexSessionMetrics {
        var metrics = metrics
        var resolvedPaths: [String: String] = [:]

        func resolve(_ cwd: String?) -> String? {
            guard let cwd else { return nil }
            if let cached = resolvedPaths[cwd] { return cached }
            let path = repositoryPath(for: cwd, fileManager: fileManager)
            if let path { resolvedPaths[cwd] = path }
            return path
        }

        metrics.points = metrics.points.map { point in
            var point = point
            point.repositoryPath = resolve(point.cwd)
            if let repositoryPath = point.repositoryPath {
                point.projectName = URL(fileURLWithPath: repositoryPath).lastPathComponent
            }
            return point
        }
        metrics.tasks = metrics.tasks.map { task in
            var task = task
            task.repositoryPath = resolve(task.cwd)
            if let repositoryPath = task.repositoryPath {
                task.projectName = URL(fileURLWithPath: repositoryPath).lastPathComponent
            }
            return task
        }
        return metrics
    }
}
