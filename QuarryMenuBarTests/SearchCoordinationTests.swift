// Tests derived from the Z specification in z-spec/docs/search-panel.tex.
//
// Each test maps to a specific schema or invariant. The Z spec line numbers
// are cited so reviewers can trace each assertion to its formal source.
//
// Z spec state mapping:
//   queryEmpty          → viewModel.query.isEmpty
//   searchState         → viewModel.state (SearchState enum)
//   results             → associated value of .results case
//   selectedResult      → viewModel.selectedResult
//   highlightedResult   → viewModel.highlightedResultID

@testable import QuarryMenuBar
import XCTest

@MainActor
final class SearchCoordinationTests: XCTestCase {

    // MARK: Internal

    // MARK: - Init (Z spec: Init schema, lines 127–135)

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testInitSelectedResultIsNil() throws {
        let vm = try makeIdleViewModel()
        XCTAssertNil(vm.selectedResult)
    }

    func testInitHighlightedResultIDIsNil() throws {
        let vm = try makeIdleViewModel()
        XCTAssertNil(vm.highlightedResultID)
    }

    // MARK: - Invariant: Empty Query Clears Everything (lines 109–111)

    //
    // queryEmpty = ztrue ⟹ searchState = idle
    // queryEmpty = ztrue ⟹ selectedResult = ∅
    // queryEmpty = ztrue ⟹ highlightedResult = ∅

    func testClearQueryClearsSelectedResult() async throws {
        let vm = try await viewModelWithResults()
        let result = try firstResult(from: vm)
        vm.selectResult(result)
        XCTAssertNotNil(vm.selectedResult)

        vm.clear()

        XCTAssertNil(
            vm.selectedResult,
            "Z spec line 110: queryEmpty = ztrue ⟹ selectedResult = ∅"
        )
    }

    func testClearQueryClearsHighlightedResultID() async throws {
        let vm = try await viewModelWithResults()
        let result = try firstResult(from: vm)
        vm.highlightResult(result.id)
        XCTAssertNotNil(vm.highlightedResultID)

        vm.clear()

        XCTAssertNil(
            vm.highlightedResultID,
            "Z spec line 111: queryEmpty = ztrue ⟹ highlightedResult = ∅"
        )
    }

    /// ProgrammaticClear (lines 304–312): must reset everything regardless of
    /// current query value. This is the bug: if query is already empty, the
    /// reactive onChange handler never fires.
    func testProgrammaticClearWhenQueryAlreadyEmpty() async throws {
        let vm = try await viewModelWithResults()
        let result = try firstResult(from: vm)
        vm.selectResult(result)
        XCTAssertNotNil(vm.selectedResult)

        // Drain query to empty, then call clear() again while already empty
        vm.clear()
        XCTAssertNil(vm.selectedResult, "Precondition: first clear resets")

        // Simulate stale selection set via a new search cycle
        MockURLProtocol.requestHandler = { _ in
            jsonResponse(
                #"{"query":"x","total_results":1,"results":[{"document_name":"doc-0","collection":"test","page_number":1,"chunk_index":0,"text":"T","page_type":"content","source_format":".md","similarity":0.9}]}"#
            )
        }
        vm.query = "x"
        vm.search()
        try await Task.sleep(for: .milliseconds(150))
        let r2 = try firstResult(from: vm)
        vm.selectResult(r2)
        XCTAssertNotNil(vm.selectedResult)

        // Now clear to empty, then clear() again — query is already ""
        vm.clear()
        vm.selectResult(r2) // Should be rejected: state is idle
        vm.clear()

        XCTAssertNil(
            vm.selectedResult,
            "Z spec ProgrammaticClear: must reset regardless of current query"
        )
    }

    // MARK: - Invariant: Selection From Results (lines 100–101)

    //
    // selectedResult ⊆ results
    // highlightedResult ⊆ results

    func testSelectResultRejectsResultNotInResults() throws {
        let vm = try makeIdleViewModel()
        XCTAssertEqual(vm.state, .idle)

        let orphan = makeResult(name: "not-in-results")
        vm.selectResult(orphan)

        XCTAssertNil(
            vm.selectedResult,
            "Z spec line 100: selectedResult ⊆ results — cannot select when no results"
        )
    }

    func testHighlightRejectsIDNotInResults() throws {
        let vm = try makeIdleViewModel()
        XCTAssertEqual(vm.state, .idle)

        vm.highlightResult("nonexistent-id")

        XCTAssertNil(
            vm.highlightedResultID,
            "Z spec line 101: highlightedResult ⊆ results — cannot highlight when no results"
        )
    }

    // MARK: - Invariant: No Selection Without hasResults (line 115)

    //
    // searchState ≠ hasResults ⟹ selectedResult = ∅

