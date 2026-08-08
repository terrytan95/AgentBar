import Darwin
import Foundation

struct CLIProxyCodexCredential: Sendable {
    var identity: CodexAuthIdentity
    var authInfo: CodexUsageAuthInfo
    var accessTokenExpiresAt: Date?
}

struct CLIProxyCodexDiscovery: Sendable {
    var credentials: [CLIProxyCodexCredential]
    var scanCompleted: Bool
    var hasBroadReadPermissions: Bool
}

enum CLIProxyCodexRegistryMetadata {
    static let source = "agentbar_external_auth_source"
    static let sourceValue = "cliproxyapi"
    static let externalOnly = "agentbar_external_auth_only"
    static let accessTokenExpiresAt = "agentbar_external_access_token_expires_at"
    static let broadReadPermissions = "agentbar_cliproxyapi_broad_read_permissions"
}

struct CLIProxyCodexAuthReader {
    static let defaultRelativeAuthDirectory = ".cli-proxy-api"
    static let maximumAuthFileBytes = 64 * 1024

    var homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    var configuredDirectory: String = ""
    var now: @Sendable () -> Date = { Date() }

    func discover() -> CLIProxyCodexDiscovery {
        guard let authDirectory = authDirectory() else {
            return CLIProxyCodexDiscovery(credentials: [], scanCompleted: true, hasBroadReadPermissions: false)
        }

        let directoryDescriptor = open(authDirectory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryDescriptor >= 0 else {
            return CLIProxyCodexDiscovery(
                credentials: [],
                scanCompleted: errno == ENOENT,
                hasBroadReadPermissions: false
            )
        }
        guard let directory = fdopendir(directoryDescriptor) else {
            close(directoryDescriptor)
            return CLIProxyCodexDiscovery(credentials: [], scanCompleted: false, hasBroadReadPermissions: false)
        }
        defer { closedir(directory) }

        var directoryInfo = stat()
        guard fstat(dirfd(directory), &directoryInfo) == 0,
              (directoryInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              directoryInfo.st_uid == geteuid()
        else {
            return CLIProxyCodexDiscovery(credentials: [], scanCompleted: false, hasBroadReadPermissions: false)
        }

        var credentials: [CLIProxyCodexCredential] = []
        var scanCompleted = true
        var hasBroadReadPermissions = directoryInfo.st_mode & mode_t(0o077) != 0

        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                if errno != 0 { scanCompleted = false }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
                    String(cString: $0)
                }
            }
            guard name != ".", name != "..", name.hasSuffix(".json") else { continue }

            let first = readAuthFile(named: name, directoryDescriptor: dirfd(directory))
            if case let .credential(credential, broadPermissions) = first {
                credentials.append(credential)
                hasBroadReadPermissions = hasBroadReadPermissions || broadPermissions
                continue
            }
            guard case .retryable = first else { continue }

            usleep(25_000)
            let second = readAuthFile(named: name, directoryDescriptor: dirfd(directory))
            if case let .credential(credential, broadPermissions) = second {
                credentials.append(credential)
                hasBroadReadPermissions = hasBroadReadPermissions || broadPermissions
            } else if case .retryable = second {
                scanCompleted = false
            }
        }

        return CLIProxyCodexDiscovery(
            credentials: deduplicated(credentials),
            scanCompleted: scanCompleted,
            hasBroadReadPermissions: hasBroadReadPermissions
        )
    }

    private func authDirectory() -> URL? {
        let candidates = [
            configuredDirectory.trimmingCharacters(in: .whitespacesAndNewlines),
            homebrewAuthDirectory(),
            "~/" + Self.defaultRelativeAuthDirectory
        ]
        return candidates.lazy
            .compactMap { $0 }
            .compactMap(expandedDirectory)
            .first
    }

    private func homebrewAuthDirectory() -> String? {
        for path in ["/opt/homebrew/etc/cliproxyapi.conf", "/usr/local/etc/cliproxyapi.conf"] {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  data.count <= Self.maximumAuthFileBytes,
                  let contents = String(data: data, encoding: .utf8)
            else { continue }

            for line in contents.split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("#"),
                      let separator = trimmed.firstIndex(of: ":"),
                      trimmed[..<separator].trimmingCharacters(in: .whitespaces) == "auth-dir"
                else { continue }
                let rawValue = trimmed[trimmed.index(after: separator)...]
                    .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !rawValue.isEmpty { return rawValue }
            }
        }
        return nil
    }

    private func expandedDirectory(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        let expanded: String
        if path == "~" {
            expanded = homeDirectory.path
        } else if path.hasPrefix("~/") {
            expanded = homeDirectory.appending(path: String(path.dropFirst(2))).path
        } else {
            expanded = path
        }
        guard expanded.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }

    private func readAuthFile(named name: String, directoryDescriptor: Int32) -> AuthFileRead {
        let descriptor = openat(directoryDescriptor, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return .ignored }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)

        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_uid == geteuid(),
              info.st_nlink == 1,
              info.st_mode & mode_t(0o022) == 0,
              info.st_size >= 0,
              info.st_size <= off_t(Self.maximumAuthFileBytes)
        else {
            return .ignored
        }

        guard info.st_size > 0,
              let data = try? handle.read(upToCount: Self.maximumAuthFileBytes + 1),
              data.count <= Self.maximumAuthFileBytes
        else {
            return .retryable
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .retryable
        }
        guard root["type"] as? String == "codex",
              root["disabled"] as? Bool != true,
              root["expired"] as? Bool != true,
              let identity = CodexAccountStorage.chatGPTAuthIdentity(from: data),
              let accountID = identity.accountID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accountID.isEmpty,
              let authInfo = CodexAccountStorage.usageAuthInfo(from: data)
        else {
            return .ignored
        }
        let expiration = CodexAccountStorage.accessTokenExpiration(from: data)
        guard expiration.map({ $0 > now() }) ?? true else { return .ignored }

        return .credential(
            CLIProxyCodexCredential(
                identity: identity,
                authInfo: authInfo,
                accessTokenExpiresAt: expiration
            ),
            broadPermissions: info.st_mode & mode_t(0o077) != 0
        )
    }

    private func deduplicated(_ credentials: [CLIProxyCodexCredential]) -> [CLIProxyCodexCredential] {
        Dictionary(grouping: credentials) { credential in
            let email = credential.identity.email?.lowercased() ?? ""
            return "\(credential.authInfo.accountID)|\(email)"
        }
            .compactMap { _, matches in
                return matches.max { lhs, rhs in
                    (lhs.accessTokenExpiresAt ?? .distantPast) < (rhs.accessTokenExpiresAt ?? .distantPast)
                }
            }
    }

    private enum AuthFileRead {
        case credential(CLIProxyCodexCredential, broadPermissions: Bool)
        case retryable
        case ignored
    }
}
