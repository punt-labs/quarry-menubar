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

    func testDetailSelectionKeyIncludesCollection() {
        let result = SearchResult(
            documentName: "README.md",
            collection: "archive",
            pageNumber: 3,
            chunkIndex: 0,
            text: "Search snippet",
            pageType: "text",
            sourceFormat: ".md",
            agentHandle: nil,
            memoryType: nil,
            summary: nil,
            similarity: 0.9
        )

        XCTAssertEqual(
            SearchPanel.detailSelectionKey(for: result),
            "archive/README.md-3-0"
        )
    }

    func testDetailSelectionKeyChangesAcrossCollectionsForSameDocumentChunk() {
        let first = SearchResult(
            documentName: "README.md",
            collection: "archive",
            pageNumber: 3,
            chunkIndex: 0,
            text: "First",
            pageType: "text",
            sourceFormat: ".md",
            agentHandle: nil,
            memoryType: nil,
            summary: nil,
            similarity: 0.9
        )
        let second = SearchResult(
            documentName: "README.md",
            collection: "notes",
            pageNumber: 3,
            chunkIndex: 0,
            text: "Second",
            pageType: "text",
            sourceFormat: ".md",
            agentHandle: nil,
            memoryType: nil,
            summary: nil,
            similarity: 0.9
        )

        XCTAssertNotEqual(
            SearchPanel.detailSelectionKey(for: first),
            SearchPanel.detailSelectionKey(for: second)
        )
    }
}
