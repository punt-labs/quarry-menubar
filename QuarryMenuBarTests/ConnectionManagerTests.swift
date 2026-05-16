@testable import QuarryMenuBar
import XCTest

@MainActor
final class ConnectionManagerTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testRefreshConnectsAndBuildsSearchViewModel() async throws {
        let profile = try testProfile(baseURL: XCTUnwrap(URL(string: "http://127.0.0.1:8420")))
        let manager = ConnectionManager(
            profileLoader: StubProfileLoader { profile },
            clientFactory: { try mockClient(profile: $0) }
        )

        MockURLProtocol.requestHandler = { request in
            let requestURL = try XCTUnwrap(request.url)
            switch requestURL.path {
            case "/health":
                return jsonResponse(#"{"status":"ok","uptime_seconds":1.5}"#, url: requestURL)
            case "/status":
                return jsonResponse(
                    """
                    {
                        "document_count": 2,
                        "collection_count": 1,
                        "chunk_count": 6,
                        "registered_directories": 1,
                        "database_path": "/Users/test/.punt-labs/quarry/data/archive/lancedb",
                        "database_size_bytes": 1024,
                        "embedding_model": "Snowflake/snowflake-arctic-embed-m-v1.5",
                        "provider": "CPUExecutionProvider (fast)",
                        "embedding_dimension": 768
                    }
                    """,
                    url: requestURL
                )
            case "/databases":
                return jsonResponse(
                    """
                    {
                        "total_databases": 1,
                        "databases": [{
                            "name": "archive",
                            "document_count": 2,
                            "size_bytes": 1024,
                            "size_description": "1.0 KB"
                        }]
                    }
                    """,
                    url: requestURL
                )
            default:
                XCTFail("Unexpected request: \(requestURL.absoluteString)")
                return jsonResponse(#"{"error":"unexpected"}"#, statusCode: 500, url: requestURL)
            }
        }

        await manager.refresh()

        XCTAssertEqual(manager.state, .connected)
        XCTAssertEqual(manager.profile, profile)
        XCTAssertEqual(manager.activeDatabaseName, "archive")
        XCTAssertEqual(manager.status?.provider, "CPUExecutionProvider (fast)")
        XCTAssertNotNil(manager.searchViewModel)
        XCTAssertTrue(manager.allowsLocalFileAccess)
    }

    func testRefreshMapsLoaderFailureToMisconfigured() async {
        let missingCA = FileManager.default.temporaryDirectory.appendingPathComponent("missing-ca.crt")
        let manager = ConnectionManager(
            profileLoader: StubProfileLoader {
                throw ConnectionProfileLoaderError.missingLocalCACertificate(missingCA)
            },
            clientFactory: { _ in
                XCTFail("clientFactory should not be called when load fails")
                return try mockClient()
            }
        )

        await manager.refresh()

        guard case let .misconfigured(message) = manager.state else {
            XCTFail("Expected misconfigured state, got \(manager.state)")
            return
        }
        XCTAssertTrue(message.contains("CA certificate"))
        XCTAssertNil(manager.searchViewModel)
    }

    func testRefreshMapsConfigurationClientFailureToMisconfigured() async throws {
        let profile = try testProfile(baseURL: XCTUnwrap(URL(string: "http://127.0.0.1:8420")))
        let manager = ConnectionManager(
            profileLoader: StubProfileLoader { profile },
            clientFactory: { _ in
                throw QuarryClientError.unauthorized
            }
        )

        await manager.refresh()

        guard case let .misconfigured(message) = manager.state else {
            XCTFail("Expected misconfigured state, got \(manager.state)")
            return
        }
        XCTAssertTrue(message.contains("Authentication failed"))
        XCTAssertEqual(manager.profile, profile)
    }

    func testRefreshMapsAvailabilityFailureToUnavailable() async throws {
        let profile = try testProfile(
            baseURL: XCTUnwrap(URL(string: "https://okinos.user.home.lab:8420")),
            mode: .remote,
            origin: .proxyConfig,
            hostDisplayName: "okinos.user.home.lab"
        )
        let manager = ConnectionManager(
            profileLoader: StubProfileLoader { profile },
            clientFactory: { _ in
                throw QuarryClientError.unreachable("timed out")
            }
        )

        await manager.refresh()

        guard case let .unavailable(message) = manager.state else {
            XCTFail("Expected unavailable state, got \(manager.state)")
            return
        }
        XCTAssertTrue(message.contains("Could not reach Quarry"))
        XCTAssertEqual(manager.profile, profile)
        XCTAssertFalse(manager.allowsLocalFileAccess)
    }
}
