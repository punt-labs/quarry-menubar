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
                ResultDetail(result: selected)
            } else {
                resultsList
            }
        }
    }

    // MARK: Private

    @State private var selectedResult: SearchResult?

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search documents…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.body)
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
            ContentUnavailableView(
                "Search Your Documents",
                systemImage: "text.magnifyingglass",
                description: Text("Type a query to search across all indexed documents.")
            )
        case .loading:
            VStack {
                Spacer()
                ProgressView("Searching…")
                Spacer()
            }
        case let .results(results):
            List(results) { result in
                ResultRow(result: result)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedResult = result
                    }
            }
            .listStyle(.plain)
        case let .empty(query):
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass",
                description: Text("No documents matched \"\(query)\".")
            )
        case let .error(message):
            ContentUnavailableView(
                "Search Error",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
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

}
