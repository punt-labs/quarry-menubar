import Foundation

// MARK: - ConnectionProfileLoading

protocol ConnectionProfileLoading {
    func load() throws -> ConnectionProfile
}

// MARK: - ConnectionProfileLoaderError

enum ConnectionProfileLoaderError: LocalizedError {
    case malformedProxyConfig(URL, String)
    case missingProxyURL(URL)
    case invalidProxyURL(String)
    case missingPinnedCACertificate(URL)
    case invalidAuthorizationHeader(String)
    case missingLocalCACertificate(URL)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .malformedProxyConfig(url, message):
            "Malformed Quarry connection profile at \(url.path): \(message)"
        case let .missingProxyURL(url):
            "Quarry connection profile at \(url.path) is missing a URL."
        case let .invalidProxyURL(value):
            "Invalid Quarry connection URL: \(value)"
        case let .missingPinnedCACertificate(url):
            "Pinned CA certificate not found at \(url.path)."
        case let .invalidAuthorizationHeader(value):
            "Unsupported Authorization header in Quarry profile: \(value)"
        case let .missingLocalCACertificate(url):
            "Local Quarry CA certificate not found at \(url.path)."
        }
    }

    var connectionOrigin: ConnectionOrigin {
        switch self {
        case .malformedProxyConfig,
             .missingProxyURL,
             .invalidProxyURL,
             .missingPinnedCACertificate,
             .invalidAuthorizationHeader:
            .proxyConfig
        case .missingLocalCACertificate:
            .localDefault
        }
    }
}

// MARK: - ConnectionProfileLoader

struct ConnectionProfileLoader: ConnectionProfileLoading {

    // MARK: Lifecycle

    init(
        fileManager: FileManager = .default,
        proxyConfigURL: URL = Self.defaultProxyConfigURL,
        localCAURL: URL = Self.defaultLocalCAURL
    ) {
        self.fileManager = fileManager
        self.proxyConfigURL = proxyConfigURL
        self.localCAURL = localCAURL
    }

    // MARK: Internal

