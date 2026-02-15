import HighlightSwift
@testable import QuarryMenuBar
import XCTest

final class SyntaxHighlighterTests: XCTestCase {

    // MARK: - isCodeFormat

    func testIsCodeFormatRecognizesAllMappedExtensions() {
        let codeExtensions: [String] = [
            ".py", ".js", ".ts", ".swift", ".rs", ".go", ".java",
            ".c", ".cpp", ".h", ".rb", ".sh", ".toml", ".yaml", ".yml", ".json"
        ]
        for ext in codeExtensions {
            XCTAssertTrue(
                SyntaxHighlighter.isCodeFormat(ext),
                "\(ext) should be recognized as code"
            )
        }
    }

    func testIsCodeFormatRejectsNonCodeFormats() {
        let nonCode: [String] = [".pdf", ".txt", ".tex", ".docx", ".md", ".png", ""]
        for ext in nonCode {
            XCTAssertFalse(
                SyntaxHighlighter.isCodeFormat(ext),
                "\(ext) should NOT be recognized as code"
            )
        }
    }

    // MARK: - Language Mapping

    func testLanguageMappingReturnsCorrectLanguages() {
        XCTAssertEqual(SyntaxHighlighter.language(for: ".py"), .python)
        XCTAssertEqual(SyntaxHighlighter.language(for: ".swift"), .swift)
        XCTAssertEqual(SyntaxHighlighter.language(for: ".js"), .javaScript)
        XCTAssertEqual(SyntaxHighlighter.language(for: ".ts"), .typeScript)
        XCTAssertEqual(SyntaxHighlighter.language(for: ".rs"), .rust)
        XCTAssertEqual(SyntaxHighlighter.language(for: ".go"), .go)
        XCTAssertEqual(SyntaxHighlighter.language(for: ".json"), .json)
        XCTAssertEqual(SyntaxHighlighter.language(for: ".yaml"), .yaml)
        XCTAssertEqual(SyntaxHighlighter.language(for: ".yml"), .yaml)
        XCTAssertEqual(SyntaxHighlighter.language(for: ".sh"), .bash)
        XCTAssertEqual(SyntaxHighlighter.language(for: ".cpp"), .cPlusPlus)
        XCTAssertEqual(SyntaxHighlighter.language(for: ".h"), .c)
    }

    func testLanguageMappingReturnsNilForNonCode() {
        XCTAssertNil(SyntaxHighlighter.language(for: ".pdf"))
        XCTAssertNil(SyntaxHighlighter.language(for: ".txt"))
        XCTAssertNil(SyntaxHighlighter.language(for: ".md"))
        XCTAssertNil(SyntaxHighlighter.language(for: ".docx"))
    }

    // MARK: - Async Highlight (Code)

    func testHighlightPythonReturnsNonEmptyAttributedString() async {
        let code = "def hello():\n    print('world')"
        let result = await SyntaxHighlighter.highlight(code, format: ".py")
        XCTAssertFalse(String(result.characters).isEmpty)
        XCTAssertEqual(String(result.characters), code)
    }

    func testHighlightSwiftReturnsNonEmptyAttributedString() async {
        let code = "let x = 42"
        let result = await SyntaxHighlighter.highlight(code, format: ".swift")
        XCTAssertFalse(String(result.characters).isEmpty)
        XCTAssertEqual(String(result.characters), code)
    }

    func testHighlightPreservesSourceText() async {
        let code = "console.log('hello');\nconst x = { key: 'value' };"
        let result = await SyntaxHighlighter.highlight(code, format: ".js")
        XCTAssertEqual(String(result.characters), code)
    }

    // MARK: - Non-Code Formats

    func testNonCodeFormatReturnsPlainText() async {
        let text = "This is plain text content."
        let result = await SyntaxHighlighter.highlight(text, format: ".pdf")
        XCTAssertEqual(String(result.characters), text)
    }

    func testUnknownFormatReturnsPlainText() async {
        let text = "Unknown format content."
        let result = await SyntaxHighlighter.highlight(text, format: ".xyz")
        XCTAssertEqual(String(result.characters), text)
    }

    // MARK: - Markdown

    func testMarkdownStripsHeaderMarkers() async {
        let md = "### Hello World"
        let result = await SyntaxHighlighter.highlight(md, format: ".md")
        XCTAssertEqual(String(result.characters), "Hello World")
    }

    func testMarkdownStripsInlineCode() async {
        let md = "Use `foo` here"
        let result = await SyntaxHighlighter.highlight(md, format: ".md")
        XCTAssertEqual(String(result.characters), "Use foo here")
    }

    func testMarkdownStripsBold() async {
        let md = "This is **bold** text"
        let result = await SyntaxHighlighter.highlight(md, format: ".md")
        XCTAssertEqual(String(result.characters), "This is bold text")
    }

    func testMarkdownStripsLinks() async {
        let md = "Click [here](https://example.com) now"
        let result = await SyntaxHighlighter.highlight(md, format: ".md")
        XCTAssertEqual(String(result.characters), "Click here now")
    }

    func testMarkdownStripsBlockQuotes() async {
        let md = "> Quoted text"
        let result = await SyntaxHighlighter.highlight(md, format: ".md")
        XCTAssertEqual(String(result.characters), "Quoted text")
    }

    // MARK: - Theme / Color Scheme

    func testLightAndDarkModeProduceDifferentResults() async {
        let code = "let x = 42"
        let light = await SyntaxHighlighter.highlight(
            code, format: ".swift", theme: .xcode, lightMode: true
        )
        let dark = await SyntaxHighlighter.highlight(
            code, format: ".swift", theme: .xcode, lightMode: false
        )
        // Both preserve text, but attributed styling differs
        XCTAssertEqual(String(light.characters), code)
        XCTAssertEqual(String(dark.characters), code)
        XCTAssertNotEqual(light, dark)
    }

    func testDifferentThemesProduceDifferentResults() async {
        let code = "def foo(): pass"
        let xcode = await SyntaxHighlighter.highlight(
            code, format: ".py", theme: .xcode, lightMode: true
        )
        let github = await SyntaxHighlighter.highlight(
            code, format: ".py", theme: .github, lightMode: true
        )
        XCTAssertEqual(String(xcode.characters), code)
        XCTAssertEqual(String(github.characters), code)
        XCTAssertNotEqual(xcode, github)
    }
}
