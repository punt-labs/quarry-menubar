import HighlightSwift
import SwiftUI

struct ResultDetail: View {

    // MARK: Internal

    let result: SearchResult
    let client: QuarryClient

    var body: some View {
        let isCode = SyntaxHighlighter.isCodeFormat(result.sourceFormat)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                Divider()
                if let output = highlightOutput {
                    if isCode {
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(output.text)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background(output.backgroundColor ?? Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Text(output.text)
                            .textSelection(.enabled)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
                }
                Spacer()
            }
            .padding(12)
        }
        .task(id: taskID) {
            highlightOutput = nil
            let fontSize: CGFloat = isCode ? 11 : 13
            let newOutput = await SyntaxHighlighter.highlight(
                result.text,
                format: result.sourceFormat,
                fontSize: fontSize,
                theme: resolvedTheme,
                lightMode: colorScheme == .light
            )
            guard !Task.isCancelled else { return }
            highlightOutput = newOutput
        }
    }

    // MARK: Private

    @State private var highlightOutput: SyntaxHighlighter.Output?
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("syntaxTheme") private var themeName: String = "xcode"

    /// Re-run highlighting when result, theme, or color scheme changes.
    private var taskID: String {
        "\(result.id)-\(themeName)-\(colorScheme)"
    }

    /// Resolve the stored theme name to a HighlightTheme, falling back to .xcode.
    private var resolvedTheme: HighlightTheme {
        HighlightTheme.allCases.first { $0.rawValue.lowercased() == themeName.lowercased() } ?? .xcode
    }

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
                activateFinder()
            }
        } catch {
            // Fall back to opening the quarry data directory
            let home = FileManager.default.homeDirectoryForCurrentUser
            let dataDir = home.appendingPathComponent(".quarry").appendingPathComponent("data")
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dataDir.path)
            activateFinder()
        }
    }

    /// Bring Finder to the foreground.
    ///
    /// `activateFileViewerSelecting` reveals the file but doesn't raise Finder
    /// above other windows when called from an LSUIElement (agent) app.
    private func activateFinder() {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
            .first?
            .activate()
    }
}
