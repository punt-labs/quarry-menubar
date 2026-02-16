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
        .task {
            await viewModel.loadCollections()
        }
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: viewModel.query) { _, newQuery in
            if newQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedResult = nil
                selectedResultID = nil
            }
        }
        .onChange(of: viewModel.selectedCollection) { _, _ in
            selectedResult = nil
            selectedResultID = nil
        }
    }

    // MARK: Private

    private static let emptyStateTopPadding: CGFloat = 40

    /// Anchor for scroll-to on selection change.
    /// Upward uses a point slightly below viewport top so partially-visible
    /// items fully clear sticky section headers and list chrome.
    private static let scrollAnchorUp = UnitPoint(x: 0.5, y: 0.15)

    @State private var selectedResult: SearchResult?
    @State private var selectedResultID: SearchResult.ID?

    @State private var scrollAnchor: UnitPoint = .top
    @FocusState private var isSearchFocused: Bool

    private var collectionPicker: some View {
        Menu {
            Button("All") {
                viewModel.selectedCollection = nil
            }
            if !viewModel.availableCollections.isEmpty {
                Divider()
                ForEach(viewModel.availableCollections, id: \.self) { name in
                    Button(name) {
                        viewModel.selectedCollection = name
                    }
                }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "folder")
                Text(viewModel.selectedCollection ?? "All")
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var searchField: some View {
        HStack {
            collectionPicker
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search documents…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isSearchFocused)
                .onSubmit {
                    if let id = selectedResultID,
                       case let .results(results) = viewModel.state,
                       let result = results.first(where: { $0.id == id }) {
                        selectedResult = result
                    } else {
                        viewModel.search()
                    }
                }
                .onExitCommand {
                    handleEscape()
                }
                .onKeyPress(.downArrow) {
                    selectedResult == nil ? moveSelection(by: 1) : .ignored
                }
                .onKeyPress(.upArrow) {
                    selectedResult == nil ? moveSelection(by: -1) : .ignored
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
            ScrollViewReader { proxy in
                List {
                    ForEach(sortedKeys, id: \.self) { format in
                        Section {
                            ForEach(grouped[format] ?? []) { result in
                                VStack(spacing: 0) {
                                    ResultRow(result: result)
                                    Divider()
                                }
                                .id(result.id)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                                .listRowBackground(
                                    result.id == selectedResultID
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.clear
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedResult = result
                                }
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
                    let ordered = flatResults(from: results)
                    if newID == ordered.first?.id {
                        // Scroll to the very top so section header isn't clipped
                        proxy.scrollTo(sortedKeys.first, anchor: .top)
                    } else {
                        proxy.scrollTo(newID, anchor: scrollAnchor)
                    }
                }
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
                    .font(.subheadline)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.text, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.subheadline)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func handleEscape() {
        if selectedResult != nil {
            selectedResult = nil
        } else if selectedResultID != nil {
            selectedResultID = nil
        } else {
            viewModel.clear()
            NSApp.keyWindow?.close()
        }
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        guard case let .results(results) = viewModel.state else { return .ignored }
        let ordered = flatResults(from: results)
        guard !ordered.isEmpty else { return .ignored }

        scrollAnchor = offset > 0 ? .bottom : Self.scrollAnchorUp
        if let currentID = selectedResultID,
           let currentIndex = ordered.firstIndex(where: { $0.id == currentID }) {
            let newIndex = currentIndex + offset
            if ordered.indices.contains(newIndex) {
                selectedResultID = ordered[newIndex].id
            }
        } else {
            // Nothing selected — Down selects first, Up selects last
            selectedResultID = offset > 0 ? ordered.first?.id : ordered.last?.id
        }
        return .handled
    }

    private func flatResults(from results: [SearchResult]) -> [SearchResult] {
        let grouped = Dictionary(grouping: results, by: \.sourceFormat)
        return grouped.keys.sorted().flatMap { grouped[$0] ?? [] }
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
