import Foundation

// MARK: - QuarryClientError

enum QuarryClientError: LocalizedError {
    case serverNotRunning
    case invalidURL(String)
    case httpError(statusCode: Int, message: String)
    case decodingError(Error)
    case networkError(Error)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .serverNotRunning:
            "Quarry server is not running. Start it with: quarry serve"
        case let .invalidURL(url):
            "Invalid URL: \(url)"
        case let .httpError(code, message):
            "HTTP \(code): \(message)"
        case let .decodingError(error):
            "Failed to decode response: \(error.localizedDescription)"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - QuarryClient

/// HTTP client for the `quarry serve` localhost API.
///
/// Discovers the server port by reading `~/.quarry/data/<db>/serve.port`,
/// then issues GET requests against the JSON endpoints.
final class QuarryClient: Sendable {

    // MARK: Lifecycle

    init(
        databaseName: String = "default",
        session: URLSession = .shared
    ) {
        self.databaseName = databaseName
        self.session = session
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

    // MARK: Private

    private let session: URLSession
    private let databaseName: String

    // MARK: - Port Discovery

    private func resolveBaseURL() throws -> URL {
        let port = try readPort()
        guard let url = URL(string: "http://127.0.0.1:\(port)") else {
            throw QuarryClientError.invalidURL("http://127.0.0.1:\(port)")
        }
        return url
    }

    private func readPort() throws -> Int {
        let portFile = quarryDataPath()
            .appendingPathComponent(databaseName)
            .appendingPathComponent("serve.port")

        guard let contents = try? String(contentsOf: portFile, encoding: .utf8),
              let port = Int(contents.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            throw QuarryClientError.serverNotRunning
        }
        return port
    }

    private func quarryDataPath() -> URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".quarry")
            .appendingPathComponent("data")
    }

    private func get<T: Decodable>(
        _ path: String,
        params: [String: String] = [:]
    ) async throws -> T {
        let base = try resolveBaseURL()
        guard var components = URLComponents(
            url: base.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw QuarryClientError.invalidURL(path)
        }

        if !params.isEmpty {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components.url else {
            throw QuarryClientError.invalidURL(path)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw QuarryClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuarryClientError.networkError(
                NSError(domain: "QuarryClient", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Non-HTTP response"
                ])
            )
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
            throw QuarryClientError.decodingError(error)
        }
    }
}
