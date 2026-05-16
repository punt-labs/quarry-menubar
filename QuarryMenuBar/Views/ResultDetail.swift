import HighlightSwift
import SwiftUI

struct ResultDetail: View {

    // MARK: Internal

    let result: SearchResult
    let client: QuarryClient
    let allowsFinderReveal: Bool

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
            let displayText = await resolvedDetailText()
            guard !Task.isCancelled else { return }
            let fontSize: CGFloat = isCode ? 11 : 13
            let newOutput = await SyntaxHighlighter.highlight(
                displayText,
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
                if allowsFinderReveal {
                    Button {
                        Task { await revealInFinder() }
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder.badge.gearshape")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal source file in Finder")
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    private func resolvedDetailText() async -> String {
        do {
            let response = try await client.show(
                document: result.documentName,
                page: result.pageNumber,
                collection: result.collection
            )
            return response.text
        } catch {
            return result.text
        }
    }

    private func revealInFinder() async {
        guard allowsFinderReveal else { return }
        do {
            let docs = try await client.documents(collection: result.collection)
            if let info = docs.documents.first(where: { $0.documentName == result.documentName }) {
                guard FileManager.default.fileExists(atPath: info.documentPath) else {
                    openFallbackDataDirectory()
                    return
                }
                let url = URL(fileURLWithPath: info.documentPath)
                NSWorkspace.shared.activateFileViewerSelecting([url])
                activateFinder()
                return
            }
            openFallbackDataDirectory()
        } catch {
            openFallbackDataDirectory()
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

    private func openFallbackDataDirectory() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dataDir = home
            .appendingPathComponent(".punt-labs")
            .appendingPathComponent("quarry")
            .appendingPathComponent("data")
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dataDir.path)
        activateFinder()
    }
}
