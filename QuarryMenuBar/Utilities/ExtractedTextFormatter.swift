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
        let reflowed = reflowParagraphs(in: normalized)
        return reflowed.isEmpty ? normalized : reflowed
    }

    static func shouldReflowDetailText(
        sourceFormat: String,
        pageType: String
    ) -> Bool {
        let normalizedPageType = pageType.trimmingCharacters(in: whitespace).lowercased()
        if normalizedPageType == "code"
            || normalizedPageType == "spreadsheet"
            || normalizedPageType == "presentation" {
            return false
        }

        return sourceFormat.caseInsensitiveCompare(".pdf") == .orderedSame
    }

    // MARK: Private

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

    private static func normalizeLineEndings(in text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
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

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: whitespace)

            if trimmed.isEmpty {
                flushParagraph()
                if !output.isEmpty, output.last?.isEmpty != true {
                    output.append("")
                }
                continue
            }

            if shouldPreserveLine(raw: rawLine, trimmed: trimmed) {
                flushParagraph()
                if !output.isEmpty, output.last?.isEmpty != true {
                    output.append("")
                }
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
                if !output.isEmpty, output.last?.isEmpty != true {
                    output.append("")
                }
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

    private static func shouldPreserveLine(
        raw: String,
        trimmed: String
    ) -> Bool {
        if raw.hasPrefix(" ") || raw.hasPrefix("\t") {
            return true
        }

        if isStandalonePageNumber(trimmed) {
            return true
        }

        if isListItem(trimmed) || isTableLike(trimmed) {
            return true
        }

        if isLikelyHeading(trimmed) {
            return true
        }

        return false
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
        !line.isEmpty && line.count <= 4 && line.allSatisfy(\.isNumber)
    }

    private static func shouldStartNewParagraph(
        after previousLine: String,
        before currentLine: String,
        typicalLineLength: Int
    ) -> Bool {
        guard typicalLineLength >= 40 else { return false }
        guard previousLine.count < Int(Double(typicalLineLength) * 0.72) else { return false }
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

    private static func isLikelyHeading(_ line: String) -> Bool {
        guard line.count <= 80,
              line.rangeOfCharacter(from: headingStopPunctuation) == nil
        else {
            return false
        }

        let tokens = line.split(whereSeparator: \.isWhitespace)
        let alphaTokens = tokens.filter { token in
            token.unicodeScalars.contains(where: CharacterSet.letters.contains)
        }

        guard (2 ... 12).contains(alphaTokens.count) else {
            return false
        }

        let capitalizedCount = alphaTokens.filter(isTitleLikeToken).count
        return capitalizedCount * 2 >= alphaTokens.count
    }

    private static func isTitleLikeToken(_ token: Substring) -> Bool {
        let scalars = token.unicodeScalars.filter(CharacterSet.letters.contains)
        guard let first = scalars.first else { return false }

        if CharacterSet.uppercaseLetters.contains(first) {
            return true
        }

        return scalars.allSatisfy(CharacterSet.uppercaseLetters.contains)
    }

    private static func joinParagraphLines(_ lines: [String]) -> String {
        guard var result = lines.first else { return "" }

        for line in lines.dropFirst() {
            if result.hasSuffix("-"),
               let firstCharacter = line.first,
               firstCharacter.isLowercase {
                result.removeLast()
                result += line
            } else {
                result += " " + line
            }
        }

        return result
    }
}
