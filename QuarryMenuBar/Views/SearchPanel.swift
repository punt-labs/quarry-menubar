import SwiftUI

struct SearchPanel: View {

    // MARK: Internal

    @Bindable var viewModel: SearchViewModel

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            if let selected = selectedResult {
                detailHeader(for: selected)
                Divider()
                ResultDetail(result: selected, client: viewModel.client)
            } else {
                resultsList
                    .animation(.easeInOut(duration: 0.15), value: viewModel.state)
            }
        }
        .onAppear {
            isSearchFocused = true
        }
    }

    // MARK: Private

    private static let emptyStateTopPadding: CGFloat = 40

    @State private var selectedResult: SearchResult?
    @State private var selectedResultID: SearchResult.ID?
    @FocusState private var isSearchFocused: Bool

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search documents…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isSearchFocused)
                .onSubmit {
                    viewModel.search()
                }
                .onExitCommand {
                    handleEscape()
                }
        }
        .padding(10)
    }

    @ViewBuilder
    private var resultsList: some View {
        switch viewModel.state {
        case .idle:
            VStack {
                Text("Type a query to search across all indexed documents.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Self.emptyStateTopPadding)
        case .loading:
            VStack(spacing: 8) {
                ProgressView("Searching…")
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Self.emptyStateTopPadding)
        case let .results(results):
            let grouped = Dictionary(grouping: results, by: \.sourceFormat)
            let sortedKeys = grouped.keys.sorted()
            List(selection: $selectedResultID) {
                ForEach(sortedKeys, id: \.self) { format in
                    Section {
                        ForEach(grouped[format] ?? []) { result in
                            VStack(spacing: 0) {
                                ResultRow(result: result)
                                Divider()
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                        }
                    } header: {
                        Text(formatLabel(format))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .onChange(of: selectedResultID) { _, newID in
                guard let newID else { return }
                selectedResult = results.first { $0.id == newID }
                selectedResultID = nil
            }
        case let .empty(query):
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text("No Results")
                    .font(.headline)
                Text("No documents matched \"\(query)\".")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Self.emptyStateTopPadding)
        case let .error(message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.red)
                Text("Search Error")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Self.emptyStateTopPadding)
        }
    }

    private func detailHeader(for result: SearchResult) -> some View {
        HStack {
            Button {
                selectedResult = nil
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.text, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func handleEscape() {
        if selectedResult != nil {
            selectedResult = nil
        } else {
            viewModel.clear()
            NSApp.keyWindow?.close()
        }
    }

    private func formatLabel(_ format: String) -> String {
        switch format {
        case ".py": "Python"
        case ".md": "Markdown"
        case ".pdf": "PDF Documents"
        case ".txt": "Text Files"
        case ".tex": "LaTeX"
        case ".docx": "Word Documents"
        default: format.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
    }

}
