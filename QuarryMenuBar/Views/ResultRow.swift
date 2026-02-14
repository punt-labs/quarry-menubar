import SwiftUI

struct ResultRow: View {

    // MARK: Internal

    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(result.documentName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(similarityLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text(result.text)
                .font(.body)
                .lineLimit(3)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Label("p.\(result.pageNumber)", systemImage: "doc")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(result.collection)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Private

    private var similarityLabel: String {
        String(format: "%.0f%%", result.similarity * 100)
    }
}
