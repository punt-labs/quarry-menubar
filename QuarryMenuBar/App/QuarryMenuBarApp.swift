import SwiftUI

// MARK: - AppDelegate

/// Owns the app-lifetime `ConnectionManager` and starts the initial connect at
/// `applicationDidFinishLaunching`.
///
/// The connect cannot be driven from the SwiftUI scene: `MenuBarExtra` builds
/// both its label and its window content lazily, so a `.task` on either does not
/// run until the user first opens the panel. Worse, the panel's `.task` is
/// cancelled on every window teardown — running the connect there cancelled the
/// in-flight request and surfaced a spurious "Unavailable — CancellationError"
/// (the bug this delegate fixes). `applicationDidFinishLaunching` is the
/// app-scope hook that fires once at startup, independent of any window; the
/// connect it starts runs in a manager-owned task that outlives every panel.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let connectionManager = ConnectionManager()

    func applicationDidFinishLaunching(_: Notification) {
        connectionManager.connectIfNeeded()
    }
}

// MARK: - QuarryMenuBarApp

@main
struct QuarryMenuBarApp: App {

    // MARK: Internal

    var body: some Scene {
        MenuBarExtra {
            ContentPanel(connectionManager: appDelegate.connectionManager)
                .frame(width: 550, height: 500)
        } label: {
            Image(systemName: statusBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: Private

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var statusBarIcon: String {
        switch appDelegate.connectionManager.state {
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
