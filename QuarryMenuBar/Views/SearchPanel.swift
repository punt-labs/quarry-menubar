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

    @State private var selectedResult: SearchResult?
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
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.clear()
                    selectedResult = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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
                    .padding(.top, 40)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        case .loading:
            VStack(alignment: .center, spacing: 8) {
                ProgressView("Searching…")
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            Spacer()
        case let .results(results):
            let grouped = Dictionary(grouping: results, by: \.sourceFormat)
            let sortedKeys = grouped.keys.sorted()
            List {
                ForEach(sortedKeys, id: \.self) { format in
                    Section(formatLabel(format)) {
                        ForEach(grouped[format] ?? []) { result in
                            ResultRow(result: result)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedResult = result
                                }
                        }
                    }
                }
            }
            .listStyle(.plain)
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
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            Spacer()
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
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            Spacer()
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
