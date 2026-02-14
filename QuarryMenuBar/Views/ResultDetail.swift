import SwiftUI

struct ResultDetail: View {

    // MARK: Internal

    let result: SearchResult
    let client: QuarryClient

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                Divider()
                Text(SyntaxHighlighter.highlight(result.text, format: result.sourceFormat, fontSize: 13))
                    .textSelection(.enabled)
                Spacer()
            }
            .padding(12)
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
                    .onTapGesture {
                        Task { await revealInFinder() }
                    }
                    .help("Reveal source file in Finder")
            }
            .foregroundStyle(.secondary)
        }
    }

    private func revealInFinder() async {
        do {
            let docs = try await client.documents(collection: result.collection)
            if let info = docs.documents.first(where: { $0.documentName == result.documentName }) {
                let url = URL(fileURLWithPath: info.documentPath)
                NSWorkspace.shared.activateFileViewerSelecting([url])
                NSApp.hide(nil)
            }
        } catch {
            // Fall back to opening the quarry data directory
            let home = FileManager.default.homeDirectoryForCurrentUser
            let dataDir = home.appendingPathComponent(".quarry").appendingPathComponent("data")
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dataDir.path)
        }
    }
}
