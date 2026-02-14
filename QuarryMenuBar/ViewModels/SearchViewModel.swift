import Foundation
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

    init(client: QuarryClient = QuarryClient()) {
        self.client = client
    }

    // MARK: Internal

    private(set) var state: SearchState = .idle

    let client: QuarryClient

    var query: String = "" {
        didSet {
            debounceSearch()
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
                let response = try await client.search(query: trimmed)
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
    }

    // MARK: Private

    private static let debounceInterval: Duration = .milliseconds(300)

    private var searchTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.puntlabs.quarry-menubar", category: "SearchViewModel")

    private func debounceSearch() {
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
