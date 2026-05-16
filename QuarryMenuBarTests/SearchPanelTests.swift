@testable import QuarryMenuBar
import XCTest

final class SearchPanelTests: XCTestCase {
    func testDetailTextToCopyUsesResolvedDetailTextWhenAvailable() {
        XCTAssertEqual(
            SearchPanel.detailTextToCopy(
                resolvedDetailText: "Full page content",
                fallbackText: "Search snippet"
            ),
            "Full page content"
        )
    }

    func testDetailTextToCopyFallsBackToSearchSnippetUntilDetailLoads() {
        XCTAssertEqual(
            SearchPanel.detailTextToCopy(
                resolvedDetailText: nil,
                fallbackText: "Search snippet"
            ),
            "Search snippet"
        )
    }
}
