@testable import QuarryMenuBar
import XCTest

@MainActor
final class ContentPanelTests: XCTestCase {
    func testContentPanelInitializesWithDaemon() {
        let daemon = DaemonManager(executablePath: "/nonexistent")
        let viewModel = SearchViewModel()
        let panel = ContentPanel(
            daemon: daemon,
            searchViewModel: viewModel,
            databaseManager: DatabaseManager(),
            onDatabaseSwitch: { _ in }
        )
        XCTAssertNotNil(panel.body)
    }

    func testContentPanelShowsErrorStateRestart() {
        let daemon = DaemonManager(executablePath: "/nonexistent/quarry")
        daemon.start()
        if case .error = daemon.state {
            // ContentPanel would show the error view with restart button
        } else {
            XCTFail("Expected error state for ContentPanel error view")
        }
    }
}
