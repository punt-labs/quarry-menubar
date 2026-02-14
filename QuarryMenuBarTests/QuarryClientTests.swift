@testable import QuarryMenuBar
import XCTest

// MARK: - MockURLProtocol

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            XCTFail("No request handler set")
            return
        }
        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Helpers

private func mockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

// swiftlint:disable force_unwrapping
private let stubBaseURL = URL(string: "http://127.0.0.1:9999")!
// swiftlint:enable force_unwrapping

private func jsonResponse(
    _ json: String,
    statusCode: Int = 200,
    url: URL = stubBaseURL
) -> (Data, HTTPURLResponse) {
    // swiftlint:disable force_unwrapping
    let data = json.data(using: .utf8)!
    let response = HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
    // swiftlint:enable force_unwrapping
    return (data, response)
}

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
            "database_path": "/home/user/.quarry/data/default/lancedb",
            "database_size_bytes": 1048576,
            "embedding_model": "Snowflake/snowflake-arctic-embed-m-v1.5",
            "embedding_dimension": 768
        }
        """
        let decoded = try JSONDecoder().decode(
            StatusResponse.self,
            from: XCTUnwrap(json.data(using: .utf8))
        )
        XCTAssertEqual(decoded.documentCount, 5)
        XCTAssertEqual(decoded.databaseSizeBytes, 1_048_576)
        XCTAssertEqual(decoded.embeddingDimension, 768)
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

    // MARK: Internal

    override func setUp() {
        super.setUp()
        // Create a temp directory structure mimicking ~/.quarry/data/<db>/
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        tempDir = dir
        let dbDir = dir.appendingPathComponent("test-db")
        try? FileManager.default.createDirectory(
            at: dbDir,
            withIntermediateDirectories: true
        )
        let portFile = dbDir.appendingPathComponent("serve.port")
        try? "9999".write(to: portFile, atomically: true, encoding: .utf8)
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testServerNotRunningThrows() async {
        // Point at a non-existent database so the port file won't be found
        let client = QuarryClient(databaseName: "nonexistent-\(UUID())", session: mockSession())
        do {
            _ = try await client.health()
            XCTFail("Expected serverNotRunning error")
        } catch let error as QuarryClientError {
            if case .serverNotRunning = error {
                // Expected
            } else {
                XCTFail("Expected serverNotRunning, got: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testHTTPErrorParsesMessage() async {
        // Write a port file to the real quarry path for "http-error-test"
        let quarryDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".quarry")
            .appendingPathComponent("data")
            .appendingPathComponent("http-error-test-\(UUID())")
        try? FileManager.default.createDirectory(
            at: quarryDir,
            withIntermediateDirectories: true
        )
        let portFile = quarryDir.appendingPathComponent("serve.port")
        try? "9999".write(to: portFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: quarryDir) }

        let dbName = quarryDir.lastPathComponent
        let client = QuarryClient(databaseName: dbName, session: mockSession())

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
        let quarryDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".quarry")
            .appendingPathComponent("data")
            .appendingPathComponent("params-test-\(UUID())")
        try FileManager.default.createDirectory(
            at: quarryDir,
            withIntermediateDirectories: true
        )
        let portFile = quarryDir.appendingPathComponent("serve.port")
        try "9999".write(to: portFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: quarryDir) }

        let dbName = quarryDir.lastPathComponent
        let client = QuarryClient(databaseName: dbName, session: mockSession())

        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            return jsonResponse(#"{"query":"hello","total_results":0,"results":[]}"#)
        }

        _ = try await client.search(query: "hello", limit: 5, collection: "research")

        let components = try XCTUnwrap(try URLComponents(url: XCTUnwrap(capturedURL), resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []
        let queryDict = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value) })

        XCTAssertEqual(queryDict["q"], "hello")
        XCTAssertEqual(queryDict["limit"], "5")
        XCTAssertEqual(queryDict["collection"], "research")
    }

    // MARK: Private

    private var tempDir: URL?

}
