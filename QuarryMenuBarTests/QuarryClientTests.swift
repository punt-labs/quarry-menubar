@testable import QuarryMenuBar
import XCTest

// MARK: - QuarryModelTests

final class QuarryModelTests: XCTestCase {
    func testHealthResponseDecoding() throws {
        let json = """
        {"status": "ok", "uptime_seconds": 42.5}
        """
        let decoded = try JSONDecoder().decode(
            HealthResponse.self,
            from: XCTUnwrap(json.data(using: .utf8))
        )
        XCTAssertEqual(decoded.status, "ok")
        XCTAssertEqual(decoded.uptimeSeconds, 42.5)
    }

    func testSearchResultDecoding() throws {
        let json = """
        {
            "query": "test",
            "total_results": 1,
            "results": [{
                "document_name": "report.pdf",
                "collection": "default",
                "page_number": 3,
                "chunk_index": 0,
                "text": "Hello world",
                "page_type": "text",
                "source_format": ".pdf",
                "similarity": 0.95
            }]
        }
        """
        let decoded = try JSONDecoder().decode(
            SearchResponse.self,
            from: XCTUnwrap(json.data(using: .utf8))
        )
        XCTAssertEqual(decoded.query, "test")
        XCTAssertEqual(decoded.totalResults, 1)
        XCTAssertEqual(decoded.results[0].documentName, "report.pdf")
        XCTAssertEqual(decoded.results[0].pageNumber, 3)
        XCTAssertEqual(decoded.results[0].similarity, 0.95)
    }

    func testDocumentsResponseDecoding() throws {
        let json = """
        {
            "total_documents": 1,
            "documents": [{
                "document_name": "report.pdf",
                "document_path": "/path/to/report.pdf",
                "collection": "default",
                "total_pages": 10,
                "chunk_count": 25,
                "indexed_pages": 10,
                "ingestion_timestamp": "2026-01-01T00:00:00"
            }]
        }
        """
        let decoded = try JSONDecoder().decode(
            DocumentsResponse.self,
            from: XCTUnwrap(json.data(using: .utf8))
        )
        XCTAssertEqual(decoded.totalDocuments, 1)
        XCTAssertEqual(decoded.documents[0].documentName, "report.pdf")
        XCTAssertEqual(decoded.documents[0].totalPages, 10)
    }

    func testCollectionsResponseDecoding() throws {
        let json = """
        {
            "total_collections": 2,
            "collections": [
                {"collection": "default", "document_count": 3, "chunk_count": 50},
                {"collection": "research", "document_count": 1, "chunk_count": 10}
            ]
        }
        """
        let decoded = try JSONDecoder().decode(
            CollectionsResponse.self,
            from: XCTUnwrap(json.data(using: .utf8))
        )
        XCTAssertEqual(decoded.totalCollections, 2)
        XCTAssertEqual(decoded.collections[0].collection, "default")
        XCTAssertEqual(decoded.collections[1].documentCount, 1)
    }

    func testStatusResponseDecoding() throws {
        let json = """
        {
            "document_count": 5,
            "collection_count": 2,
            "chunk_count": 100,
            "registered_directories": 2,
            "database_path": "/home/user/.punt-labs/quarry/data/default/lancedb",
            "database_size_bytes": 1048576,
            "embedding_model": "Snowflake/snowflake-arctic-embed-m-v1.5",
            "provider": "CPUExecutionProvider (fast)",
            "embedding_dimension": 768
        }
        """
        let decoded = try JSONDecoder().decode(
            StatusResponse.self,
            from: XCTUnwrap(json.data(using: .utf8))
        )
        XCTAssertEqual(decoded.documentCount, 5)
        XCTAssertEqual(decoded.registeredDirectories, 2)
        XCTAssertEqual(decoded.databaseSizeBytes, 1_048_576)
        XCTAssertEqual(decoded.provider, "CPUExecutionProvider (fast)")
        XCTAssertEqual(decoded.embeddingDimension, 768)
    }

    func testDatabasesResponseDecoding() throws {
        let json = """
        {
            "total_databases": 1,
            "databases": [{
                "name": "default",
                "document_count": 3,
                "size_bytes": 2048,
                "size_description": "2.0 KB"
            }]
        }
        """
        let decoded = try JSONDecoder().decode(
            DatabasesResponse.self,
            from: XCTUnwrap(json.data(using: .utf8))
        )
        XCTAssertEqual(decoded.totalDatabases, 1)
        XCTAssertEqual(decoded.databases, [
            DatabaseSummary(
                name: "default",
                documentCount: 3,
                sizeBytes: 2048,
                sizeDescription: "2.0 KB"
            )
        ])
    }

