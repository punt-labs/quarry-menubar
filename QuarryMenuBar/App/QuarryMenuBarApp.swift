import SwiftUI

@main
struct QuarryMenuBarApp: App {

    // MARK: Lifecycle

    init() {
        let dbManager = DatabaseManager()
        let initialDB = dbManager.currentDatabase
        _databaseManager = State(initialValue: dbManager)
        _daemon = State(initialValue: DaemonManager(databaseName: initialDB))
        _searchViewModel = State(initialValue: SearchViewModel(
            client: QuarryClient(databaseName: initialDB)
        ))
    }

    // MARK: Internal

    var body: some Scene {
        MenuBarExtra("Quarry", systemImage: statusBarIcon) {
            ContentPanel(
                daemon: daemon,
                searchViewModel: searchViewModel,
                databaseManager: databaseManager,
                onDatabaseSwitch: switchDatabase
            )
            .frame(width: 400, height: 500)
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: Private

    @State private var databaseManager: DatabaseManager
    @State private var daemon: DaemonManager
    @State private var searchViewModel: SearchViewModel

    private var statusBarIcon: String {
        switch daemon.state {
        case .stopped,
             .starting:
            "doc.text.magnifyingglass"
        case .running:
            "doc.text.magnifyingglass"
        case .error:
            "exclamationmark.triangle"
        }
    }

    private func switchDatabase(_ newDatabase: String) {
        daemon.stop()
        searchViewModel.clear()
        databaseManager.selectDatabase(newDatabase)
        daemon = DaemonManager(databaseName: newDatabase)
        searchViewModel = SearchViewModel(
            client: QuarryClient(databaseName: newDatabase)
        )
        // Delay mirrors DaemonManager.restart() — lets the old process
        // and port file clean up before the new daemon binds.
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            daemon.start()
        }
    }
}
