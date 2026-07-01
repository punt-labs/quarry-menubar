import Foundation

enum ExtractedTextFormatter {

    // MARK: Internal

    static func formatDetailText(
        _ text: String,
        sourceFormat: String,
        pageType: String
    ) -> String {
        guard shouldReflowDetailText(sourceFormat: sourceFormat, pageType: pageType) else {
            return text
        }

        let normalized = normalizeLineEndings(in: text)
        let lines = normalized.components(separatedBy: "\n")

        // Only reflow content whose line-length distribution looks like hard-wrapped
        // prose. Short-line content (verse, addresses, bibliographies) is passed through
        // UNCHANGED so its intentional line structure is never flattened into one blob.
        guard looksLikeHardWrappedProse(lines) else {
            return text
        }

        let reflowed = reflowParagraphs(in: normalized)
        return reflowed.isEmpty ? normalized : reflowed
    }

    static func shouldReflowDetailText(
        sourceFormat: String,
        pageType: String
    ) -> Bool {
        let normalizedPageType = pageType.trimmingCharacters(in: whitespace).lowercased()
        if nonProsePageTypes.contains(normalizedPageType) {
            return false
        }

        return sourceFormat.caseInsensitiveCompare(".pdf") == .orderedSame
    }

    // MARK: Private

    /// Page types whose text is structural rather than prose — never reflow these.
    private static let nonProsePageTypes: Set<String> = ["code", "spreadsheet", "presentation"]

    /// Minimum typical (median) line length for a page to be treated as hard-wrapped
    /// prose. Below this, lines are assumed to be intentionally short (verse, addresses,
    /// bibliographies) and the page is passed through unchanged.
    private static let minReflowLineLength = 40

    /// A line shorter than this fraction of the typical line length ends its paragraph:
    /// a short line followed by a capitalized line is a likely paragraph boundary.
    private static let paragraphBreakRatio = 0.72

    /// A heading candidate whose length reaches this fraction of the typical line length
    /// is treated as wrapped prose, not a heading. Real headings are short relative to the
    /// wrap column, so this prevents title-case-heavy wrapped sentences from being torn out.
    private static let headingWrapRatio = 0.72

    /// Absolute cap on heading length, in characters.
    private static let maxHeadingLength = 80

    private static let minHeadingTokens = 2
    private static let maxHeadingTokens = 12

    /// A bare number with at most this many digits is a candidate running-header page
    /// number (subject to the year-range exception in `isStandalonePageNumber`).
    private static let maxPageNumberDigits = 4

    /// Four-digit values in this range are plausible years — real content, not page chrome.
    private static let plausibleYearRange = 1000 ... 2999

    private static let whitespace = CharacterSet.whitespacesAndNewlines
    private static let headingStopPunctuation = CharacterSet(charactersIn: ".,;!?")
    private static let listPrefixes = [
        "- ",
        "* ",
        "• ",
        "■ ",
        "▪ ",
        "● ",
        "○ ",
        "o ",
        "· "
    ]

    /// Hard-compound prefixes: when a line-wrap hyphen follows one of these fragments,
    /// keep the hyphen — `well-known`, never `wellknown`. Several entries (`well`, `self`,
    /// `all`, `half`, `high`, `over`, `under`, …) are also complete common words, covering
    /// the "complete common word" case named in the fix without a full dictionary.
    private static let hardCompoundPrefixes: Set<String> = [
        "well", "self", "non", "co", "pre", "post", "anti", "multi", "semi",
        "ex", "all", "half", "high", "low", "long", "short", "cross", "mid",
        "sub", "super", "inter", "over", "under", "e", "x"
    ]

    /// Additional complete common words that habitually form hard compounds. Kept small and
    /// biased toward preserving the hyphen; an unrecognized fragment defaults to a soft-wrap
    /// join. Keeping a visible hyphen here (`time-line` vs `timeline`) is the recoverable
    /// error; merging into a fake word is not, so the bias favors this set being generous.
    private static let commonCompoundWords: Set<String> = [
        "time", "life", "home", "hand", "work", "world", "book", "water",
        "night", "day", "year", "school", "house", "child", "family", "side"
    ]

