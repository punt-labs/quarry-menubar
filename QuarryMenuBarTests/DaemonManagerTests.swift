@testable import QuarryMenuBar
import XCTest

@MainActor
final class DaemonManagerTests: XCTestCase {
    func testInitialStateIsStopped() {
        let manager = DaemonManager(executablePath: "/nonexistent")
        XCTAssertEqual(manager.state, .stopped)
    }

    func testStartWithInvalidPathSetsError() {
        let manager = DaemonManager(executablePath: "/nonexistent/quarry")
        manager.start()
        if case .error = manager.state {
            // Expected: launching a nonexistent binary fails
        } else {
            XCTFail("Expected error state, got: \(manager.state)")
        }
    }

    func testStopFromStoppedIsNoOp() {
        let manager = DaemonManager(executablePath: "/nonexistent")
        manager.stop()
        XCTAssertEqual(manager.state, .stopped)
    }

    func testStartGuardsAgainstDoubleStart() {
        let manager = DaemonManager(
            executablePath: "/bin/sleep",
            processArguments: ["5"]
        )
        addTeardownBlock { manager.stop() }
        manager.start()
        let stateAfterFirstStart = manager.state
        manager.start() // Should be a no-op since already running
        XCTAssertEqual(manager.state, stateAfterFirstStart)
        manager.stop()
    }

    func testDaemonStateEquatable() {
        XCTAssertEqual(DaemonState.stopped, DaemonState.stopped)
        XCTAssertEqual(DaemonState.starting, DaemonState.starting)
        XCTAssertEqual(DaemonState.running(pid: 42), DaemonState.running(pid: 42))
        XCTAssertNotEqual(DaemonState.running(pid: 42), DaemonState.running(pid: 99))
        XCTAssertNotEqual(DaemonState.stopped, DaemonState.starting)
    }
}
