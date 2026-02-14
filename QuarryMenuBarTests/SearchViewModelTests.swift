@testable import QuarryMenuBar
import XCTest

@MainActor
final class SearchViewModelTests: XCTestCase {
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
}
