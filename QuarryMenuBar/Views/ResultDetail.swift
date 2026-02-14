import SwiftUI

struct ResultDetail: View {

    // MARK: Internal

    let result: SearchResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                Divider()
                Text(result.text)
                    .font(.body)
                    .textSelection(.enabled)
                Spacer()
            }
            .padding(12)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    copyText()
                } label: {
                    Label("Copy Text", systemImage: "doc.on.doc")
                }
                .help("Copy text to clipboard")

                Button {
                    revealInFinder()
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .help("Reveal source file in Finder")
            }
        }
    }

    // MARK: Private

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.documentName)
                .font(.headline)
            HStack(spacing: 12) {
                Label("Page \(result.pageNumber)", systemImage: "doc")
                    .font(.caption)
                Label(result.collection, systemImage: "folder")
                    .font(.caption)
                Label(String(format: "%.0f%% match", result.similarity * 100), systemImage: "target")
                    .font(.caption)
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
        }
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.text, forType: .string)
    }

    private func revealInFinder() {
        // The document path would come from the documents endpoint.
        // For now, construct a likely path from the quarry data directory.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dataDir = home
            .appendingPathComponent(".quarry")
            .appendingPathComponent("data")
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dataDir.path)
    }
}