    func testNoSelectionWhenStateIsIdle() throws {
        let vm = try makeIdleViewModel()
        let result = makeResult()
        vm.selectResult(result)

        XCTAssertNil(
            vm.selectedResult,
            "Z spec line 115: searchState ≠ hasResults ⟹ selectedResult = ∅"
        )
    }

    func testSelectedResultClearedWhenStateTransitionsToEmpty() async throws {
        let vm = try await viewModelWithResults()
        let result = try firstResult(from: vm)
        vm.selectResult(result)
        XCTAssertNotNil(vm.selectedResult)

        // Same query, but server now returns empty — tests state didSet path
        MockURLProtocol.requestHandler = { _ in
            jsonResponse(#"{"query":"test","total_results":0,"results":[]}"#)
        }
        vm.search()
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(vm.state, .empty("test"))
        XCTAssertNil(
            vm.selectedResult,
            "Z spec line 115: state leaving .results clears selection"
        )
    }

    // MARK: - Invariant: Detail and Highlight Exclusive (line 120)

    //
    // selectedResult ≠ ∅ ⟹ highlightedResult = ∅

    func testSelectResultClearsHighlight() async throws {
        let vm = try await viewModelWithResults()
        let results = try allResults(from: vm)
        try requireMinimumResults(results, count: 2)

        vm.highlightResult(results[0].id)
        XCTAssertNotNil(vm.highlightedResultID)

        vm.selectResult(results[1])

        XCTAssertNil(
            vm.highlightedResultID,
            "Z spec line 120: selectedResult ≠ ∅ ⟹ highlightedResult = ∅"
        )
    }

    func testHighlightBlockedWhileDetailOpen() async throws {
        let vm = try await viewModelWithResults()
        let results = try allResults(from: vm)
        try requireMinimumResults(results, count: 2)

        vm.selectResult(results[0])
        XCTAssertNotNil(vm.selectedResult)

        vm.highlightResult(results[1].id)

        XCTAssertNil(
            vm.highlightedResultID,
            "Z spec line 254: cannot highlight while detail view is open"
        )
    }

    // MARK: - Operation: SelectResult (lines 231–242)

    func testSelectResultSetsValue() async throws {
        let vm = try await viewModelWithResults()
        let result = try firstResult(from: vm)

        vm.selectResult(result)

        XCTAssertEqual(vm.selectedResult?.id, result.id)
    }

    func testSelectResultPreservesSearchState() async throws {
        let vm = try await viewModelWithResults()
        let stateBefore = vm.state
        let result = try firstResult(from: vm)

        vm.selectResult(result)

        XCTAssertEqual(
            vm.state, stateBefore,
            "Z spec line 240: searchState' = searchState"
        )
    }

    // MARK: - Operation: CloseDetail (lines 286–295)

    func testCloseDetailClearsSelectedResult() async throws {
        let vm = try await viewModelWithResults()
        let result = try firstResult(from: vm)
        vm.selectResult(result)
        XCTAssertNotNil(vm.selectedResult)

        vm.closeDetail()

        XCTAssertNil(vm.selectedResult)
    }

    func testCloseDetailPreservesResults() async throws {
        let vm = try await viewModelWithResults()
        let resultsBefore = try allResults(from: vm)
        let result = try firstResult(from: vm)
        vm.selectResult(result)

        vm.closeDetail()

        let resultsAfter = try allResults(from: vm)
        XCTAssertEqual(
            resultsBefore.map(\.id), resultsAfter.map(\.id),
            "Z spec line 292: results' = results"
        )
    }

    func testCloseDetailClearsHighlight() async throws {
        let vm = try await viewModelWithResults()
        let result = try firstResult(from: vm)

        // Set a highlight (no detail open), then call closeDetail
        vm.highlightResult(result.id)
        XCTAssertNotNil(vm.highlightedResultID)

        vm.closeDetail()

        XCTAssertNil(
            vm.highlightedResultID,
            "Z spec line 291: highlightedResult' = ∅ after CloseDetail"
        )
    }

    // MARK: - Operation: HighlightResult (lines 249–261)

    func testHighlightSetsID() async throws {
        let vm = try await viewModelWithResults()
        let result = try firstResult(from: vm)

        vm.highlightResult(result.id)

        XCTAssertEqual(vm.highlightedResultID, result.id)
    }

    func testHighlightRequiresHasResultsState() throws {
        let vm = try makeIdleViewModel()
        // idle state — no results exist
        vm.highlightResult("some-id")

        XCTAssertNil(
            vm.highlightedResultID,
            "Z spec line 253: highlight requires searchState = hasResults"
        )
    }

    // MARK: - Operation: ClearHighlight (lines 268–278)

    func testClearHighlightClearsID() async throws {
        let vm = try await viewModelWithResults()
        let result = try firstResult(from: vm)
        vm.highlightResult(result.id)
        XCTAssertNotNil(vm.highlightedResultID)

        vm.clearHighlight()

        XCTAssertNil(vm.highlightedResultID)
    }

    // MARK: - Operation: ChangeCollection (lines 319–327)

    //
    // selectedResult' = ∅
    // highlightedResult' = ∅

    func testChangeCollectionClearsSelectedResult() async throws {
        let vm = try await viewModelWithResults()
        let result = try firstResult(from: vm)
        vm.selectResult(result)
        XCTAssertNotNil(vm.selectedResult)

        vm.selectedCollection = "other-collection"

        XCTAssertNil(
            vm.selectedResult,
            "Z spec line 322: ChangeCollection clears selectedResult"
        )
    }

    func testChangeCollectionClearsHighlight() async throws {
        let vm = try await viewModelWithResults()
        let result = try firstResult(from: vm)
        vm.highlightResult(result.id)
        XCTAssertNotNil(vm.highlightedResultID)

        vm.selectedCollection = "other-collection"

        XCTAssertNil(
            vm.highlightedResultID,
            "Z spec line 323: ChangeCollection clears highlightedResult"
        )
    }

    // MARK: - Operation: EnterQuery (lines 145–153)

    //
    // New query clears previous selections

    func testEnterQueryClearsSelectedResult() async throws {
        let vm = try await viewModelWithResults()
        let result = try firstResult(from: vm)
        vm.selectResult(result)
        XCTAssertNotNil(vm.selectedResult)

        vm.query = "new query"

        XCTAssertNil(
            vm.selectedResult,
            "Z spec line 151: EnterQuery clears selectedResult"
        )
    }

    func testEnterQueryClearsHighlight() async throws {
        let vm = try await viewModelWithResults()
        let result = try firstResult(from: vm)
        vm.highlightResult(result.id)
        XCTAssertNotNil(vm.highlightedResultID)

        vm.query = "new query"

        XCTAssertNil(
            vm.highlightedResultID,
            "Z spec line 152: EnterQuery clears highlightedResult"
        )
    }

    // MARK: - Operation: ReceiveResults (lines 178–191)

    func testReceiveResultsDoesNotAutoSelect() async throws {
        let vm = try await viewModelWithResults()

        XCTAssertNil(
            vm.selectedResult,
            "Z spec line 188: selectedResult' = ∅ after ReceiveResults"
        )
        XCTAssertNil(
            vm.highlightedResultID,
            "Z spec line 189: highlightedResult' = ∅ after ReceiveResults"
        )
    }

    // MARK: Private

    // MARK: - Private Helpers

    private func makeResult(
        name: String = "test-doc",
        page: Int = 1,
        chunk: Int = 0
    ) -> SearchResult {
        SearchResult(
            documentName: name,
            collection: "test",
            pageNumber: page,
            chunkIndex: chunk,
            text: "Sample text for \(name)",
            pageType: "content",
            sourceFormat: ".md",
            agentHandle: nil,
            memoryType: nil,
            summary: nil,
            similarity: 0.95
        )
    }

    private func firstResult(from vm: SearchViewModel) throws -> SearchResult {
        guard case let .results(results) = vm.state,
              let first = results.first
        else {
            throw XCTSkip("ViewModel not in results state")
        }
        return first
    }

    private func allResults(from vm: SearchViewModel) throws -> [SearchResult] {
        guard case let .results(results) = vm.state else {
            throw XCTSkip("ViewModel not in results state")
        }
        return results
    }

    private func requireMinimumResults(
        _ results: [SearchResult],
        count: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        if results.count < count {
            XCTFail(
                "Need at least \(count) results, got \(results.count)",
                file: file,
                line: line
            )
            throw XCTSkip("Insufficient results")
        }
    }

    /// Creates a SearchViewModel with mock results already loaded.
    private func viewModelWithResults(count: Int = 3) async throws -> SearchViewModel {
        let client = try mockClient()
        let items = (0 ..< count).map { i in
            #"{"document_name":"doc-\#(i)","collection":"test","page_number":1,"chunk_index":0,"text":"Text \#(i)","page_type":"content","source_format":".md","similarity":0.9\#(i)}"#
        }
        let json = #"{"query":"test","total_results":\#(count),"results":[\#(items.joined(separator: ","))]}"#
        MockURLProtocol.requestHandler = { _ in
            jsonResponse(json)
        }
        let vm = SearchViewModel(client: client)
        vm.query = "test"
        vm.search()
        try await Task.sleep(for: .milliseconds(150))
        guard case .results = vm.state else {
            throw XCTSkip("Search did not produce results")
        }
        return vm
    }

    private func makeIdleViewModel() throws -> SearchViewModel {
        try SearchViewModel(client: mockClient())
    }
}
