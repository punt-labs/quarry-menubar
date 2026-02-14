import SwiftUI

@main
struct QuarryMenuBarApp: App {

    // MARK: Internal

    var body: some Scene {
        MenuBarExtra("Quarry", systemImage: statusBarIcon) {
            ContentPanel(daemon: daemon, searchViewModel: searchViewModel)
                .frame(width: 400, height: 500)
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: Private

    @State private var daemon = DaemonManager()
    @State private var searchViewModel = SearchViewModel()

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
}
