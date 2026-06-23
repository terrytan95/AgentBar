import AppKit
import CryptoKit
import Foundation
import Security

@MainActor
final class AppUpdateStore: ObservableObject {
    static let shared = AppUpdateStore()

    @Published private(set) var status: AppUpdateStatus = .idle
    @Published private(set) var latestRelease: AppUpdateRelease?
    @Published private(set) var downloadedUpdate: DownloadedAppUpdate?

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let session: URLSession
    private let updatesRootOverride: URL?
    private var automaticCheckTimer: Timer?
    private var isChecking = false

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
            try AppUpdateInstaller.installAndRestart(from: downloadedUpdate.appURL)
            NSApp.terminate(nil)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func checkAutomaticallyIfNeeded() async {
        let now = Date()
        if let lastCheck = defaults.object(forKey: Keys.lastAutomaticCheckDate) as? Date,
           now.timeIntervalSince(lastCheck) < 60 * 60 * 24 {
            return
        }
        defaults.set(now, forKey: Keys.lastAutomaticCheckDate)
        await checkForUpdates(trigger: .automatic)
    }

    private func checkForUpdates(trigger: AppUpdateTrigger) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        status = .checking
        do {
            let release = try await fetchLatestRelease()
            latestRelease = release
            guard VersionComparator.isReleaseVersion(release.version, newerThan: AppVersion.currentComparableVersion) else {
                downloadedUpdate = nil
                clearPendingDownload()
                status = trigger == .manual ? .upToDate : .idle
                return
            }
            if let downloadedUpdate, downloadedUpdate.release.version == release.version {
                status = .downloaded(release.version)
                return
            }
            try await download(release)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

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

    private func download(_ release: AppUpdateRelease) async throws {
        status = .downloading(release.version)
        let updateDirectory = try freshUpdateDirectory(for: release.version)
        try AppUpdateSecurity.validateDownloadURL(release.asset.downloadURL)
        let zipURL = updateDirectory.appending(path: try AppUpdateSecurity.safeAssetFileName(release.asset.name))
        let extractDirectory = updateDirectory.appending(path: "expanded", directoryHint: .isDirectory)

        let request = URLRequest(url: release.asset.downloadURL, cachePolicy: .reloadIgnoringLocalCacheData)
        let (temporaryURL, response) = try await session.download(for: request)
        try validateHTTPResponse(response)
        try fileManager.moveItem(at: temporaryURL, to: zipURL)
        try AppUpdateSecurity.verifyRequiredSHA256Digest(release.asset.digest, fileURL: zipURL)
        try fileManager.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
        try unzip(zipURL, to: extractDirectory)
        let appURL = try findAppBundle(in: extractDirectory)
        try AppUpdateSecurity.validateDownloadedAppBundle(appURL, expectedRoot: extractDirectory, fileManager: fileManager)

        let downloadedUpdate = DownloadedAppUpdate(release: release, appURL: appURL)
        self.downloadedUpdate = downloadedUpdate
        defaults.set(release.version, forKey: Keys.pendingReleaseVersion)
        defaults.set(appURL.path, forKey: Keys.pendingAppPath)
        status = .downloaded(release.version)
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

    private func updatesRootDirectory() throws -> URL {
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

    private func restorePendingDownload() {
        guard let version = defaults.string(forKey: Keys.pendingReleaseVersion),
              let path = defaults.string(forKey: Keys.pendingAppPath)
        else { return }
        guard VersionComparator.isReleaseVersion(version, newerThan: AppVersion.currentComparableVersion) else {
            clearPendingDownload()
            return
        }
        guard let updatesRoot = try? updatesRootDirectory(),
              let appURL = try? AppUpdateSecurity.validatedRestoredPendingAppURL(
                path: path,
                updatesRoot: updatesRoot,
                fileManager: fileManager
              ) else {
            clearPendingDownload()
            return
        }
        let release = AppUpdateRelease(
            version: version,
            name: "AgentBar \(version)",
            pageURL: URL(string: "https://github.com/terrytan95/AgentBar/releases/tag/\(version)")!,
            asset: AppUpdateAsset(name: "", downloadURL: appURL, size: 0, digest: nil)
        )
        latestRelease = release
        downloadedUpdate = DownloadedAppUpdate(release: release, appURL: appURL)
        status = .downloaded(version)
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

    private enum Keys {
        static let lastAutomaticCheckDate = "appUpdateLastAutomaticCheckDate"
        static let pendingReleaseVersion = "appUpdatePendingReleaseVersion"
        static let pendingAppPath = "appUpdatePendingAppPath"
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

struct AppUpdateRelease: Equatable {
    let version: String
    let name: String
    let pageURL: URL
    let asset: AppUpdateAsset
}

struct AppUpdateAsset: Equatable {
    let name: String
    let downloadURL: URL
    let size: Int
    let digest: String?
}

struct DownloadedAppUpdate: Equatable {
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
        let data = try Data(contentsOf: fileURL)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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

private extension String {
    var shellQuoted: String {
        "'\(replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    var appleScriptQuoted: String {
        "\"\(replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
