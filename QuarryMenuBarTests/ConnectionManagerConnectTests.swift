@testable import QuarryMenuBar
import XCTest

/// Connect-ownership and cancellation behavior for `ConnectionManager`.
///
/// These cover the MenuBarExtra(`.window`) panel-teardown fix: the connect runs
/// in a manager-owned task (`connectIfNeeded`) and a cancelled attempt must never
/// surface as a user-facing `.unavailable`/`.misconfigured` state.
@MainActor
final class ConnectionManagerConnectTests: XCTestCase {

    // MARK: Internal

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testRefreshDoesNotSurfaceCancellationAsUnavailable() async throws {
        // A cancelled request maps (via QuarryClient.mapURLError) to CancellationError.
        // Reproduces the MenuBarExtra(.window) panel-teardown bug: the connect must
        // never present that cancellation as a user-facing "Unavailable" state.
        let profile = try testProfile(baseURL: XCTUnwrap(URL(string: "http://127.0.0.1:8420")))
        let manager = ConnectionManager(
            profileLoader: StubProfileLoader { profile },
            clientFactory: { _ in throw CancellationError() }
        )

        await manager.refresh()

        XCTAssertEqual(manager.state, .idle, "Cancellation must reset to .idle, not .unavailable/.misconfigured")
        XCTAssertNil(manager.profile)
        XCTAssertNil(manager.failureOrigin)
        XCTAssertNil(manager.searchViewModel)
    }

    func testRefreshDoesNotSurfaceURLCancellationAsUnavailable() async throws {
        // URLError.cancelled reaches the manager when a task is cancelled before the
        // request path resolves it to CancellationError; it must be treated the same.
        let profile = try testProfile(baseURL: XCTUnwrap(URL(string: "http://127.0.0.1:8420")))
        let manager = ConnectionManager(
            profileLoader: StubProfileLoader { profile },
            clientFactory: { _ in throw URLError(.cancelled) }
        )

        await manager.refresh()

        XCTAssertEqual(manager.state, .idle)
    }

    func testConnectIfNeededConnectsFromIdle() async throws {
        // connectIfNeeded starts the connect in a manager-owned task (the fix that
        // decouples the connect from the cancellable panel `.task`).
        let profile = try testProfile(baseURL: XCTUnwrap(URL(string: "http://127.0.0.1:8420")))
        let manager = ConnectionManager(
            profileLoader: StubProfileLoader { profile },
            clientFactory: { try mockClient(profile: $0) }
        )
        MockURLProtocol.requestHandler = successHandler

        manager.connectIfNeeded()
        try await waitFor { manager.state == .connected }

        XCTAssertEqual(manager.state, .connected)
        XCTAssertNotNil(manager.searchViewModel)
    }

    func testConnectIfNeededIsNoOpWhenNotIdle() async throws {
        // Once connected, a repeat connectIfNeeded (e.g. a later panel open) must not
        // tear down the live connection or start a redundant attempt.
        let profile = try testProfile(baseURL: XCTUnwrap(URL(string: "http://127.0.0.1:8420")))
        var loadCount = 0
        let manager = ConnectionManager(
            profileLoader: StubProfileLoader {
                loadCount += 1
                return profile
            },
            clientFactory: { try mockClient(profile: $0) }
        )
        MockURLProtocol.requestHandler = successHandler

        manager.connectIfNeeded()
        try await waitFor { manager.state == .connected }
        manager.connectIfNeeded()
        manager.connectIfNeeded()

        XCTAssertEqual(manager.state, .connected)
        XCTAssertEqual(loadCount, 1, "connectIfNeeded must not re-run once connected")
    }

