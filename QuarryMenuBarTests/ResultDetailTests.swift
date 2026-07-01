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

    func testLoadContentReflowsWrappedPDFPageText() async throws {
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
                        "text": "Chapter 3 / An Introduction to Relational Databases\\n75\\ncould be relational, while a given user could have an external view that was\\nhierarchic. In\\npractice, however, most systems use the same type of structure as the basis for\\nboth levels,\\nand relational products are no exception to this general rule---views are still\\nrelvars, just\\nlike the base relvars are. And since the same type of object is supported at both\\nlevels, the"
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

        XCTAssertEqual(
            content.text,
            """
            Chapter 3 / An Introduction to Relational Databases
            could be relational, while a given user could have an external view that was hierarchic. In practice, however, most systems use the same type of structure as the basis for both levels, and relational products are no exception to this general rule---views are still relvars, just like the base relvars are. And since the same type of object is supported at both levels, the
            """
        )
        XCTAssertNil(content.warningMessage)
    }

    func testLoadContentPreservesPDFBulletLines() async throws {
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
                        "text": "Why It Matters\\n■ Base relvars\\n\\\"really exist\\\" in the sense that they represent data physically stored.\\n■ Views\\nprovide different ways of looking at the real data."
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

        XCTAssertEqual(
            content.text,
            """
            Why It Matters

            ■ Base relvars
            "really exist" in the sense that they represent data physically stored.

            ■ Views
            provide different ways of looking at the real data.
            """
        )
    }

    func testLoadContentRestoresLikelyPDFParagraphBreaks() async throws {
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
                        "text": "This is the first long extracted line that wraps in the source PDF but belongs to a single paragraph for the reader.\\nThis is the second long extracted line that should still be joined into that same paragraph for readability.\\nThis is the third long extracted line that keeps the page's typical line length high for the heuristic.\\nShort ending line only.\\nThere is one final point that should begin a new paragraph because the prior extracted line was unusually short."
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

        XCTAssertEqual(
            content.text,
            """
            This is the first long extracted line that wraps in the source PDF but belongs to a single paragraph for the reader. This is the second long extracted line that should still be joined into that same paragraph for readability. This is the third long extracted line that keeps the page's typical line length high for the heuristic. Short ending line only.

            There is one final point that should begin a new paragraph because the prior extracted line was unusually short.
            """
        )
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

    func testFormatDetailTextLeavesNonPDFTextUnchanged() {
        let text = """
        Heading
        wrapped prose
        stays as-authored
        """

        XCTAssertEqual(
            ExtractedTextFormatter.formatDetailText(
                text,
                sourceFormat: ".md",
                pageType: "text"
            ),
            text
        )
    }

    func testShouldReflowDetailTextMatchesQuarryRepresentationPolicy() {
        XCTAssertTrue(
            ExtractedTextFormatter.shouldReflowDetailText(
                sourceFormat: ".pdf",
                pageType: "text"
            )
        )
        XCTAssertFalse(
            ExtractedTextFormatter.shouldReflowDetailText(
                sourceFormat: ".py",
                pageType: "code"
            )
        )
        XCTAssertFalse(
            ExtractedTextFormatter.shouldReflowDetailText(
                sourceFormat: ".md",
                pageType: "text"
            )
        )
        XCTAssertFalse(
            ExtractedTextFormatter.shouldReflowDetailText(
                sourceFormat: ".csv",
                pageType: "spreadsheet"
            )
        )
        XCTAssertFalse(
            ExtractedTextFormatter.shouldReflowDetailText(
                sourceFormat: ".pptx",
                pageType: "presentation"
            )
        )
    }

    func testFormatDetailTextLeavesQuarryCodePagesUnchanged() {
        let text = """
        def example():
            return "still wrapped
        exactly as-authored"
        """

        XCTAssertEqual(
            ExtractedTextFormatter.formatDetailText(
                text,
                sourceFormat: ".py",
                pageType: "code"
            ),
            text
        )
    }

    func testFormatDetailTextUnhyphenatesSoftWrappedPDFWords() {
        // Realistic hard-wrapped prose: long lines so the page is treated as prose and the
        // soft-wrap de-hyphenation runs. "inas" is a clear fragment, so the hyphen is dropped.
        let text = """
        The archaic construction becomes far more legible inas-
        much as the paragraph is reflowed into continuous readable prose.
        """

        XCTAssertEqual(
            ExtractedTextFormatter.formatDetailText(
                text,
                sourceFormat: ".pdf",
                pageType: "text"
            ),
            "The archaic construction becomes far more legible inasmuch "
                + "as the paragraph is reflowed into continuous readable prose."
        )
    }

    func testFormatDetailTextPreservesHardCompoundHyphen() {
        // "well" is a hard-compound prefix, so the wrap hyphen is kept: `well-known`, never
        // the fake word `wellknown`. When uncertain we bias toward preserving the hyphen.
        let text = """
        This particular approach is a remarkably well-
        known technique among database practitioners working today.
        """

        XCTAssertEqual(
            ExtractedTextFormatter.formatDetailText(
                text,
                sourceFormat: ".pdf",
                pageType: "text"
            ),
            "This particular approach is a remarkably well-known "
                + "technique among database practitioners working today."
        )
    }

    func testFormatDetailTextPreservesYearFollowingHeading() {
        // A four-digit year is real content, not a running-header page number, so it must
        // never be stripped even when it follows a heading.
        let text = """
        Annual Report
        2024
        Revenue increased twelve percent over the prior fiscal year on continued strong demand.
        """

        XCTAssertEqual(
            ExtractedTextFormatter.formatDetailText(
                text,
                sourceFormat: ".pdf",
                pageType: "text"
            ),
            """
            Annual Report
            2024 Revenue increased twelve percent over the prior fiscal year on continued strong demand.
            """
        )
    }

    func testFormatDetailTextStripsFourDigitNonYearPageNumber() {
        // Documents the residual call: a four-digit value outside the plausible year range
        // is treated as a large page number and stripped when it follows a heading.
        let text = """
        Report Title
        4021
        This is body prose long enough to be treated as hard-wrapped prose content for the reader.
        """

        XCTAssertEqual(
            ExtractedTextFormatter.formatDetailText(
                text,
                sourceFormat: ".pdf",
                pageType: "text"
            ),
            """
            Report Title
            This is body prose long enough to be treated as hard-wrapped prose content for the reader.
            """
        )
    }

    func testFormatDetailTextPreservesShortLineVerse() {
        // Predominantly short lines (verse) are intentional structure — pass through unchanged.
        let text = """
        Roses are red,
        Violets are blue,
        Sugar is sweet,
        And so are you.
        """

        XCTAssertEqual(
            ExtractedTextFormatter.formatDetailText(
                text,
                sourceFormat: ".pdf",
                pageType: "text"
            ),
            text
        )
    }

    func testFormatDetailTextPreservesShortLineAddress() {
        let text = """
        Jane Doe
        128 Example Avenue
        Springfield, IL 62704
        """

        XCTAssertEqual(
            ExtractedTextFormatter.formatDetailText(
                text,
                sourceFormat: ".pdf",
                pageType: "text"
            ),
            text
        )
    }

    func testFormatDetailTextDoesNotSplitTitleCaseWrappedSentence() {
        // A title-case-heavy wrapped prose line must not be torn out as a spurious heading.
        let text = """
        The United States Federal Reserve Board announced
        that interest rates would remain unchanged through
        the remainder of the current fiscal year.
        """

        XCTAssertEqual(
            ExtractedTextFormatter.formatDetailText(
                text,
                sourceFormat: ".pdf",
                pageType: "text"
            ),
            "The United States Federal Reserve Board announced that interest rates "
                + "would remain unchanged through the remainder of the current fiscal year."
        )
    }

    func testFormatDetailTextReturnsEmptyStringUnchanged() {
        XCTAssertEqual(
            ExtractedTextFormatter.formatDetailText("", sourceFormat: ".pdf", pageType: "text"),
            ""
        )
    }

    func testFormatDetailTextReturnsWhitespaceOnlyInputUnchanged() {
        let text = "   \n  \t "
        XCTAssertEqual(
            ExtractedTextFormatter.formatDetailText(text, sourceFormat: ".pdf", pageType: "text"),
            text
        )
    }

    func testFormatDetailTextReturnsSingleLineUnchanged() {
        let text = "This is one already-clean line of prose that needs no reflow at all today."
        XCTAssertEqual(
            ExtractedTextFormatter.formatDetailText(text, sourceFormat: ".pdf", pageType: "text"),
            text
        )
    }

    func testFormatDetailTextIsIdempotentOnCleanProse() {
        let text = "This is one already-clean line of prose that needs no reflow at all today."
        let once = ExtractedTextFormatter.formatDetailText(text, sourceFormat: ".pdf", pageType: "text")
        let twice = ExtractedTextFormatter.formatDetailText(once, sourceFormat: ".pdf", pageType: "text")
        XCTAssertEqual(once, text)
        XCTAssertEqual(twice, once)
    }

    func testFormatDetailTextPreservesExistingBlankLineParagraphBreaks() {
        // A single blank-line paragraph break is preserved — neither collapsed nor doubled.
        let text = """
        This first paragraph is long enough to read as hard-wrapped prose content here.

        This second paragraph is also long enough to read as hard-wrapped prose here.
        """

        XCTAssertEqual(
            ExtractedTextFormatter.formatDetailText(
                text,
                sourceFormat: ".pdf",
                pageType: "text"
            ),
            text
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