    private static func normalizeLineEndings(in text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// A page is treated as hard-wrapped prose only when its typical (median) prose line is
    /// long enough to indicate wrap-column content. Predominantly short lines mean the line
    /// breaks are intentional, so the caller passes the content through unchanged.
    private static func looksLikeHardWrappedProse(_ lines: [String]) -> Bool {
        medianNonPreservedLineLength(in: lines) >= minReflowLineLength
    }

    private static func reflowParagraphs(in text: String) -> String {
        let lines = stripLeadingPageChrome(from: text.components(separatedBy: "\n"))
        let typicalLineLength = medianNonPreservedLineLength(in: lines)
        var output: [String] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            output.append(joinParagraphLines(paragraphLines))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func appendBlankSeparator() {
            if !output.isEmpty, output.last?.isEmpty != true {
                output.append("")
            }
        }

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: whitespace)

            if trimmed.isEmpty {
                flushParagraph()
                appendBlankSeparator()
                continue
            }

            let atBlockStart = paragraphLines.isEmpty
            if isStructuralLine(raw: rawLine, trimmed: trimmed)
                || isHeadingLine(trimmed, atBlockStart: atBlockStart, typicalLineLength: typicalLineLength) {
                flushParagraph()
                appendBlankSeparator()
                output.append(trimmed)
                continue
            }

            if let previousLine = paragraphLines.last,
               shouldStartNewParagraph(
                   after: previousLine,
                   before: trimmed,
                   typicalLineLength: typicalLineLength
               ) {
                flushParagraph()
                appendBlankSeparator()
            }

            paragraphLines.append(trimmed)
        }

        flushParagraph()

        while output.last?.isEmpty == true {
            output.removeLast()
        }