    func testConnectReachesConnectedWithQuarry3SizelessShapes() async throws {
        // Regression for the quarry 3.x break: GET /v1/status omits
        // database_size_bytes and GET /v1/databases entries omit size_bytes /
        // size_description. Both decodes must succeed so the connect handshake
        // (ConnectionManager.performRefresh awaits status + databases) reaches
        // .connected rather than aborting to .unavailable.
        let profile = try testProfile(baseURL: XCTUnwrap(URL(string: "http://127.0.0.1:8420")))
        let manager = ConnectionManager(
            profileLoader: StubProfileLoader { profile },
            clientFactory: { try mockClient(profile: $0) }
        )
        MockURLProtocol.requestHandler = quarry3Handler

        manager.connectIfNeeded()
        try await waitFor { manager.state == .connected }

        XCTAssertEqual(manager.state, .connected)
        XCTAssertNotNil(manager.searchViewModel)
        XCTAssertEqual(manager.databases.count, 1)
        XCTAssertNil(manager.databases.first?.sizeBytes)
        XCTAssertNil(manager.status?.databaseSizeBytes)
    }

    // MARK: Private

    private var quarry3StatusJSON: String {
        // quarry 3.x GET /v1/status — no database_size_bytes.
        """
        {
            "document_count": 7,
            "collection_count": 1,
            "chunk_count": 42,
            "registered_directories": 0,
            "database_path": "/Users/test/.punt-labs/quarry/data/default/lancedb",
            "embedding_model": "Snowflake/snowflake-arctic-embed-m-v1.5",
            "provider": "CPUExecutionProvider (fast)",
            "embedding_dimension": 768
        }
        """
    }

    private var quarry3DatabasesJSON: String {
        // quarry 3.x GET /v1/databases — entries carry no size fields.
        """
        {
            "total_databases": 1,
            "databases": [{"name": "default", "document_count": 7}]
        }
        """
    }

    private var minimalStatusJSON: String {
        """
        {
            "document_count": 1,
            "collection_count": 1,
            "chunk_count": 1,
            "registered_directories": 0,
            "database_path": "/Users/test/.punt-labs/quarry/data/archive/lancedb",
            "database_size_bytes": 512,
            "embedding_model": "Snowflake/snowflake-arctic-embed-m-v1.5",
            "provider": "CPUExecutionProvider (fast)",
            "embedding_dimension": 768
        }
        """
    }

    private var minimalDatabasesJSON: String {
        """
        {
            "total_databases": 1,
            "databases": [{
                "name": "archive",
                "document_count": 1,
                "size_bytes": 512,
                "size_description": "512 B"
            }]
        }
        """
    }

    private func successHandler(request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let requestURL = try XCTUnwrap(request.url)
        switch requestURL.path {
        case "/health":
            return jsonResponse(#"{"status":"ok","uptime_seconds":1.0}"#, url: requestURL)
        case "/v1/status":
            return jsonResponse(minimalStatusJSON, url: requestURL)
        case "/v1/databases":
            return jsonResponse(minimalDatabasesJSON, url: requestURL)
        default:
            XCTFail("Unexpected request: \(requestURL.absoluteString)")
            return jsonResponse(#"{"error":"unexpected"}"#, statusCode: 500, url: requestURL)
        }
    }

    private func quarry3Handler(request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let requestURL = try XCTUnwrap(request.url)
        switch requestURL.path {
        case "/health":
            return jsonResponse(#"{"status":"ok","uptime_seconds":1.0}"#, url: requestURL)
        case "/v1/status":
            return jsonResponse(quarry3StatusJSON, url: requestURL)
        case "/v1/databases":
            return jsonResponse(quarry3DatabasesJSON, url: requestURL)
        default:
            XCTFail("Unexpected request: \(requestURL.absoluteString)")
            return jsonResponse(#"{"error":"unexpected"}"#, statusCode: 500, url: requestURL)
        }
    }

    /// Poll a main-actor condition until true or a timeout elapses. Used to await
    /// the manager-owned connect task (`connectIfNeeded`), which completes
    /// asynchronously rather than on the caller's `await`.
    private func waitFor(
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "Condition not met within \(timeout)")
    }
}
