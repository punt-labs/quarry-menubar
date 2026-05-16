@testable import QuarryMenuBar
import XCTest

final class ResultDetailTests: XCTestCase {

    // MARK: Internal

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testLoadContentReturnsFullPageTextWhenShowSucceeds() async throws {
        let result = makeResult()
        let client = try mockClient()

        MockURLProtocol.requestHandler = { request in
            let requestURL = try XCTUnwrap(request.url)
            switch requestURL.path {
            case "/show":
                return jsonResponse(
                    """
                    {
                        "document_name": "README.md",
                        "page_number": 3,
                        "text": "Full page content"
                    }
                    """,
                    url: requestURL
                )
            default:
                XCTFail("Unexpected request: \(requestURL.absoluteString)")
                return jsonResponse(#"{"error":"unexpected"}"#, statusCode: 500, url: requestURL)
            }
        }

        let content = await ResultDetail.loadContent(result: result, client: client)

        XCTAssertEqual(content.text, "Full page content")
        XCTAssertNil(content.warningMessage)
    }

    func testLoadContentSurfacesFallbackWarningWhenShowFails() async throws {
        let result = makeResult()
        let client = try mockClient()

        MockURLProtocol.requestHandler = { request in
            let requestURL = try XCTUnwrap(request.url)
            switch requestURL.path {
            case "/show":
                return jsonResponse(#"{"error":"detail unavailable"}"#, statusCode: 404, url: requestURL)
            default:
                XCTFail("Unexpected request: \(requestURL.absoluteString)")
                return jsonResponse(#"{"error":"unexpected"}"#, statusCode: 500, url: requestURL)
            }
        }

        let content = await ResultDetail.loadContent(result: result, client: client)

        XCTAssertEqual(content.text, result.text)
        XCTAssertEqual(
            content.warningMessage,
            "HTTP 404: detail unavailable Showing the search excerpt instead."
        )
    }

    // MARK: Private

    private func makeResult() -> SearchResult {
        SearchResult(
            documentName: "README.md",
            collection: "quarry-menubar",
            pageNumber: 3,
            chunkIndex: 0,
            text: "Search snippet",
            pageType: "text",
            sourceFormat: ".md",
            agentHandle: nil,
            memoryType: nil,
            summary: nil,
            similarity: 0.91
        )
    }
}
