import CryptoKit
import Foundation
import Security

@MainActor
final class AppUpdateStore: ObservableObject {
    static let shared = AppUpdateStore()

    @Published private(set) var status: AppUpdateStatus = .idle
    @Published private(set) var latestRelease: AppUpdateRelease?
    @Published private(set) var downloadedUpdate: DownloadedAppUpdate?

    private let lifecycle: AppUpdateLifecycle
    private var automaticCheckTimer: Timer?
    private var isChecking = false

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        session: URLSession = .shared,
        updatesRootOverride: URL? = nil
    ) {
        lifecycle = AppUpdateLifecycle(
            defaults: defaults,
            fileManager: fileManager,
            session: session,
            updatesRootOverride: updatesRootOverride
        )
        restorePendingDownload()
    }

    var currentVersion: String {
        AppVersion.currentDisplayVersion
    }

    var showsCheckForUpdatesControl: Bool {
        downloadedUpdate == nil
    }

    var canCheckForUpdates: Bool {
        showsCheckForUpdatesControl && !status.isBusy
    }

    var canInstallDownloadedUpdate: Bool {
        downloadedUpdate != nil && !status.isBusy
    }

    func startAutomaticChecks() {
        guard automaticCheckTimer == nil else { return }
        automaticCheckTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkAutomaticallyIfNeeded()
            }
        }
        Task { await checkAutomaticallyIfNeeded() }
    }

    func checkForUpdates() async {
        await checkForUpdates(trigger: .manual)
    }

    func installDownloadedUpdate() {
        guard let downloadedUpdate else { return }
        do {
            status = .installing(downloadedUpdate.release.version)
            try lifecycle.install(downloadedUpdate)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func checkAutomaticallyIfNeeded() async {
        let now = Date()
        guard lifecycle.shouldCheckAutomatically(now: now) else { return }
        await checkForUpdates(trigger: .automatic)
    }

    private func checkForUpdates(trigger: AppUpdateTrigger) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        status = .checking
        let result = await lifecycle.checkForUpdates(
            trigger: trigger,
            downloadedUpdate: downloadedUpdate,
            currentVersion: AppVersion.currentComparableVersion,
            statusDidChange: { [weak self] status in
                self?.status = status
            }
        )
        latestRelease = result.latestRelease ?? latestRelease
        downloadedUpdate = result.downloadedUpdate
        status = result.status
    }

    private func restorePendingDownload() {
        guard let result = lifecycle.restorePendingDownload(
            currentVersion: AppVersion.currentComparableVersion
        ) else { return }
        latestRelease = result.latestRelease
        downloadedUpdate = result.downloadedUpdate
        if let status = result.status {
            self.status = status
        }
    }

}

enum AppUpdateStatus: Equatable {
    case idle
    case checking
    case upToDate
    case downloading(String)
    case downloaded(String)
    case installing(String)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .installing:
            true
        case .idle, .upToDate, .downloaded, .failed:
            false
        }
    }

    var isFailure: Bool {
        if case .failed = self {
            return true
        }
        return false
    }

    func localizedMessage(language: AppLanguage) -> String {
        switch self {
        case .idle:
            L.text("updates_daily_check", language)
        case .checking:
            L.text("checking_for_updates", language)
        case .upToDate:
            L.text("app_up_to_date", language)
        case .downloading(let version):
            String(format: L.text("downloading_update", language), version)
        case .downloaded(let version):
            String(format: L.text("update_ready_to_install", language), version)
        case .installing(let version):
            String(format: L.text("installing_update", language), version)
        case .failed(let message):
            String(format: L.text("update_check_failed", language), message)
        }
    }
}

enum AppUpdateTrigger {
    case manual
    case automatic
}

struct AppUpdateRelease: Equatable, Sendable {
    let version: String
    let name: String
    let pageURL: URL
    let asset: AppUpdateAsset
}

struct AppUpdateAsset: Equatable, Sendable {
    let name: String
    let downloadURL: URL
    let size: Int
    let digest: String?
}

struct DownloadedAppUpdate: Equatable, Sendable {
    let release: AppUpdateRelease
    let appURL: URL
}

enum AppVersion {
    static var currentDisplayVersion: String {
        let version = bundleValue("CFBundleShortVersionString")
        let build = bundleValue("CFBundleVersion")
        if let version, let build, !build.isEmpty {
            return "\(version) (\(build))"
        }
        if let version {
            return version
        }
        return "Development"
    }

    static var currentComparableVersion: String {
        bundleValue("CFBundleShortVersionString") ?? "0.0.0"
    }

    private static func bundleValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty
        else { return nil }
        return value
    }
}

enum VersionComparator {
    static func isReleaseVersion(_ releaseVersion: String, newerThan currentVersion: String) -> Bool {
        normalizedParts(releaseVersion).lexicographicallyPrecedes(normalizedParts(currentVersion)) == false
            && normalizedParts(releaseVersion) != normalizedParts(currentVersion)
    }

    private static func normalizedParts(_ version: String) -> [Int] {
        let trimmed = version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let numericPrefix = trimmed.split(separator: "-", maxSplits: 1).first ?? Substring(trimmed)
        let parts = numericPrefix.split(separator: ".").map { Int($0) ?? 0 }
        return parts + Array(repeating: 0, count: max(0, 3 - parts.count))
    }
}

