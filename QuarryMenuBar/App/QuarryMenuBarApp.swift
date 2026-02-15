import SwiftUI

@main
struct QuarryMenuBarApp: App {

    // MARK: Lifecycle

    init() {
        let quarryPath = ExecutableResolver.resolve()
        let dbManager: DatabaseManager
        if let quarryPath {
            let discovery = CLIDatabaseDiscovery(
                executablePath: quarryPath,
                processArguments: ["databases", "--json"]
            )
            dbManager = DatabaseManager(discovery: discovery)
        } else {
            dbManager = DatabaseManager()
        }
        let initialDB = dbManager.currentDatabase
        _quarryPath = State(initialValue: quarryPath)
        _databaseManager = State(initialValue: dbManager)
        _daemon = State(initialValue: DaemonManager(
            databaseName: initialDB,
            executablePath: quarryPath ?? "/usr/bin/env",
            processArguments: quarryPath != nil
                ? ["serve", "--db", initialDB]
                : nil
        ))
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
            .frame(width: 550, height: 500)
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: Private

    @State private var quarryPath: String?
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
        daemon = DaemonManager(
            databaseName: newDatabase,
            executablePath: quarryPath ?? "/usr/bin/env",
            processArguments: quarryPath != nil
                ? ["serve", "--db", newDatabase]
                : nil
        )
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
