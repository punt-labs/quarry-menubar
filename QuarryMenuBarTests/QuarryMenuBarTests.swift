@testable import QuarryMenuBar
import XCTest

@MainActor
final class ContentPanelTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testContentPanelInitializesWhenConnected() async {
        let manager = ConnectionManager(
            profileLoader: StubProfileLoader { testProfile() },
            clientFactory: { try mockClient(profile: $0) }
        )

        MockURLProtocol.requestHandler = { request in
            let requestURL = try XCTUnwrap(request.url)
            switch requestURL.path {
            case "/health":
                return jsonResponse(#"{"status":"ok","uptime_seconds":1.0}"#, url: requestURL)
            case "/status":
                return jsonResponse(
                    """
                    {
                        "document_count": 1,
                        "collection_count": 1,
                        "chunk_count": 1,
                        "registered_directories": 0,
                        "database_path": "/Users/test/.punt-labs/quarry/data/default/lancedb",
                        "database_size_bytes": 512,
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
                            "name": "default",
                            "document_count": 1,
                            "size_bytes": 512,
                            "size_description": "512 B"
                        }]
                    }
                    """,
                    url: requestURL
                )
            default:
                return jsonResponse(#"{"error":"unexpected"}"#, statusCode: 500, url: requestURL)
            }
        }

        await manager.refresh()

        let panel = ContentPanel(connectionManager: manager)
        XCTAssertNotNil(panel.body)
    }

    func testUnavailableHintForLocalConnectionMentionsAuthenticatedRemoteLogin() {
        XCTAssertEqual(
            ContentPanel.unavailableHint(for: .local),
            "Run `quarry install` to set up local Quarry, or run `quarry login <host> --api-key <token>` to point Quarry at a remote server. You can also set `QUARRY_API_KEY` before running `quarry login <host>`."
        )
    }

    func testUnavailableHintForRemoteConnectionMentionsPinnedCAAndToken() {
        XCTAssertEqual(
            ContentPanel.unavailableHint(for: .remote),
            "Check that the remote Quarry server is reachable and that its pinned CA and token are still valid."
        )
    }

    func testConfigurationHintForProxyConfigMentionsLoginAndLogoutRecovery() {
        XCTAssertEqual(
            ContentPanel.configurationHint(for: .proxyConfig),
            "Fix `~/.punt-labs/mcp-proxy/quarry.toml`, rerun `quarry login <host> --api-key <token>` (or set `QUARRY_API_KEY` first), or run `quarry logout` if you want the app to return to local Quarry."
        )
    }

    func testConfigurationHintForLocalDefaultMentionsInstallOrAuthenticatedLogin() {
        XCTAssertEqual(
            ContentPanel.configurationHint(for: .localDefault),
            "Run `quarry install` to create the local TLS certificates and daemon, or run `quarry login <host> --api-key <token>` to use a remote server. You can also set `QUARRY_API_KEY` before running `quarry login <host>`."
        )
    }
}
