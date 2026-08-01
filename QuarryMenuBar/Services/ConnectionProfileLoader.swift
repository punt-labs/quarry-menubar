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
    case insecureRemoteProxyURL(String)
    case missingProxyCACertificate(URL)
    case missingPinnedCACertificate(URL)
    case invalidAuthorizationHeader(String)
    case missingLocalCACertificate(URL)
    case daemonNotRunning(URL)
    case serveTokenUnreadable(URL)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .malformedProxyConfig(url, message):
            "Malformed Quarry connection profile at \(url.path): \(message)"
        case let .missingProxyURL(url):
            "Quarry connection profile at \(url.path) is missing a URL."
        case let .invalidProxyURL(value):
            "Invalid Quarry connection URL: \(value)"
        case let .insecureRemoteProxyURL(value):
            "Remote Quarry connections must use `https://` or `wss://`: \(value)"
        case let .missingProxyCACertificate(url):
            "Quarry connection profile at \(url.path) is missing a `ca_cert` entry for its HTTPS connection."
        case let .missingPinnedCACertificate(url):
            "Pinned CA certificate not found at \(url.path)."
        case let .invalidAuthorizationHeader(value):
            "Unsupported Authorization header in Quarry profile: \(value)"
        case let .missingLocalCACertificate(url):
            "Local Quarry CA certificate not found at \(url.path)."
        case let .daemonNotRunning(url):
            "Quarry daemon is not running — no `serve.port` at \(url.path). "
                + "Run `quarry install` or start `quarryd`, then retry."
        case let .serveTokenUnreadable(url):
            "Quarry daemon's `serve.token` is missing or unreadable at \(url.path). "
                + "Ensure `quarryd` is running (run `quarry install`)."
        }
    }

    var connectionOrigin: ConnectionOrigin {
        switch self {
        case .malformedProxyConfig,
             .missingProxyURL,
             .invalidProxyURL,
             .insecureRemoteProxyURL,
             .missingProxyCACertificate,
             .missingPinnedCACertificate,
             .invalidAuthorizationHeader:
            .proxyConfig
        case .missingLocalCACertificate,
             .daemonNotRunning,
             .serveTokenUnreadable:
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
        localCAURL: URL = Self.defaultLocalCAURL,
        dataRootURL: URL = Self.defaultDataRootURL,
        quarryConfigURL: URL = Self.defaultQuarryConfigURL
    ) {
        self.fileManager = fileManager
        self.proxyConfigURL = proxyConfigURL
        self.localCAURL = localCAURL
        self.dataRootURL = dataRootURL
        self.quarryConfigURL = quarryConfigURL
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

    /// Root of the daemon's per-database run directories (`~/.punt-labs/quarry/data`).
    /// Each database's `serve.port` / `serve.token` sidecars live beside its
    /// LanceDB data under `<dataRoot>/<db>/` (mirrors quarry's `Settings.quarry_root`).
    static let defaultDataRootURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".punt-labs")
        .appendingPathComponent("quarry")
        .appendingPathComponent("data")

    /// The daemon's persistent config (`~/.punt-labs/quarry/config.toml`), whose
    /// `[default] database` names the startup database whose run dir holds the
    /// live `serve.token` (mirrors quarry's `Settings.read_default_db`).
    static let defaultQuarryConfigURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".punt-labs")
        .appendingPathComponent("quarry")
        .appendingPathComponent("config.toml")

    /// Resolve the daemon target, mirroring quarry's `TargetResolver.resolve`
    /// precedence (`quarry/client/resolver.py`) minus the `QUARRY_URL` env tier:
    ///
    /// 1. a stored remote login (`quarry.toml`) whose host is genuinely remote;
    /// 2. otherwise the local daemon on literal loopback, authenticated with the
    ///    live `serve.token` read from the startup database's run directory.
    ///
    /// A `quarry.toml` pointing at a loopback host is intentionally ignored here
    /// and falls through to the loopback path: the daemon now requires its live
    /// `serve.token` on every loopback request (DES-031 v2.2 R4), and that token
    /// is not stored in the toml. Reading it live from the run dir is the only
    /// correct source (it rotates on every daemon restart).
    ///
    /// The `QUARRY_URL`/`QUARRY_TOKEN` env tier that quarry's CLI honors is
    /// deliberately not implemented: the app launches via `open`, which does not
    /// propagate the shell environment, so an env tier would be an untestable,
    /// never-exercised path in this GUI context.
    func load() throws -> ConnectionProfile {
        if fileManager.fileExists(atPath: proxyConfigURL.path),
           let profile = try loadRemoteProxyProfile() {
            return profile
        }
        return try loadLoopbackProfile()
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
    private let dataRootURL: URL
    private let quarryConfigURL: URL

    /// Build a `.remote` profile from `quarry.toml`, or return `nil` to fall
    /// through to the loopback path.
    ///
    /// Returns `nil` when the file has no usable `[quarry].url`, or when that URL
    /// names a loopback host — a loopback login carries no usable credential now
    /// that the daemon authenticates loopback with its live `serve.token`, so the
    /// loopback path (which reads that token) is authoritative. A `[quarry]`
    /// section with a *missing* url throws `missingProxyURL`: that is a
    /// half-written remote login the operator should see, not silently demote to
    /// local. A malformed url throws `invalidProxyURL` for the same reason.
    private func loadRemoteProxyProfile() throws -> ConnectionProfile? {
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
              let parsedHost = components.host,
              let scheme = components.scheme?.lowercased()
        else {
            throw ConnectionProfileLoaderError.invalidProxyURL(urlString)
        }

        // `URLComponents.host` surfaces IPv6 literals in bracketed form (`[::1]`). Strip the
        // brackets only for host comparison and display; the value assigned back to
        // `URLComponents.host` must keep its brackets, or a remote IPv6 literal fails to build.
        let bareHost = strippingIPv6Brackets(parsedHost)
        // A loopback login is not a remote target: fall through to serve.token.
        guard !isLocalHost(bareHost) else {
            return nil
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
        // Remote hosts (including IPv6 literals) keep the bracketed form Foundation
        // parsed so the URL still builds; the toml URL's path (e.g. `/mcp`) is dropped
        // so the client can address `/v1/...` at the server root.
        baseComponents.host = parsedHost
        baseComponents.port = components.port ?? 8420

        guard let baseURL = baseComponents.url else {
            throw ConnectionProfileLoaderError.invalidProxyURL(urlString)
        }

        if baseScheme != "https" {
            throw ConnectionProfileLoaderError.insecureRemoteProxyURL(urlString)
        }

        let caURL = try resolvedCAURL(path: config.caCertPath, required: true)
        let token = try parseBearerToken(from: config.authorizationHeader)
        return ConnectionProfile(
            mode: .remote,
            origin: .proxyConfig,
            baseURL: baseURL,
            caCertificateURL: caURL,
            authToken: token,
            hostDisplayName: bareHost
        )
    }

    /// Build the local-daemon profile on literal loopback, authenticated with the
    /// daemon's live `serve.token`.
    ///
    /// Mirrors quarry's `TargetResolver._loopback_default` (`resolver.py`): the
    /// bound port comes from `serve.port` and the bearer from `serve.token`, both
    /// read from the startup database's run directory. The connection targets the
    /// `127.0.0.1` literal — never the ambiguous `localhost` name a dual-stack
    /// resolver could redirect — and pins the local CA. Fails closed: a missing
    /// `serve.port` (daemon down) or an unreadable/empty `serve.token` surfaces a
    /// clear `.misconfigured` error rather than a bare 401 far from its cause.
    private func loadLoopbackProfile() throws -> ConnectionProfile {
        let runDir = dataRootURL.appendingPathComponent(activeDatabaseName())
        let portURL = runDir.appendingPathComponent("serve.port")
        let tokenURL = runDir.appendingPathComponent("serve.token")

        let port = try loopbackPort(portURL)
        let token = try serveToken(tokenURL)

        guard fileManager.fileExists(atPath: localCAURL.path) else {
            throw ConnectionProfileLoaderError.missingLocalCACertificate(localCAURL)
        }

        let baseString = "https://127.0.0.1:\(port)"
        guard let baseURL = URL(string: baseString) else {
            throw ConnectionProfileLoaderError.invalidProxyURL(baseString)
        }

        return ConnectionProfile(
            mode: .local,
            origin: .localDefault,
            baseURL: baseURL,
            caCertificateURL: localCAURL,
            authToken: token,
            hostDisplayName: "localhost"
        )
    }

    /// Read the daemon's bound port from `serve.port`, or fail closed.
    private func loopbackPort(_ portURL: URL) throws -> Int {
        guard fileManager.fileExists(atPath: portURL.path),
              let raw = try? String(contentsOf: portURL, encoding: .utf8),
              let port = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              port > 0
        else {
            throw ConnectionProfileLoaderError.daemonNotRunning(portURL)
        }
        return port
    }

    /// Read the daemon's live loopback bearer from `serve.token`, or fail closed.
    private func serveToken(_ tokenURL: URL) throws -> String {
        guard fileManager.fileExists(atPath: tokenURL.path),
              let raw = try? String(contentsOf: tokenURL, encoding: .utf8)
        else {
            throw ConnectionProfileLoaderError.serveTokenUnreadable(tokenURL)
        }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw ConnectionProfileLoaderError.serveTokenUnreadable(tokenURL)
        }
        return token
    }

    /// Name the startup database whose run dir holds the live `serve.token`.
    ///
    /// Mirrors quarry's `Settings.read_default_db` (`config.py`): read
    /// `config.toml`'s `[default] database`; if present and not the literal
    /// `"default"`, that names the run dir. Absent, unreadable, or `"default"`
    /// falls back to `"default"`. A name containing a path separator is rejected
    /// (it would escape the data root) and falls back to `"default"`.
    private func activeDatabaseName() -> String {
        guard fileManager.fileExists(atPath: quarryConfigURL.path),
              let contents = try? String(contentsOf: quarryConfigURL, encoding: .utf8)
        else {
            return "default"
        }
        guard let name = parseDefaultDatabase(contents),
              name != "default",
              !name.contains("/"),
              !name.contains("\\"),
              name != ".",
              name != ".."
        else {
            return "default"
        }
        return name
    }

    /// Extract `[default] database = "..."` from a `config.toml` body, or `nil`.
    private func parseDefaultDatabase(_ contents: String) -> String? {
        var inDefaultSection = false
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line == "[default]" {
                inDefaultSection = true
                continue
            }
            if line.hasPrefix("[") {
                inDefaultSection = false
                continue
            }
            guard inDefaultSection, let equalsIndex = line.firstIndex(of: "=") else { continue }
            let key = line[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard key == "database" else { continue }
            let valueSlice = line[line.index(after: equalsIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return try? parseQuotedString(valueSlice)
        }
        return nil
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
                throw ConnectionProfileLoaderError.missingProxyCACertificate(proxyConfigURL)
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

    /// Recognizes the canonical loopback host forms the loader normalizes to IPv4.
    ///
    /// The allow-list is deliberately narrow: non-canonical loopback spellings such as the expanded
    /// IPv6 form `0:0:0:0:0:0:0:1`, a zone-scoped `::1%lo0`, or any `127.0.0.0/8` address other than
    /// `127.0.0.1` are not recognized and fall through to `.remote`. They are not produced by the
    /// Quarry config writer, so handling them is out of scope for this fix.
    private func isLocalHost(_ host: String) -> Bool {
        ["localhost", "127.0.0.1", "::1"].contains(host.lowercased())
    }

    /// Removes the surrounding brackets from an IPv6 host literal (`[::1]` -> `::1`).
    ///
    /// `URLComponents.host` returns IPv6 addresses in bracketed form. Hosts without enclosing
    /// brackets are returned unchanged.
    private func strippingIPv6Brackets(_ host: String) -> String {
        guard host.hasPrefix("["), host.hasSuffix("]"), host.count >= 2 else { return host }
        return String(host.dropFirst().dropLast())
    }
}
