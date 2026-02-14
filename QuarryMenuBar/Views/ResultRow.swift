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

            Text(result.text.prefix(200))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

}