    static let defaultProxyConfigURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".punt-labs")
        .appendingPathComponent("mcp-proxy")
        .appendingPathComponent("quarry.toml")

    static let defaultLocalCAURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".punt-labs")
        .appendingPathComponent("quarry")
        .appendingPathComponent("tls")
        .appendingPathComponent("ca.crt")

    func load() throws -> ConnectionProfile {
        if fileManager.fileExists(atPath: proxyConfigURL.path),
           let profile = try loadProxyConfigProfile() {
            return profile
        }
        return try loadDefaultLocalProfile()
    }

    // MARK: Private

    private enum Section {
        case none
        case quarry
        case quarryHeaders
    }

    private struct ProxyConfig {
        var containsQuarrySection = false
        var url: String?
        var caCertPath: String?
        var authorizationHeader: String?
    }

    private let fileManager: FileManager
    private let proxyConfigURL: URL
    private let localCAURL: URL

    private func loadProxyConfigProfile() throws -> ConnectionProfile? {
        let contents: String
        do {
            contents = try String(contentsOf: proxyConfigURL, encoding: .utf8)
        } catch {
            throw ConnectionProfileLoaderError.malformedProxyConfig(
                proxyConfigURL,
                error.localizedDescription
            )
        }

        let config = try parseProxyConfig(contents)
        guard config.containsQuarrySection else {
            return nil
        }
        guard let urlString = config.url else {
            throw ConnectionProfileLoaderError.missingProxyURL(proxyConfigURL)
        }

        guard let profileURL = URL(string: urlString),
              let components = URLComponents(url: profileURL, resolvingAgainstBaseURL: false),
              let host = components.host,
              let scheme = components.scheme?.lowercased()
        else {
            throw ConnectionProfileLoaderError.invalidProxyURL(urlString)
        }

        let baseScheme: String
        switch scheme {
        case "ws":
            baseScheme = "http"
        case "wss":
            baseScheme = "https"
        case "http",
             "https":
            baseScheme = scheme
        default:
            throw ConnectionProfileLoaderError.invalidProxyURL(urlString)
        }

        var baseComponents = URLComponents()
        baseComponents.scheme = baseScheme
        baseComponents.host = host
        baseComponents.port = components.port ?? 8420

        guard let baseURL = baseComponents.url else {
            throw ConnectionProfileLoaderError.invalidProxyURL(urlString)
        }

        let caURL = try resolvedCAURL(path: config.caCertPath, required: baseScheme == "https")
        let token = try parseBearerToken(from: config.authorizationHeader)
        return ConnectionProfile(
            mode: isLocalHost(host) ? .local : .remote,
            origin: .proxyConfig,
            baseURL: baseURL,
            caCertificateURL: caURL,
            authToken: token,
            hostDisplayName: host
        )
    }

    private func loadDefaultLocalProfile() throws -> ConnectionProfile {
        guard fileManager.fileExists(atPath: localCAURL.path) else {
            throw ConnectionProfileLoaderError.missingLocalCACertificate(localCAURL)
        }

        guard let baseURL = URL(string: "https://localhost:8420") else {
            throw ConnectionProfileLoaderError.invalidProxyURL("https://localhost:8420")
        }

        return ConnectionProfile(
            mode: .local,
            origin: .localDefault,
            baseURL: baseURL,
            caCertificateURL: localCAURL,
            authToken: nil,
            hostDisplayName: "localhost"
        )
    }

    private func parseProxyConfig(_ contents: String) throws -> ProxyConfig {
        var config = ProxyConfig()
        var section = Section.none

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if line == "[quarry]" {
                section = .quarry
                config.containsQuarrySection = true
                continue
            }
            if line == "[quarry.headers]" {
                section = .quarryHeaders
                config.containsQuarrySection = true
                continue
            }
            if line.hasPrefix("[") {
                section = .none
                continue
            }

            guard section == .quarry || section == .quarryHeaders else { continue }
            guard let equalsIndex = line.firstIndex(of: "=") else {
                throw ConnectionProfileLoaderError.malformedProxyConfig(
                    proxyConfigURL,
                    "Expected key/value pair in line: \(line)"
                )
            }

            let key = line[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let valueSlice = line[line.index(after: equalsIndex)...]
            let value = try parseQuotedString(
                valueSlice.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            switch (section, key) {
            case (.quarry, "url"):
                config.url = value
            case (.quarry, "ca_cert"):
                config.caCertPath = value
            case (.quarryHeaders, "Authorization"):
                config.authorizationHeader = value
            default:
                continue
            }
        }

        return config
    }

    private func parseQuotedString(_ raw: String) throws -> String {
        guard raw.count >= 2, raw.first == "\"", raw.last == "\"" else {
            throw ConnectionProfileLoaderError.malformedProxyConfig(
                proxyConfigURL,
                "Expected TOML basic string, got: \(raw)"
            )
        }

        var result = ""
        var escaping = false
        for character in raw.dropFirst().dropLast() {
            if escaping {
                switch character {
                case "\\": result.append("\\")
                case "\"": result.append("\"")
                case "n": result.append("\n")
                case "t": result.append("\t")
                default:
                    result.append(character)
                }
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }

        if escaping {
            throw ConnectionProfileLoaderError.malformedProxyConfig(
                proxyConfigURL,
                "Unterminated escape sequence in TOML string."
            )
        }
        return result
    }

    private func resolvedCAURL(
        path: String?,
        required: Bool
    ) throws -> URL? {
        guard let path else {
            if required {
                throw ConnectionProfileLoaderError.missingPinnedCACertificate(proxyConfigURL)
            }
            return nil
        }

        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        guard fileManager.fileExists(atPath: url.path) else {
            throw ConnectionProfileLoaderError.missingPinnedCACertificate(url)
        }
        return url
    }

    private func parseBearerToken(from header: String?) throws -> String? {
        guard let header else { return nil }
        guard header.hasPrefix("Bearer ") else {
            throw ConnectionProfileLoaderError.invalidAuthorizationHeader(header)
        }

        let token = String(header.dropFirst("Bearer ".count)).trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else {
            throw ConnectionProfileLoaderError.invalidAuthorizationHeader(header)
        }
        return token
    }

    private func isLocalHost(_ host: String) -> Bool {
        ["localhost", "127.0.0.1", "::1"].contains(host.lowercased())
    }
}
