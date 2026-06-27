import Foundation

struct AppUpdateLifecycle {
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
}
