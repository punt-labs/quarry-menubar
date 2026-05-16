import SwiftUI

@main
struct QuarryMenuBarApp: App {

    // MARK: Internal

    var body: some Scene {
        MenuBarExtra {
            ContentPanel(connectionManager: connectionManager)
                .frame(width: 550, height: 500)
        } label: {
            Image(systemName: statusBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: Private

    @State private var connectionManager = ConnectionManager()

    private var statusBarIcon: String {
        switch connectionManager.state {
        case .idle,
             .connecting,
             .connected:
            "sparkle.magnifyingglass"
        case .unavailable,
             .misconfigured:
            "exclamationmark.triangle.fill"
        }
    }
}
