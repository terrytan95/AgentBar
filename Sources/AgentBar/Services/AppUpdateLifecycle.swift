import AppKit
import Foundation

struct AppUpdateLifecycle {
    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let session: URLSession
    private let updatesRootOverride: URL?

    struct CheckResult: Equatable {
        var latestRelease: AppUpdateRelease?
        var downloadedUpdate: DownloadedAppUpdate?
        var status: AppUpdateStatus
        var shouldClearPendingDownload: Bool
    }

    struct RestoreResult: Equatable {
        var latestRelease: AppUpdateRelease?
        var downloadedUpdate: DownloadedAppUpdate?
        var status: AppUpdateStatus?
        var shouldClearPendingDownload: Bool
    }

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        session: URLSession = .shared,
        updatesRootOverride: URL? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.session = session
        self.updatesRootOverride = updatesRootOverride
    }

    func shouldCheckAutomatically(now: Date) -> Bool {
        if let lastCheck = defaults.object(forKey: Keys.lastAutomaticCheckDate) as? Date,
           now.timeIntervalSince(lastCheck) < 60 * 60 * 24 {
            return false
        }
        defaults.set(now, forKey: Keys.lastAutomaticCheckDate)
        return true
    }

    @MainActor
    func checkForUpdates(
        trigger: AppUpdateTrigger,
        downloadedUpdate: DownloadedAppUpdate?,
        currentVersion: String,
        statusDidChange: (AppUpdateStatus) -> Void = { _ in }
    ) async -> CheckResult {
        let result = await checkForUpdates(
            trigger: trigger,
            downloadedUpdate: downloadedUpdate,
            currentVersion: currentVersion,
            fetchLatestRelease: fetchLatestRelease,
            download: download,
            statusDidChange: statusDidChange
        )
        if result.shouldClearPendingDownload {
            clearPendingDownload()
        }
        return result
    }

    @MainActor
    func checkForUpdates(
        trigger: AppUpdateTrigger,
        downloadedUpdate: DownloadedAppUpdate?,
        currentVersion: String,
        fetchLatestRelease: () async throws -> AppUpdateRelease,
        download: (AppUpdateRelease) async throws -> DownloadedAppUpdate,
        statusDidChange: (AppUpdateStatus) -> Void = { _ in }
    ) async -> CheckResult {
        do {
            let release = try await fetchLatestRelease()
            guard VersionComparator.isReleaseVersion(release.version, newerThan: currentVersion) else {
                return CheckResult(
                    latestRelease: release,
                    downloadedUpdate: nil,
                    status: trigger == .manual ? .upToDate : .idle,
                    shouldClearPendingDownload: true
                )
            }
            if let downloadedUpdate, downloadedUpdate.release.version == release.version {
                return CheckResult(
                    latestRelease: release,
                    downloadedUpdate: downloadedUpdate,
                    status: .downloaded(release.version),
                    shouldClearPendingDownload: false
                )
            }
            statusDidChange(.downloading(release.version))
            let downloadedUpdate = try await download(release)
            return CheckResult(
                latestRelease: release,
                downloadedUpdate: downloadedUpdate,
                status: .downloaded(release.version),
                shouldClearPendingDownload: false
            )
        } catch {
            return CheckResult(
                latestRelease: nil,
                downloadedUpdate: downloadedUpdate,
                status: .failed(error.localizedDescription),
                shouldClearPendingDownload: false
            )
        }
    }

    func restorePendingDownload(
        version: String,
        path: String,
        currentVersion: String,
        updatesRoot: URL,
        validateAppURL: (String, URL) throws -> URL
    ) -> RestoreResult {
        guard VersionComparator.isReleaseVersion(version, newerThan: currentVersion) else {
            return RestoreResult(
                latestRelease: nil,
                downloadedUpdate: nil,
                status: nil,
                shouldClearPendingDownload: true
            )
        }
        do {
            let appURL = try validateAppURL(path, updatesRoot)
            let release = AppUpdateRelease(
                version: version,
                name: "AgentBar \(version)",
                pageURL: URL(string: "https://github.com/terrytan95/AgentBar/releases/tag/\(version)")!,
                asset: AppUpdateAsset(name: "", downloadURL: appURL, size: 0, digest: nil)
            )
            return RestoreResult(
                latestRelease: release,
                downloadedUpdate: DownloadedAppUpdate(release: release, appURL: appURL),
                status: .downloaded(version),
                shouldClearPendingDownload: false
            )
        } catch {
            return RestoreResult(
                latestRelease: nil,
                downloadedUpdate: nil,
                status: nil,
                shouldClearPendingDownload: true
            )
        }
    }

    func restorePendingDownload(currentVersion: String) -> RestoreResult? {
        guard let version = defaults.string(forKey: Keys.pendingReleaseVersion),
              let path = defaults.string(forKey: Keys.pendingAppPath)
        else { return nil }
        let stager = AppUpdateStager(fileManager: fileManager, updatesRootOverride: updatesRootOverride)
        guard let updatesRoot = try? stager.updatesRootDirectory() else {
            clearPendingDownload()
            return nil
        }
        let result = restorePendingDownload(
            version: version,
            path: path,
            currentVersion: currentVersion,
            updatesRoot: updatesRoot,
            validateAppURL: { [fileManager] path, updatesRoot in
                try AppUpdateSecurity.validatedRestoredPendingAppURL(
                    path: path,
                    updatesRoot: updatesRoot,
                    fileManager: fileManager
                )
            }
        )
        if result.shouldClearPendingDownload {
            clearPendingDownload()
        }
        return result
    }

    @MainActor
    func install(_ update: DownloadedAppUpdate) throws {
        try AppUpdateInstaller.installAndRestart(from: update.appURL)
        NSApp.terminate(nil)
    }

    @MainActor
    private func fetchLatestRelease() async throws -> AppUpdateRelease {
        let url = URL(string: "https://api.github.com/repos/terrytan95/AgentBar/releases/latest")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AgentBar", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let asset = release.assets.first(where: { asset in
            asset.name.hasSuffix(".zip") && asset.name.localizedCaseInsensitiveContains("AgentBar")
        }) else {
            throw AppUpdateError.missingDownloadAsset
        }
        return AppUpdateRelease(
            version: release.tagName,
            name: release.name,
            pageURL: release.htmlURL,
            asset: AppUpdateAsset(
                name: asset.name,
                downloadURL: asset.browserDownloadURL,
                size: asset.size,
                digest: asset.digest
            )
        )
    }

    @MainActor
    private func download(_ release: AppUpdateRelease) async throws -> DownloadedAppUpdate {
        let request = URLRequest(url: release.asset.downloadURL, cachePolicy: .reloadIgnoringLocalCacheData)
        let (temporaryURL, response) = try await session.download(for: request)
        try validateHTTPResponse(response)
        let stager = AppUpdateStager(fileManager: fileManager, updatesRootOverride: updatesRootOverride)
        let downloadedUpdate = try await Task.detached(priority: .utility) {
            try stager.stage(release: release, temporaryURL: temporaryURL)
        }.value
        defaults.set(release.version, forKey: Keys.pendingReleaseVersion)
        defaults.set(downloadedUpdate.appURL.path, forKey: Keys.pendingAppPath)
        return downloadedUpdate
    }

    private func clearPendingDownload() {
        defaults.removeObject(forKey: Keys.pendingReleaseVersion)
        defaults.removeObject(forKey: Keys.pendingAppPath)
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode
        else {
            throw AppUpdateError.networkFailure
        }
    }

    private enum Keys {
        static let lastAutomaticCheckDate = "appUpdateLastAutomaticCheckDate"
        static let pendingReleaseVersion = "appUpdatePendingReleaseVersion"
        static let pendingAppPath = "appUpdatePendingAppPath"
    }
}

