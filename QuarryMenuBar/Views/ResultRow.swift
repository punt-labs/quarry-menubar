import SwiftUI

struct ResultRow: View {

    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(result.documentName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Label("p.\(result.pageNumber)", systemImage: "doc")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(SyntaxHighlighter.highlight(result.text, format: result.sourceFormat, fontSize: 11))
                .lineLimit(3)

            Text(result.collection)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 4)
    }

}
