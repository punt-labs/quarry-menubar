import AppKit
import HighlightSwift
import SwiftUI

/// Syntax highlighter that delegates code coloring to HighlightSwift (highlight.js)
/// and handles Markdown formatting with custom inline-transform logic.
enum SyntaxHighlighter {

    // MARK: Internal

    /// Whether the given file extension is treated as source code (monospace font).
    static func isCodeFormat(_ format: String) -> Bool {
        languageMap[format] != nil
    }

    /// Map a source-format extension to a HighlightSwift language.
    /// Returns `nil` for non-code formats (.pdf, .txt, .tex, .docx, .md).
    static func language(for format: String) -> HighlightLanguage? {
        languageMap[format]
    }

    /// Highlight code or format prose for display.
    ///
    /// - Code formats: tokenized by highlight.js via HighlightSwift
    /// - Markdown: custom syntax stripping + inline formatting
    /// - Everything else: plain text with system font
    static func highlight(
        _ text: String,
        format: String,
        fontSize: CGFloat = 0,
        theme: HighlightTheme = .xcode,
        lightMode: Bool = true
    ) async -> AttributedString {
        let size = fontSize > 0 ? fontSize : NSFont.smallSystemFontSize

        if format == ".md" {
            return highlightMarkdown(text, fontSize: size)
        }

        guard let lang = languageMap[format] else {
            return plainText(text, fontSize: size)
        }

        let colors: HighlightColors = lightMode ? .light(theme) : .dark(theme)
        do {
            var result = try await highlighter.attributedText(text, language: lang, colors: colors)
            let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            var fontAttrs = AttributeContainer()
            fontAttrs.appKit.font = font
            result.mergeAttributes(fontAttrs)
            return result
        } catch {
            // Fallback to plain monospace on highlight.js failure
            return plainText(text, fontSize: size, monospace: true)
        }
    }

    // MARK: Private

    // MARK: - Markdown (strip syntax, apply formatting)

    /// A pending replacement: swap `range` with `replacement` and apply `attributes`.
    private struct InlineTransform {
        let range: NSRange
        let replacement: String
        let attributes: [NSAttributedString.Key: Any]
    }

    /// Shared Highlight instance — reuses the JavaScriptCore context across calls.
    private static let highlighter = Highlight()

    /// Extension → HighlightLanguage mapping. Only code formats appear here;
    /// absence means the format gets plain-text treatment.
    private static let languageMap: [String: HighlightLanguage] = [
        ".py": .python,
        ".js": .javaScript,
        ".ts": .typeScript,
        ".swift": .swift,
        ".rs": .rust,
        ".go": .go,
        ".java": .java,
        ".c": .c,
        ".cpp": .cPlusPlus,
        ".h": .c,
        ".rb": .ruby,
        ".sh": .bash,
        ".toml": .toml,
        ".yaml": .yaml,
        ".yml": .yaml,
        ".json": .json
    ]

    private static func plainText(
        _ text: String,
        fontSize: CGFloat,
        monospace: Bool = false
    ) -> AttributedString {
        let font: NSFont = monospace
            ? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            : .systemFont(ofSize: fontSize)
        var attrs = AttributeContainer()
        attrs.appKit.font = font
        attrs.appKit.foregroundColor = .labelColor
        var result = AttributedString(text)
        result.mergeAttributes(attrs)
        return result
    }

    private static func highlightMarkdown(_ text: String, fontSize: CGFloat) -> AttributedString {
        let baseFont = NSFont.systemFont(ofSize: fontSize)
        let boldFont = NSFont.boldSystemFont(ofSize: fontSize)
        let monoFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let result = NSMutableAttributedString()
        let lines = text.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            var processed = line
            var lineFont = baseFont
            var lineColor = NSColor.labelColor

            // Strip header markers: ### Title → Title (bold)
            if let match = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                processed = String(line[match.upperBound...])
                lineFont = boldFont
            }
            // Strip block quote markers: > text → text (dimmed)
            else if let match = line.range(of: #"^>\s+"#, options: .regularExpression) {
                processed = String(line[match.upperBound...])
                lineColor = NSColor.secondaryLabelColor
            }

            let lineAttr = NSMutableAttributedString(string: processed)
            let fullRange = NSRange(location: 0, length: lineAttr.length)
            lineAttr.addAttribute(.font, value: lineFont, range: fullRange)
            lineAttr.addAttribute(.foregroundColor, value: lineColor, range: fullRange)

            applyInlineTransforms(to: lineAttr, monoFont: monoFont, boldFont: boldFont)

            result.append(lineAttr)
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }

        return AttributedString(result)
    }

    /// Replace inline markdown syntax (backticks, bold, links) with formatted text.
    /// Longer matches win when ranges overlap; transforms apply in reverse position order.
    private static func applyInlineTransforms(
        to attr: NSMutableAttributedString,
        monoFont: NSFont,
        boldFont: NSFont
    ) {
        let text = attr.string
        let fullRange = NSRange(location: 0, length: attr.length)
        var transforms: [InlineTransform] = []

        // Inline code: `text` → text (monospace, teal)
        if let regex = try? NSRegularExpression(pattern: #"`([^`]+)`"#) {
            for match in regex.matches(in: text, range: fullRange) {
                let content = (text as NSString).substring(with: match.range(at: 1))
                transforms.append(InlineTransform(
                    range: match.range, replacement: content,
                    attributes: [.font: monoFont, .foregroundColor: NSColor.systemTeal]
                ))
            }
        }

        // Bold: **text** → text (bold)
        if let regex = try? NSRegularExpression(pattern: #"\*\*([^*]+)\*\*"#) {
            for match in regex.matches(in: text, range: fullRange) {
                let content = (text as NSString).substring(with: match.range(at: 1))
                transforms.append(InlineTransform(
                    range: match.range, replacement: content,
                    attributes: [.font: boldFont]
                ))
            }
        }

        // Links: [text](url) → text (blue)
        if let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\([^)]+\)"#) {
            for match in regex.matches(in: text, range: fullRange) {
                let content = (text as NSString).substring(with: match.range(at: 1))
                transforms.append(InlineTransform(
                    range: match.range, replacement: content,
                    attributes: [.foregroundColor: NSColor.systemBlue]
                ))
            }
        }

        // Resolve overlaps: longer matches win
        transforms.sort { $0.range.length > $1.range.length }
        var used = IndexSet()
        var kept: [InlineTransform] = []
        for transform in transforms {
            let span = transform.range.location ..< (transform.range.location + transform.range.length)
            guard !used.intersects(integersIn: span) else { continue }
            used.insert(integersIn: span)
            kept.append(transform)
        }

        // Apply in reverse position order so earlier ranges stay valid
        kept.sort { $0.range.location > $1.range.location }
        for transform in kept {
            var attrs: [NSAttributedString.Key: Any] = transform.range.location < attr.length
                ? attr.attributes(at: transform.range.location, effectiveRange: nil)
                : [:]
            for (key, value) in transform.attributes {
                attrs[key] = value
            }
            attr.replaceCharacters(
                in: transform.range,
                with: NSAttributedString(string: transform.replacement, attributes: attrs)
            )
        }
    }

}