// A stager is consumed by one utility task; its FileManager is never mutated or shared back into UI work.
private struct AppUpdateStager: @unchecked Sendable {
    var fileManager: FileManager
    var updatesRootOverride: URL?

    func stage(release: AppUpdateRelease, temporaryURL: URL) throws -> DownloadedAppUpdate {
        let updateDirectory = try freshUpdateDirectory(for: release.version)
        try AppUpdateSecurity.validateDownloadURL(release.asset.downloadURL)
        let zipURL = updateDirectory.appending(path: try AppUpdateSecurity.safeAssetFileName(release.asset.name))
        let extractDirectory = updateDirectory.appending(path: "expanded", directoryHint: .isDirectory)

        try fileManager.moveItem(at: temporaryURL, to: zipURL)
        try AppUpdateSecurity.verifyRequiredSHA256Digest(release.asset.digest, fileURL: zipURL)
        try fileManager.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
        try unzip(zipURL, to: extractDirectory)
        let appURL = try findAppBundle(in: extractDirectory)
        try AppUpdateSecurity.validateDownloadedAppBundle(appURL, expectedRoot: extractDirectory, fileManager: fileManager)
        return DownloadedAppUpdate(release: release, appURL: appURL)
    }

    func updatesRootDirectory() throws -> URL {
        if let updatesRootOverride {
            try fileManager.createDirectory(at: updatesRootOverride, withIntermediateDirectories: true)
            return updatesRootOverride
        }
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appending(path: "AgentBar/Updates", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func freshUpdateDirectory(for version: String) throws -> URL {
        let safeVersion = version.replacingOccurrences(of: "/", with: "-")
        let root = try updatesRootDirectory()
        let directory = root.appending(path: safeVersion, directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func unzip(_ zipURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, destinationURL.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AppUpdateError.unzipFailed
        }
    }

    private func findAppBundle(in directory: URL) throws -> URL {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw AppUpdateError.missingAppBundle
        }
        for case let url as URL in enumerator where url.lastPathComponent == "AgentBar.app" {
            return url
        }
        throw AppUpdateError.missingAppBundle
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String
    let htmlURL: URL
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL
    let size: Int
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
        case digest
    }
}
