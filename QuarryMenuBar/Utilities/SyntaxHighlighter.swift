import AppKit
import SwiftUI

/// Lightweight regex-based syntax highlighter for code snippets.
///
/// Uses `NSColor.system*` adaptive colors so output automatically
/// respects the system light/dark appearance.
enum SyntaxHighlighter {

    // MARK: Internal

    static func highlight(_ text: String, format: String, fontSize: CGFloat = 0) -> AttributedString {
        let size = fontSize > 0 ? fontSize : NSFont.smallSystemFontSize
        let nsAttr = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: nsAttr.length)

        let isCode = codeFormats.contains(format)
        let font: NSFont = isCode
            ? .monospacedSystemFont(ofSize: size, weight: .regular)
            : .systemFont(ofSize: size)

        nsAttr.addAttribute(.font, value: font, range: fullRange)
        nsAttr.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)

        if format == ".md" {
            return highlightMarkdown(text, fontSize: size)
        }

        let patterns: [(String, NSColor)] = switch format {
        case ".py": pythonPatterns
        default: isCode ? genericCodePatterns : []
        }

        for (pattern, color) in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.anchorsMatchLines]
            ) else { continue }
            for match in regex.matches(in: text, range: fullRange) {
                nsAttr.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }

        return AttributedString(nsAttr)
    }

    // MARK: Private

    /// A pending replacement: swap `range` with `replacement` and apply `attributes`.
    private struct InlineTransform {
        let range: NSRange
        let replacement: String
        let attributes: [NSAttributedString.Key: Any]
    }

    private static let codeFormats: Set<String> = [
        ".py", ".js", ".ts", ".swift", ".rs", ".go", ".java",
        ".c", ".cpp", ".h", ".rb", ".sh", ".toml", ".yaml", ".yml", ".json"
    ]

    // MARK: - Python

    private static let pythonPatterns: [(String, NSColor)] = [
        // Comments (must come first — overrides later matches within comments)
        (#"#[^\n]*"#, .secondaryLabelColor),
        // Triple-quoted strings
        (#""{3}[\s\S]*?"{3}"#, .systemRed),
        (#"'{3}[\s\S]*?'{3}"#, .systemRed),
        // Single/double quoted strings
        (#""[^"\n]*""#, .systemRed),
        (#"'[^'\n]*'"#, .systemRed),
        // Keywords
        (
            #"\b(def|class|import|from|return|if|else|elif|for|in|while|with|as|not|and|or|try|except|finally|raise|pass|break|continue|yield|lambda|global|nonlocal|assert|del|is|async|await)\b"#,
            .systemPurple
        ),
        // Built-in constants
        (#"\b(None|True|False|self)\b"#, .systemOrange),
        // Decorators
        (#"@\w+"#, .systemTeal),
        // Numbers
        (#"\b\d+\.?\d*\b"#, .systemBlue),
        // Function/class names after keyword
        (#"(?<=\bdef\s)\w+"#, .systemBlue),
        (#"(?<=\bclass\s)\w+"#, .systemBlue)
    ]

    // MARK: - Generic (C-family comments + strings)

    private static let genericCodePatterns: [(String, NSColor)] = [
        // Line comments
        (#"//[^\n]*"#, .secondaryLabelColor),
        (#"#[^\n]*"#, .secondaryLabelColor),
        // Strings
        (#""[^"\n]*""#, .systemRed),
        (#"'[^'\n]*'"#, .systemRed),
        // Numbers
        (#"\b\d+\.?\d*\b"#, .systemBlue)
    ]

    // MARK: - Markdown (strip syntax, apply formatting)

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
