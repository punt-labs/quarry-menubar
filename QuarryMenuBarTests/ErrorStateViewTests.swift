@testable import QuarryMenuBar
import XCTest

@MainActor
final class ErrorStateViewTests: XCTestCase {
    func testErrorStateViewWithNotFoundMessage() {
        let view = ErrorStateView(message: "Failed to start: No such file or directory") {}
        XCTAssertNotNil(view.body)
    }

    func testErrorStateViewWithCrashMessage() {
        let view = ErrorStateView(message: "Process exited with code 1") {}
        XCTAssertNotNil(view.body)
    }

    func testErrorStateViewWithUnknownMessage() {
        let view = ErrorStateView(message: "Something unexpected happened") {}
        XCTAssertNotNil(view.body)
    }
}
