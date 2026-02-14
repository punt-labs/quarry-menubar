import SwiftUI

struct SearchPanel: View {

    // MARK: Internal

    @Bindable var viewModel: SearchViewModel

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            resultsList
        }
    }

    // MARK: Private

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
}