    func testShowPageResponseDecoding() throws {
        let json = """
        {
            "document_name": "report.pdf",
            "page_number": 3,
            "text": "Page text"
        }
        """
        let decoded = try JSONDecoder().decode(
            ShowPageResponse.self,
            from: XCTUnwrap(json.data(using: .utf8))
        )
        XCTAssertEqual(decoded.documentName, "report.pdf")
        XCTAssertEqual(decoded.pageNumber, 3)
        XCTAssertEqual(decoded.text, "Page text")
    }

    func testSearchResultIdentifiable() throws {
        let json = """
        {
            "document_name": "test.pdf",
            "collection": "default",
            "page_number": 1,
            "chunk_index": 2,
            "text": "sample",
            "page_type": "text",
            "source_format": ".pdf",
            "similarity": 0.8
        }
        """
        let result = try JSONDecoder().decode(
            SearchResult.self,
            from: XCTUnwrap(json.data(using: .utf8))
        )
        XCTAssertEqual(result.id, "test.pdf-1-2")
    }
}

// MARK: - QuarryClientNetworkTests

final class QuarryClientNetworkTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testHTTPErrorParsesMessage() async throws {
        let client = try mockClient()

        MockURLProtocol.requestHandler = { _ in
            jsonResponse(
                #"{"error": "Missing required parameter: q"}"#,
                statusCode: 400
            )
        }

        do {
            _ = try await client.search(query: "")
            XCTFail("Expected httpError")
        } catch let error as QuarryClientError {
            if case let .httpError(code, message) = error {
                XCTAssertEqual(code, 400)
                XCTAssertEqual(message, "Missing required parameter: q")
            } else {
                XCTFail("Expected httpError, got: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testSearchRequestIncludesQueryParams() async throws {
        let baseURL = try XCTUnwrap(URL(string: "http://127.0.0.1:8420"))
        let client = try mockClient(profile: testProfile(baseURL: baseURL))

        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            return jsonResponse(
                #"{"query":"hello","total_results":0,"results":[]}"#,
                url: request.url ?? baseURL
            )
        }

        _ = try await client.search(query: "hello", limit: 5, collection: "research")

        let components = try XCTUnwrap(try URLComponents(url: XCTUnwrap(capturedURL), resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []
        let queryDict = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value) })

        XCTAssertEqual(queryDict["q"], "hello")
        XCTAssertEqual(queryDict["limit"], "5")
        XCTAssertEqual(queryDict["collection"], "research")
    }

    func testSearchRequestIncludesAuthorizationHeader() async throws {
        let baseURL = try XCTUnwrap(URL(string: "https://okinos.user.home.lab:8420"))
        let client = try mockClient(
            profile: testProfile(
                baseURL: baseURL,
                mode: .remote,
                origin: .proxyConfig,
                authToken: "secret-token",
                hostDisplayName: "okinos.user.home.lab"
            )
        )

        var capturedAuthorization: String?
        MockURLProtocol.requestHandler = { request in
            capturedAuthorization = request.value(forHTTPHeaderField: "Authorization")
            return jsonResponse(
                #"{"query":"hello","total_results":0,"results":[]}"#,
                url: request.url ?? baseURL
            )
        }

        _ = try await client.search(query: "hello")

        XCTAssertEqual(capturedAuthorization, "Bearer secret-token")
    }

    func testUnauthorizedMapsToUnauthorizedError() async throws {
        let client = try mockClient()
        MockURLProtocol.requestHandler = { request in
            let requestURL = try XCTUnwrap(request.url)
            return jsonResponse(#"{"error":"Unauthorized"}"#, statusCode: 401, url: requestURL)
        }

        do {
            _ = try await client.collections()
            XCTFail("Expected unauthorized error")
        } catch let error as QuarryClientError {
            guard case .unauthorized = error else {
                XCTFail("Expected unauthorized, got \(error)")
                return
            }
        }
    }

    func testNetworkURLErrorMapsToUnreachable() async throws {
        let client = try mockClient()
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.cannotConnectToHost)
        }

        do {
            _ = try await client.health()
            XCTFail("Expected unreachable error")
        } catch let error as QuarryClientError {
            guard case .unreachable = error else {
                XCTFail("Expected unreachable, got \(error)")
                return
            }
        }
    }

    func testSecureProfileWithoutCACertificateThrows() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://okinos.user.home.lab:8420"))
        let profile = testProfile(
            baseURL: baseURL,
            mode: .remote,
            origin: .proxyConfig,
            caCertificateURL: URL(fileURLWithPath: "/tmp/missing-ca.crt"),
            hostDisplayName: "okinos.user.home.lab"
        )

        XCTAssertThrowsError(try QuarryClient(profile: profile)) { error in
            guard case let QuarryClientError.missingCACertificate(path) = error else {
                XCTFail("Expected missingCACertificate, got \(error)")
                return
            }
            XCTAssertTrue(path.contains("missing-ca.crt"))
        }
    }

}
