import Foundation
import XCTest
@testable import AgentBar

final class AppUpdateSecurityTests: XCTestCase {
    func testRequiredDigestAcceptsMatchingSHA256() throws {
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

    func testRequiredDigestRejectsMissingOrMalformedDigest() throws {
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

    func testRestoredPendingUpdateMustBeAgentBarBundleUnderUpdatesRoot() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let root = temp.appending(path: "Updates", directoryHint: .isDirectory)
        let app = root.appending(path: "v1.0.6/expanded/AgentBar.app", directoryHint: .isDirectory)
        try createFakeAgentBarApp(at: app)
        try adHocSignApp(at: app)

        let validated = try AppUpdateSecurity.validatedRestoredPendingAppURL(path: app.path, updatesRoot: root)

        XCTAssertEqual(validated.path, app.path)
    }

    func testRestoredPendingUpdateRejectsUnsignedAgentBarBundle() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let root = temp.appending(path: "Updates", directoryHint: .isDirectory)
        let app = root.appending(path: "v1.0.6/expanded/AgentBar.app", directoryHint: .isDirectory)
        try createFakeAgentBarApp(at: app)

        XCTAssertThrowsError(try AppUpdateSecurity.validatedRestoredPendingAppURL(path: app.path, updatesRoot: root)) { error in
            XCTAssertEqual(error as? AppUpdateError, .invalidCodeSignature)
        }
    }

    func testRestoredPendingUpdateRejectsBundleOutsideUpdatesRoot() throws {
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

    func testAssetNameCannotContainPathComponents() {
        XCTAssertNoThrow(try AppUpdateSecurity.safeAssetFileName("AgentBar-v1.0.6.zip"))
        XCTAssertThrowsError(try AppUpdateSecurity.safeAssetFileName("../AgentBar-v1.0.6.zip")) { error in
            XCTAssertEqual(error as? AppUpdateError, .unsafeDownloadAsset)
        }
    }

    func testInstallerUsesInlineQuotedCommandInsteadOfTemporaryScript() {
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
