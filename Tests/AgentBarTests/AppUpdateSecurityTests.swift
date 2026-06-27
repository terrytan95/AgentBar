import Foundation
import XCTest
@testable import AgentBar

final class AppUpdateSecurityTests: XCTestCase {

    @MainActor
    func testAppUpdateSecurityCoverage() async throws {
        try await checkManualUpdateCheckBypassesURLCacheRevalidation()
        try checkPendingDownloadedUpdateSuppressesManualUpdateCheck()
        try checkRequiredDigestAcceptsMatchingSHA256()
        await checkAppUpdateLifecycleDownloadsNewerReleaseAndEmitsState()
        try checkAppUpdateLifecycleClearsStalePendingRestore()
        try checkRequiredDigestRejectsMissingOrMalformedDigest()
        try checkRestoredPendingUpdateMustBeAgentBarBundleUnderUpdatesRoot()
        try checkRestoredPendingUpdateRejectsUnsignedAgentBarBundle()
        try checkRestoredPendingUpdateRejectsBundleOutsideUpdatesRoot()
        checkAssetNameCannotContainPathComponents()
        checkInstallerUsesInlineQuotedCommandInsteadOfTemporaryScript()
    }
    @MainActor
    private func checkManualUpdateCheckBypassesURLCacheRevalidation() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateCheckURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let defaultsName = "AgentBarTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            UpdateCheckURLProtocol.handler.set(nil)
        }

        UpdateCheckURLProtocol.handler.set { request in
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (
                response,
                Data("""
                {
                  "tag_name": "v0.0.0",
                  "name": "AgentBar v0.0.0",
                  "html_url": "https://github.com/terrytan95/AgentBar/releases/tag/v0.0.0",
                  "assets": [{
                    "name": "AgentBar-v0.0.0.zip",
                    "browser_download_url": "https://github.com/terrytan95/AgentBar/releases/download/v0.0.0/AgentBar-v0.0.0.zip",
                    "size": 1,
                    "digest": "sha256:1ca77194abc4fa2675c7b5773420993b23f12d77e492f0e2787c3e0bf80de655"
                  }]
                }
                """.utf8)
            )
        }

        let store = AppUpdateStore(defaults: defaults, session: session)

        await store.checkForUpdates()

        XCTAssertEqual(store.status, .upToDate)
    }

    @MainActor
    private func checkPendingDownloadedUpdateSuppressesManualUpdateCheck() throws {
        let fileManager = FileManager.default
        let updatesRoot = fileManager.temporaryDirectory
            .appending(path: "AgentBarTests-\(UUID().uuidString)/Updates", directoryHint: .isDirectory)
        let version = "v999.0.0"
        let app = updatesRoot.appending(path: "\(version)/expanded/AgentBar.app", directoryHint: .isDirectory)
        try createFakeAgentBarApp(at: app)
        try adHocSignApp(at: app)

        let defaultsName = "AgentBarTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defaults.set(version, forKey: "appUpdatePendingReleaseVersion")
        defaults.set(app.path, forKey: "appUpdatePendingAppPath")
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? fileManager.removeItem(at: updatesRoot.deletingLastPathComponent())
        }

        let store = AppUpdateStore(defaults: defaults, fileManager: fileManager, updatesRootOverride: updatesRoot)

        XCTAssertTrue(store.canInstallDownloadedUpdate)
        XCTAssertFalse(store.showsCheckForUpdatesControl)
        XCTAssertFalse(store.canCheckForUpdates)
    }

    private func checkRequiredDigestAcceptsMatchingSHA256() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let file = temp.appending(path: "AgentBar.zip")
        try Data("agentbar".utf8).write(to: file)

        try AppUpdateSecurity.verifyRequiredSHA256Digest(
            "sha256:1ca77194abc4fa2675c7b5773420993b23f12d77e492f0e2787c3e0bf80de655",
            fileURL: file
        )
    }

    @MainActor
    private func checkAppUpdateLifecycleDownloadsNewerReleaseAndEmitsState() async {
        let release = AppUpdateRelease(
            version: "v9.0.0",
            name: "AgentBar v9.0.0",
            pageURL: URL(string: "https://github.com/terrytan95/AgentBar/releases/tag/v9.0.0")!,
            asset: AppUpdateAsset(
                name: "AgentBar-v9.0.0.zip",
                downloadURL: URL(string: "https://github.com/terrytan95/AgentBar/releases/download/v9.0.0/AgentBar-v9.0.0.zip")!,
                size: 1,
                digest: nil
            )
        )
        let appURL = URL(fileURLWithPath: "/tmp/AgentBar.app")
        var events: [AppUpdateStatus] = []
        var downloadedVersions: [String] = []
        let lifecycle = AppUpdateLifecycle()

        let result = await lifecycle.checkForUpdates(
            trigger: .manual,
            downloadedUpdate: nil,
            currentVersion: "1.0.0",
            fetchLatestRelease: { release },
            download: { release in
                downloadedVersions.append(release.version)
                return DownloadedAppUpdate(release: release, appURL: appURL)
            },
            statusDidChange: { events.append($0) }
        )

        XCTAssertEqual(events, [.downloading("v9.0.0")])
        XCTAssertEqual(downloadedVersions, ["v9.0.0"])
        XCTAssertEqual(result.latestRelease, release)
        XCTAssertEqual(result.downloadedUpdate, DownloadedAppUpdate(release: release, appURL: appURL))
        XCTAssertEqual(result.status, .downloaded("v9.0.0"))
        XCTAssertFalse(result.shouldClearPendingDownload)
    }

    private func checkAppUpdateLifecycleClearsStalePendingRestore() throws {
        let lifecycle = AppUpdateLifecycle()
        let root = URL(fileURLWithPath: "/tmp/AgentBarUpdates")

        let result = lifecycle.restorePendingDownload(
            version: "v1.0.0",
            path: "/tmp/AgentBarUpdates/v1.0.0/AgentBar.app",
            currentVersion: "1.0.0",
            updatesRoot: root,
            validateAppURL: { _, _ in
                XCTFail("stale pending update should not validate app bundle")
                return URL(fileURLWithPath: "/tmp/unused.app")
            }
        )

        XCTAssertNil(result.latestRelease)
        XCTAssertNil(result.downloadedUpdate)
        XCTAssertNil(result.status)
        XCTAssertTrue(result.shouldClearPendingDownload)
    }

    private func checkRequiredDigestRejectsMissingOrMalformedDigest() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let file = temp.appending(path: "AgentBar.zip")
        try Data("agentbar".utf8).write(to: file)

        XCTAssertThrowsError(try AppUpdateSecurity.verifyRequiredSHA256Digest(nil, fileURL: file)) { error in
            XCTAssertEqual(error as? AppUpdateError, .missingDigest)
        }
        XCTAssertThrowsError(try AppUpdateSecurity.verifyRequiredSHA256Digest("sha256:not-hex", fileURL: file)) { error in
            XCTAssertEqual(error as? AppUpdateError, .invalidDigest)
        }
    }

    private func checkRestoredPendingUpdateMustBeAgentBarBundleUnderUpdatesRoot() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let root = temp.appending(path: "Updates", directoryHint: .isDirectory)
        let app = root.appending(path: "v1.0.6/expanded/AgentBar.app", directoryHint: .isDirectory)
        try createFakeAgentBarApp(at: app)
        try adHocSignApp(at: app)

        let validated = try AppUpdateSecurity.validatedRestoredPendingAppURL(path: app.path, updatesRoot: root)

        XCTAssertEqual(validated.path, app.path)
    }

    private func checkRestoredPendingUpdateRejectsUnsignedAgentBarBundle() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let root = temp.appending(path: "Updates", directoryHint: .isDirectory)
        let app = root.appending(path: "v1.0.6/expanded/AgentBar.app", directoryHint: .isDirectory)
        try createFakeAgentBarApp(at: app)

        XCTAssertThrowsError(try AppUpdateSecurity.validatedRestoredPendingAppURL(path: app.path, updatesRoot: root)) { error in
            XCTAssertEqual(error as? AppUpdateError, .invalidCodeSignature)
        }
    }

    private func checkRestoredPendingUpdateRejectsBundleOutsideUpdatesRoot() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let root = temp.appending(path: "Updates", directoryHint: .isDirectory)
        let outside = temp.appending(path: "Elsewhere/AgentBar.app", directoryHint: .isDirectory)
        try createFakeAgentBarApp(at: outside)
        try adHocSignApp(at: outside)

        XCTAssertThrowsError(try AppUpdateSecurity.validatedRestoredPendingAppURL(path: outside.path, updatesRoot: root)) { error in
            XCTAssertEqual(error as? AppUpdateError, .invalidAppBundle)
        }
    }

    private func checkAssetNameCannotContainPathComponents() {
        XCTAssertNoThrow(try AppUpdateSecurity.safeAssetFileName("AgentBar-v1.0.6.zip"))
        XCTAssertThrowsError(try AppUpdateSecurity.safeAssetFileName("../AgentBar-v1.0.6.zip")) { error in
            XCTAssertEqual(error as? AppUpdateError, .unsafeDownloadAsset)
        }
    }

    private func checkInstallerUsesInlineQuotedCommandInsteadOfTemporaryScript() {
        let appURL = URL(fileURLWithPath: "/tmp/AgentBar's Update/AgentBar.app")

        let command = AppUpdateInstaller.installCommand(from: appURL)

        XCTAssertFalse(command.contains("agentbar-install-"))
        XCTAssertFalse(command.contains("/bin/sh /"))
        XCTAssertTrue(command.contains("'/tmp/AgentBar'\\''s Update/AgentBar.app'"))
        XCTAssertTrue(command.contains("'/Applications/AgentBar.app'"))
    }

    private func createFakeAgentBarApp(at appURL: URL) throws {
        let contents = appURL.appending(path: "Contents", directoryHint: .isDirectory)
        let macOS = contents.appending(path: "MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: macOS.appending(path: "AgentBar"))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: macOS.appending(path: "AgentBar").path
        )
        let plist: [String: String] = [
            "CFBundleExecutable": "AgentBar",
            "CFBundleIdentifier": AppUpdateSecurity.bundleIdentifier,
            "CFBundleName": "AgentBar",
            "CFBundlePackageType": "APPL"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))
    }

    private func adHocSignApp(at appURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--deep", "--sign", "-", appURL.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}

private final class UpdateCheckURLProtocol: URLProtocol {
    static let handler = UpdateCheckURLProtocolHandler()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler.get() else {
            XCTFail("Missing URL protocol handler")
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class UpdateCheckURLProtocolHandler: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    func set(_ handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?) {
        lock.withLock {
            self.handler = handler
        }
    }

    func get() -> ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        lock.withLock {
            handler
        }
    }
}
