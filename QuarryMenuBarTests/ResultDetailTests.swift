@testable import QuarryMenuBar
import XCTest

final class ResultDetailTests: XCTestCase {

    // MARK: Internal

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testLoadContentReturnsShowTextVerbatimWhenShowSucceeds() async throws {
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

    func testLoadContentRendersPDFPageTextWithoutReflowing() async throws {
        // The app no longer reconstructs paragraphs — reflow moved upstream to Quarry.
        // Wrapped PDF text must be returned exactly as /show delivers it, including the
        // embedded line breaks. This is the load-bearing assertion for qmb-v15.
        let result = makeResult(sourceFormat: ".pdf")
        let client = try mockClient()

        let showText = "Chapter 3 / An Introduction to Relational Databases\n"
            + "75\ncould be relational, while a given user could have an external view that was\n"
            + "hierarchic. In\npractice, however, most systems use the same type of structure."

        MockURLProtocol.requestHandler = { request in
            let requestURL = try XCTUnwrap(request.url)
            switch requestURL.path {
            case "/show":
                let escaped = showText.replacingOccurrences(of: "\n", with: "\\n")
                return jsonResponse(
                    """
                    {
                        "document_name": "README.md",
                        "page_number": 3,
                        "text": "\(escaped)"
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

        // Verbatim except line-ending hygiene: the input uses only LF, so it survives
        // unchanged — no reflow, no join, no paragraph reconstruction.
        XCTAssertEqual(content.text, showText)
        XCTAssertNil(content.warningMessage)
    }

    func testLoadContentNormalizesCarriageReturnsToLineFeeds() async throws {
        // Some /show docs return CRLF (or bare CR). loadContent normalizes CR/CRLF -> LF so no
        // stray carriage return leaks into the SwiftUI Text. This is hygiene, not reflow: the
        // existing LF break structure is preserved, only carriage returns are rewritten.
        let result = makeResult(sourceFormat: ".pdf")
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
                        "text": "a\\r\\nb\\rc"
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

        XCTAssertEqual(content.text, "a\nb\nc")
        XCTAssertFalse(content.text.contains("\r"))
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

    private func makeResult(sourceFormat: String = ".md") -> SearchResult {
        SearchResult(
            documentName: "README.md",
            collection: "quarry-menubar",
            pageNumber: 3,
            chunkIndex: 0,
            text: "Search snippet",
            pageType: "text",
            sourceFormat: sourceFormat,
            agentHandle: nil,
            memoryType: nil,
            summary: nil,
            similarity: 0.91
        )
    }
}