enum AppUpdateInstaller {
    static func installAndRestart(from appURL: URL) throws {
        let command = installCommand(from: appURL)
        let appleScript = "do shell script \(command.appleScriptQuoted) with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        try process.run()
    }

    static func installCommand(from appURL: URL) -> String {
        let destination = URL(fileURLWithPath: "/Applications/AgentBar.app")
        return """
        set -e
        sleep 1
        /bin/rm -rf \(destination.path.shellQuoted)
        /usr/bin/ditto \(appURL.path.shellQuoted) \(destination.path.shellQuoted)
        /usr/bin/xattr -dr com.apple.quarantine \(destination.path.shellQuoted) >/dev/null 2>&1 || true
        /usr/bin/open -n \(destination.path.shellQuoted)
        """
    }
}

enum AppUpdateError: LocalizedError {
    case networkFailure
    case missingDownloadAsset
    case missingDigest
    case invalidDigest
    case digestMismatch
    case unzipFailed
    case missingAppBundle
    case unsafeDownloadAsset
    case insecureDownloadURL
    case invalidAppBundle
    case invalidCodeSignature

    var errorDescription: String? {
        switch self {
        case .networkFailure: "GitHub returned an unexpected response."
        case .missingDownloadAsset: "The latest release does not include an AgentBar zip asset."
        case .missingDigest: "The update asset is missing a required checksum."
        case .invalidDigest: "The update asset checksum is not a valid SHA-256 digest."
        case .digestMismatch: "The downloaded update did not match GitHub's asset checksum."
        case .unzipFailed: "The downloaded update could not be expanded."
        case .missingAppBundle: "The downloaded update did not contain AgentBar.app."
        case .unsafeDownloadAsset: "The update asset name is not safe to download."
        case .insecureDownloadURL: "The update asset must be downloaded over HTTPS."
        case .invalidAppBundle: "The downloaded update is not a valid AgentBar app bundle."
        case .invalidCodeSignature: "The downloaded update does not have a valid code signature."
        }
    }
}

enum AppUpdateSecurity {
    static let bundleIdentifier = "com.terrytan.AgentBar"

    static func validateDownloadURL(_ url: URL) throws {
        guard url.scheme?.localizedCaseInsensitiveCompare("https") == .orderedSame else {
            throw AppUpdateError.insecureDownloadURL
        }
    }

    static func safeAssetFileName(_ name: String) throws -> String {
        let fileName = URL(fileURLWithPath: name).lastPathComponent
        guard !fileName.isEmpty,
              fileName == name,
              fileName != ".",
              fileName != "..",
              fileName.hasSuffix(".zip"),
              fileName.localizedCaseInsensitiveContains("AgentBar")
        else {
            throw AppUpdateError.unsafeDownloadAsset
        }
        return fileName
    }

    static func verifyRequiredSHA256Digest(_ digest: String?, fileURL: URL) throws {
        guard let digest, digest.hasPrefix("sha256:") else {
            throw AppUpdateError.missingDigest
        }
        let expected = String(digest.dropFirst("sha256:".count)).lowercased()
        guard expected.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
            throw AppUpdateError.invalidDigest
        }
        let file = try FileHandle(forReadingFrom: fileURL)
        defer { try? file.close() }
        var hasher = SHA256()
        while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expected else {
            throw AppUpdateError.digestMismatch
        }
    }

    static func validatedRestoredPendingAppURL(
        path: String,
        updatesRoot: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let appURL = URL(fileURLWithPath: path)
        try validateDownloadedAppBundle(appURL, expectedRoot: updatesRoot, fileManager: fileManager)
        return appURL
    }

    static func validateDownloadedAppBundle(
        _ appURL: URL,
        expectedRoot: URL,
        fileManager: FileManager = .default
    ) throws {
        guard appURL.lastPathComponent == "AgentBar.app",
              isDescendant(appURL, of: expectedRoot),
              fileManager.fileExists(atPath: appURL.path)
        else {
            throw AppUpdateError.invalidAppBundle
        }
        let values = try appURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true, values.isDirectory == true else {
            throw AppUpdateError.invalidAppBundle
        }
        guard let bundle = Bundle(url: appURL),
              bundle.bundleIdentifier == bundleIdentifier,
              let executableURL = bundle.executableURL,
              fileManager.fileExists(atPath: executableURL.path)
        else {
            throw AppUpdateError.invalidAppBundle
        }
        try validateCodeSignature(appURL)
    }

    private static func isDescendant(_ url: URL, of root: URL) -> Bool {
        let childPath = url.standardizedFileURL.path
        var rootPath = root.standardizedFileURL.path
        if !rootPath.hasSuffix("/") {
            rootPath += "/"
        }
        return childPath.hasPrefix(rootPath)
    }

    private static func validateCodeSignature(_ appURL: URL) throws {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            throw AppUpdateError.invalidCodeSignature
        }
        let checkStatus = SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil)
        guard checkStatus == errSecSuccess else {
            throw AppUpdateError.invalidCodeSignature
        }
    }
}

private extension String {
    var shellQuoted: String {
        "'\(replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    var appleScriptQuoted: String {
        "\"\(replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
