import Foundation

// MARK: - QuarryClientError

enum QuarryClientError: LocalizedError {
    case invalidBaseURL(String)
    case missingCACertificate(String)
    case invalidCACertificate(String)
    case unauthorized
    case httpError(statusCode: Int, message: String)
    case unreachable(String)
    case tlsValidationFailed(String)
    case networkError(String)
    case decodingError(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .invalidBaseURL(url):
            "Invalid Quarry URL: \(url)"
        case let .missingCACertificate(path):
            "Pinned CA certificate not found at \(path)"
        case let .invalidCACertificate(path):
            "Could not read pinned CA certificate at \(path)"
        case .unauthorized:
            "Authentication failed. Check the configured Quarry token."
        case let .httpError(code, message):
            "HTTP \(code): \(message)"
        case let .unreachable(message):
            "Could not reach Quarry: \(message)"
        case let .tlsValidationFailed(message):
            "TLS validation failed: \(message)"
        case let .networkError(message):
            "Network error: \(message)"
        case let .decodingError(message):
            "Failed to decode response: \(message)"
        }
    }

    var isConfigurationIssue: Bool {
        switch self {
        case .invalidBaseURL,
             .missingCACertificate,
             .invalidCACertificate,
             .unauthorized:
            true
        case .httpError,
             .unreachable,
             .tlsValidationFailed,
             .networkError,
             .decodingError:
            false
        }
    }
}

// MARK: - QuarryClient

/// HTTP client for the Quarry API.
final class QuarryClient {

    // MARK: Lifecycle

    init(
        profile: ConnectionProfile,
        session: URLSession? = nil
    ) throws {
        self.profile = profile
        if let session {
            self.session = session
            sessionDelegate = nil
        } else {
            let (builtSession, delegate) = try Self.makeSession(for: profile)
            self.session = builtSession
            sessionDelegate = delegate
        }
    }

    // MARK: Internal

    // MARK: - Public API

    func health() async throws -> HealthResponse {
        try await get("/health")
    }

    func search(
        query: String,
        limit: Int = 10,
        collection: String? = nil
    ) async throws -> SearchResponse {
        var params = ["q": query, "limit": String(limit)]
        if let collection {
            params["collection"] = collection
        }
        return try await get("/search", params: params)
    }

    func documents(collection: String? = nil) async throws -> DocumentsResponse {
        var params: [String: String] = [:]
        if let collection {
            params["collection"] = collection
        }
        return try await get("/documents", params: params)
    }

    func collections() async throws -> CollectionsResponse {
        try await get("/collections")
    }

    func status() async throws -> StatusResponse {
        try await get("/status")
    }

    func databases() async throws -> DatabasesResponse {
        try await get("/databases")
    }

    func show(
        document: String,
        page: Int,
        collection: String? = nil
    ) async throws -> ShowPageResponse {
        var params: [String: String] = [
            "document": document,
            "page": String(page)
        ]
        if let collection {
            params["collection"] = collection
        }
        return try await get("/show", params: params)
    }

    // MARK: Private

    private let session: URLSession
    private let sessionDelegate: PinnedCASessionDelegate?
    private let profile: ConnectionProfile

    private static func makeSession(
        for profile: ConnectionProfile
    ) throws -> (URLSession, PinnedCASessionDelegate?) {
        let configuration = URLSessionConfiguration.ephemeral

        guard profile.usesTLS else {
            return (URLSession(configuration: configuration), nil)
        }

        guard let caURL = profile.caCertificateURL else {
            throw QuarryClientError.missingCACertificate("(missing from connection profile)")
        }
        guard FileManager.default.fileExists(atPath: caURL.path) else {
            throw QuarryClientError.missingCACertificate(caURL.path)
        }

        let certificateData: Data
        do {
            certificateData = try Data(contentsOf: caURL)
        } catch {
            throw QuarryClientError.invalidCACertificate(caURL.path)
        }

        let delegate: PinnedCASessionDelegate
        do {
            delegate = try PinnedCASessionDelegate(certificateData: certificateData)
        } catch {
            throw QuarryClientError.invalidCACertificate(caURL.path)
        }
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
        return (session, delegate)
    }

    private func get<T: Decodable>(
        _ path: String,
        params: [String: String] = [:]
    ) async throws -> T {
        let base = try resolveBaseURL()
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(
            url: base.appendingPathComponent(normalizedPath),
            resolvingAgainstBaseURL: false
        ) else {
            throw QuarryClientError.invalidBaseURL(path)
        }

        if !params.isEmpty {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components.url else {
            throw QuarryClientError.invalidBaseURL(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = profile.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw mapURLError(error)
        } catch {
            throw QuarryClientError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuarryClientError.networkError("Non-HTTP response")
        }

        if httpResponse.statusCode == 401 {
            throw QuarryClientError.unauthorized
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message: String = if let errorBody = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                errorBody.error
            } else {
                String(data: data, encoding: .utf8) ?? "Unknown error"
            }
            throw QuarryClientError.httpError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw QuarryClientError.decodingError(error.localizedDescription)
        }
    }

    private func resolveBaseURL() throws -> URL {
        guard profile.baseURL.scheme != nil,
              profile.baseURL.host != nil
        else {
            throw QuarryClientError.invalidBaseURL(profile.baseURL.absoluteString)
        }
        return profile.baseURL
    }

    private func mapURLError(_ error: URLError) -> QuarryClientError {
        switch error.code {
        case .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .notConnectedToInternet,
             .timedOut,
             .dnsLookupFailed:
            return .unreachable(error.localizedDescription)
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .clientCertificateRejected,
             .clientCertificateRequired,
             .appTransportSecurityRequiresSecureConnection:
            return .tlsValidationFailed(error.localizedDescription)
        default:
            return .networkError(error.localizedDescription)
        }
    }
}
