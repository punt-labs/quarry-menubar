import Foundation
import Observation
import os

// MARK: - SearchState

enum SearchState: Equatable {
    case idle
    case loading
    case results([SearchResult])
    case empty(String)
    case error(String)

    // MARK: Internal

    static func == (lhs: SearchState, rhs: SearchState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.loading, .loading):
            true
        case let (.results(lhsResults), .results(rhsResults)):
            lhsResults.map(\.id) == rhsResults.map(\.id)
        case let (.empty(lhsQuery), .empty(rhsQuery)):
            lhsQuery == rhsQuery
        case let (.error(lhsMsg), .error(rhsMsg)):
            lhsMsg == rhsMsg
        default:
            false
        }
    }
}

// MARK: - SearchViewModel

@MainActor
@Observable
final class SearchViewModel {

    // MARK: Lifecycle

    init(client: QuarryClient) {
        self.client = client
    }

    // MARK: Internal

    private(set) var availableCollections: [String] = []

    let client: QuarryClient

    // MARK: - UI Coordination

    //
    // Maps to Z specification state variables (z-spec/docs/search-panel.tex):
    //   selectedResult      → detail view target  (§5 line 89)
    //   highlightedResultID → list cursor         (§5 line 90)
    //

    private(set) var selectedResult: SearchResult?
    private(set) var highlightedResultID: SearchResult.ID?

    private(set) var state: SearchState = .idle {
        didSet {
            if case .results = state {} else {
                selectedResult = nil
                highlightedResultID = nil
            }
        }
    }

    var query: String = "" {
        didSet {
            debounceSearch()
        }
    }

    var selectedCollection: String? {
        didSet {
            // Re-run the current search when filter changes
            if oldValue != selectedCollection {
                selectedResult = nil
                highlightedResultID = nil
                search()
            }
        }
    }

    func search() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .idle
            return
        }

        searchTask?.cancel()
        searchTask = Task {
            state = .loading
            do {
                let response = try await client.search(query: trimmed, collection: selectedCollection)
                guard !Task.isCancelled else { return }
                if response.results.isEmpty {
                    state = .empty(trimmed)
                } else {
                    state = .results(response.results)
                }
            } catch is CancellationError {
                // Debounce cancellation — ignore
            } catch {
                guard !Task.isCancelled else { return }
                state = .error(error.localizedDescription)
                logger.error("Search failed: \(error)")
            }
        }
    }

    func clear() {
        query = ""
        searchTask?.cancel()
        state = .idle
        selectedResult = nil
        highlightedResultID = nil
    }

    func selectResult(_ result: SearchResult) {
        guard case let .results(results) = state,
              results.contains(where: { $0.id == result.id }) else { return }
        selectedResult = result
        highlightedResultID = nil
    }

    func highlightResult(_ resultID: SearchResult.ID) {
        guard selectedResult == nil,
              case let .results(results) = state,
              results.contains(where: { $0.id == resultID }) else { return }
        highlightedResultID = resultID
    }

    func clearHighlight() {
        highlightedResultID = nil
    }

    func closeDetail() {
        selectedResult = nil
        highlightedResultID = nil
    }

    func loadCollections() async {
        do {
            let response = try await client.collections()
            availableCollections = response.collections.map(\.collection).sorted()
        } catch is CancellationError {
            // Task cancelled (e.g. view disappeared) — not an error
        } catch {
            logger.error("Failed to load collections: \(error)")
        }
    }

    // MARK: Private

    private static let debounceInterval: Duration = .milliseconds(300)

    private var searchTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.puntlabs.quarry-menubar", category: "SearchViewModel")

    private func debounceSearch() {
        selectedResult = nil
        highlightedResultID = nil
        debounceTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchTask?.cancel()
            state = .idle
            return
        }

        debounceTask = Task {
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled else { return }
            search()
        }
    }
}