        return output.joined(separator: "\n")
    }

    private static func medianNonPreservedLineLength(in lines: [String]) -> Int {
        let lengths = lines
            .map { raw in (raw, raw.trimmingCharacters(in: whitespace)) }
            .filter { raw, trimmed in
                !trimmed.isEmpty && !shouldPreserveLine(raw: raw, trimmed: trimmed)
            }
            .map { _, trimmed in trimmed.count }
            .sorted()

        guard !lengths.isEmpty else { return 0 }
        return lengths[lengths.count / 2]
    }

    /// Union of structural lines and (context-free) heading candidates. Used only to filter
    /// the median-length sample; the reflow loop uses the context-aware `isHeadingLine`.
    private static func shouldPreserveLine(
        raw: String,
        trimmed: String
    ) -> Bool {
        isStructuralLine(raw: raw, trimmed: trimmed) || isLikelyHeading(trimmed)
    }

    /// Lines whose structure must be preserved regardless of surrounding context: indented
    /// lines, standalone page numbers, list items, and table-like rows.
    private static func isStructuralLine(
        raw: String,
        trimmed: String
    ) -> Bool {
        if raw.hasPrefix(" ") || raw.hasPrefix("\t") {
            return true
        }

        if isStandalonePageNumber(trimmed) {
            return true
        }

        return isListItem(trimmed) || isTableLike(trimmed)
    }

    private static func stripLeadingPageChrome(from lines: [String]) -> [String] {
        var result = lines
        let nonEmptyIndices = result.indices.filter { !result[$0].trimmingCharacters(in: whitespace).isEmpty }

        guard nonEmptyIndices.count >= 2 else { return result }

        let headingIndex = nonEmptyIndices[0]
        let pageNumberIndex = nonEmptyIndices[1]
        let heading = result[headingIndex].trimmingCharacters(in: whitespace)
        let pageNumber = result[pageNumberIndex].trimmingCharacters(in: whitespace)

        guard isLikelyHeading(heading), isStandalonePageNumber(pageNumber) else {
            return result
        }

        result.remove(at: pageNumberIndex)
        return result
    }

    private static func isStandalonePageNumber(_ line: String) -> Bool {
        guard !line.isEmpty, line.count <= maxPageNumberDigits, line.allSatisfy(\.isNumber) else {
            return false
        }

        // A four-digit value in a plausible year range is real content (e.g. "2024"), not a
        // running-header page number, so it must never be stripped. Other 1–4 digit values
        // are treated as page chrome — including four-digit non-years, which are far more
        // likely to be large page numbers than data the reader would miss.
        if line.count == 4, let value = Int(line), plausibleYearRange.contains(value) {
            return false
        }

        return true
    }

    private static func shouldStartNewParagraph(
        after previousLine: String,
        before currentLine: String,
        typicalLineLength: Int
    ) -> Bool {
        guard typicalLineLength >= minReflowLineLength else { return false }
        guard previousLine.count < Int(Double(typicalLineLength) * paragraphBreakRatio) else { return false }
        guard previousLine.last.map(isParagraphTerminal) == true else { return false }
        guard currentLine.first?.isUppercase == true else { return false }
        return true
    }

    private static func isParagraphTerminal(_ character: Character) -> Bool {
        ".!?)]\"'".contains(character)
    }

    private static func isListItem(_ line: String) -> Bool {
        if listPrefixes.contains(where: { line.hasPrefix($0) }) {
            return true
        }

        return line.range(
            of: #"^(\d+|[A-Za-z])[.)]\s+"#,
            options: .regularExpression
        ) != nil
    }

    private static func isTableLike(_ line: String) -> Bool {
        if line.contains("|") {
            return true
        }

        return line.range(
            of: #"\S\s{2,}\S"#,
            options: .regularExpression
        ) != nil
    }

    /// Context-aware heading test used by the reflow loop. A line is only treated as a
    /// heading when it begins a fresh block (`atBlockStart`) and is short relative to the
    /// wrap column. Both guards prevent a title-case-heavy wrapped sentence from being torn
    /// out as a spurious heading, which would split one sentence into heading + orphan.
    private static func isHeadingLine(
        _ trimmed: String,
        atBlockStart: Bool,
        typicalLineLength: Int
    ) -> Bool {
        guard atBlockStart, isLikelyHeading(trimmed) else { return false }

        if typicalLineLength >= minReflowLineLength {
            let wrapThreshold = Int(Double(typicalLineLength) * headingWrapRatio)
            if trimmed.count >= wrapThreshold {
                return false
            }
        }

        return true
    }

    private static func isLikelyHeading(_ line: String) -> Bool {
        guard line.count <= maxHeadingLength,
              line.rangeOfCharacter(from: headingStopPunctuation) == nil
        else {
            return false
        }

        let tokens = line.split(whereSeparator: \.isWhitespace)
        let alphaTokens = tokens.filter { token in
            token.unicodeScalars.contains(where: CharacterSet.letters.contains)
        }

        guard (minHeadingTokens ... maxHeadingTokens).contains(alphaTokens.count) else {
            return false
        }

        let capitalizedCount = alphaTokens.filter(isTitleLikeToken).count
        return capitalizedCount * 2 >= alphaTokens.count
    }

    private static func isTitleLikeToken(_ token: Substring) -> Bool {
        guard let first = token.unicodeScalars.first(where: CharacterSet.letters.contains) else {
            return false
        }

        return CharacterSet.uppercaseLetters.contains(first)
    }

    private static func joinParagraphLines(_ lines: [String]) -> String {
        guard var result = lines.first else { return "" }

        for line in lines.dropFirst() {
            if result.hasSuffix("-"),
               let firstCharacter = line.first,
               firstCharacter.isLowercase {
                if shouldStripWrapHyphen(before: result) {
                    result.removeLast()
                    result += line
                } else {
                    result += line
                }
            } else {
                result += " " + line
            }
        }

        return result
    }

    /// Decide whether a line-ending hyphen is a soft wrap to remove, or part of a real hard
    /// compound to keep.
    ///
    /// The hyphen is stripped (words merged) only for "clear fragments" — the token before
    /// the hyphen is neither a curated hard-compound prefix (`well`, `self`, `non`, …) nor a
    /// complete common word (`time`, `home`, …). For those recognized prefixes the hyphen is
    /// preserved (`well-known`, not `wellknown`).
    ///
    /// Residual ambiguity: a genuine hard compound whose prefix is outside these curated sets
    /// is still merged, and a soft-wrapped word whose fragment happens to match a set entry
    /// keeps a visible hyphen. We accept the second error over the first — a visible hyphen is
    /// recoverable by the reader; a merged fake word is not.
    private static func shouldStripWrapHyphen(before result: String) -> Bool {
        let prefix = result
            .dropLast()
            .split(whereSeparator: \.isWhitespace)
            .last
            .map(String.init) ?? ""
        let normalized = prefix
            .trimmingCharacters(in: CharacterSet.letters.inverted)
            .lowercased()

        guard !normalized.isEmpty else { return true }

        if hardCompoundPrefixes.contains(normalized) || commonCompoundWords.contains(normalized) {
            return false
        }

        return true
    }
}
