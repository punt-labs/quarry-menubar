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

    func testContentPanelInitializesWhenMisconfigured() async {
        let missingCA = FileManager.default.temporaryDirectory.appendingPathComponent("missing-ca.crt")
        let manager = ConnectionManager(
            profileLoader: StubProfileLoader {
                throw ConnectionProfileLoaderError.missingLocalCACertificate(missingCA)
            },
            clientFactory: { try mockClient(profile: $0) }
        )

        await manager.refresh()

        let panel = ContentPanel(connectionManager: manager)
        XCTAssertNotNil(panel.body)
    }
}
