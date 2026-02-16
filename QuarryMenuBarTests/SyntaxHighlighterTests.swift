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

    func testHighlightPythonReturnsNonEmptyWithBackground() async {
        let code = "def hello():\n    print('world')"
        let output = await SyntaxHighlighter.highlight(code, format: ".py")
        XCTAssertFalse(String(output.text.characters).isEmpty)
        XCTAssertEqual(String(output.text.characters), code)
        XCTAssertNotNil(output.backgroundColor)
    }

    func testHighlightSwiftReturnsNonEmptyWithBackground() async {
        let code = "let x = 42"
        let output = await SyntaxHighlighter.highlight(code, format: ".swift")
        XCTAssertFalse(String(output.text.characters).isEmpty)
        XCTAssertEqual(String(output.text.characters), code)
        XCTAssertNotNil(output.backgroundColor)
    }

    func testHighlightPreservesSourceText() async {
        let code = "console.log('hello');\nconst x = { key: 'value' };"
        let output = await SyntaxHighlighter.highlight(code, format: ".js")
        XCTAssertEqual(String(output.text.characters), code)
    }

    // MARK: - Non-Code Formats

    func testNonCodeFormatReturnsPlainTextWithNoBackground() async {
        let text = "This is plain text content."
        let output = await SyntaxHighlighter.highlight(text, format: ".pdf")
        XCTAssertEqual(String(output.text.characters), text)
        XCTAssertNil(output.backgroundColor)
    }

    func testUnknownFormatReturnsPlainTextWithNoBackground() async {
        let text = "Unknown format content."
        let output = await SyntaxHighlighter.highlight(text, format: ".xyz")
        XCTAssertEqual(String(output.text.characters), text)
        XCTAssertNil(output.backgroundColor)
    }

    // MARK: - Markdown

    func testMarkdownStripsHeaderMarkers() async {
        let md = "### Hello World"
        let output = await SyntaxHighlighter.highlight(md, format: ".md")
        XCTAssertEqual(String(output.text.characters), "Hello World")
        XCTAssertNil(output.backgroundColor)
    }

    func testMarkdownStripsInlineCode() async {
        let md = "Use `foo` here"
        let output = await SyntaxHighlighter.highlight(md, format: ".md")
        XCTAssertEqual(String(output.text.characters), "Use foo here")
    }

    func testMarkdownStripsBold() async {
        let md = "This is **bold** text"
        let output = await SyntaxHighlighter.highlight(md, format: ".md")
        XCTAssertEqual(String(output.text.characters), "This is bold text")
    }

    func testMarkdownStripsLinks() async {
        let md = "Click [here](https://example.com) now"
        let output = await SyntaxHighlighter.highlight(md, format: ".md")
        XCTAssertEqual(String(output.text.characters), "Click here now")
    }

    func testMarkdownStripsBlockQuotes() async {
        let md = "> Quoted text"
        let output = await SyntaxHighlighter.highlight(md, format: ".md")
        XCTAssertEqual(String(output.text.characters), "Quoted text")
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
        XCTAssertEqual(String(light.text.characters), code)
        XCTAssertEqual(String(dark.text.characters), code)
        XCTAssertNotEqual(light.text, dark.text)
    }

    func testDifferentThemesProduceDifferentResults() async {
        let code = "def foo(): pass"
        let xcode = await SyntaxHighlighter.highlight(
            code, format: ".py", theme: .xcode, lightMode: true
        )
        let github = await SyntaxHighlighter.highlight(
            code, format: ".py", theme: .github, lightMode: true
        )
        XCTAssertEqual(String(xcode.text.characters), code)
        XCTAssertEqual(String(github.text.characters), code)
        XCTAssertNotEqual(xcode.text, github.text)
    }
}
