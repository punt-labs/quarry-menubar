@testable import QuarryMenuBar
import XCTest

@MainActor
final class SearchViewModelTests: XCTestCase {

    // MARK: Internal

    func testInitialStateIsIdle() {
        let viewModel = SearchViewModel()
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertEqual(viewModel.query, "")
    }

    func testSearchWithEmptyQueryStaysIdle() {
        let viewModel = SearchViewModel()
        viewModel.search()
        XCTAssertEqual(viewModel.state, .idle)
    }

    func testClearResetsState() {
        let viewModel = SearchViewModel()
        viewModel.query = "test"
        viewModel.clear()
        XCTAssertEqual(viewModel.query, "")
        XCTAssertEqual(viewModel.state, .idle)
    }

    func testSearchWithWhitespaceOnlyStaysIdle() {
        let viewModel = SearchViewModel()
        viewModel.query = "   "
        viewModel.search()
        XCTAssertEqual(viewModel.state, .idle)
    }

    func testSearchStateEquatable() {
        XCTAssertEqual(SearchState.idle, SearchState.idle)
        XCTAssertEqual(SearchState.loading, SearchState.loading)
        XCTAssertEqual(SearchState.empty("test"), SearchState.empty("test"))
        XCTAssertNotEqual(SearchState.empty("a"), SearchState.empty("b"))
        XCTAssertEqual(SearchState.error("fail"), SearchState.error("fail"))
        XCTAssertNotEqual(SearchState.idle, SearchState.loading)
    }

    // MARK: - Collection Filtering

    func testInitialCollectionStateIsEmpty() {
        let viewModel = SearchViewModel()
        XCTAssertTrue(viewModel.availableCollections.isEmpty)
        XCTAssertNil(viewModel.selectedCollection)
    }

    func testSelectedCollectionDoesNotSearchWithEmptyQuery() {
        let viewModel = SearchViewModel()
        viewModel.selectedCollection = "research"
        // Empty query → search() exits early → stays idle
        XCTAssertEqual(viewModel.state, .idle)
    }

    func testLoadCollectionsPopulatesAndSortsList() async throws {
        let (client, _) = try mockClient()

        MockURLProtocol.requestHandler = { _ in
            jsonResponse("""
            {
                "total_collections": 3,
                "collections": [
                    {"collection": "zebra", "document_count": 1, "chunk_count": 5},
                    {"collection": "alpha", "document_count": 2, "chunk_count": 10},
                    {"collection": "middle", "document_count": 3, "chunk_count": 15}
                ]
            }
            """)
        }

        let viewModel = SearchViewModel(client: client)
        await viewModel.loadCollections()
        XCTAssertEqual(viewModel.availableCollections, ["alpha", "middle", "zebra"])
    }

    func testLoadCollectionsHandlesError() async throws {
        let (client, _) = try mockClient()

        MockURLProtocol.requestHandler = { _ in
            jsonResponse(#"{"error": "server error"}"#, statusCode: 500)
        }

        let viewModel = SearchViewModel(client: client)
        await viewModel.loadCollections()
        XCTAssertTrue(viewModel.availableCollections.isEmpty)
    }

    func testSearchPassesCollectionParameter() async throws {
        let (client, _) = try mockClient()

        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            return jsonResponse(#"{"query":"test","total_results":0,"results":[]}"#)
        }

        let viewModel = SearchViewModel(client: client)
        viewModel.selectedCollection = "research"
        viewModel.query = "test"
        viewModel.search()

        // Wait for the async search task to complete
        try await Task.sleep(for: .milliseconds(100))

        let url = try XCTUnwrap(capturedURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []
        let queryDict = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value) })
        XCTAssertEqual(queryDict["collection"], "research")
    }

    // MARK: Private

    // MARK: - Helpers

    /// Creates a QuarryClient with a mock session and a temporary port file.
    /// Returns the client and the temp directory (caller should clean up).
    private func mockClient() throws -> (QuarryClient, URL) {
        let quarryDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".quarry")
            .appendingPathComponent("data")
            .appendingPathComponent("vm-test-\(UUID())")
        try FileManager.default.createDirectory(
            at: quarryDir,
            withIntermediateDirectories: true
        )
        let portFile = quarryDir.appendingPathComponent("serve.port")
        try "9999".write(to: portFile, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: quarryDir) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let client = QuarryClient(
            databaseName: quarryDir.lastPathComponent,
            session: session
        )
        return (client, quarryDir)
    }
}
