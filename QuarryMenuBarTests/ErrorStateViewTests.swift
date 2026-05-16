@testable import QuarryMenuBar
import XCTest

@MainActor
final class ErrorStateViewTests: XCTestCase {
    func testErrorStateViewWithHintBuildsBody() {
        let view = ErrorStateView(
            title: "Quarry Configuration",
            message: "Pinned CA certificate not found.",
            hint: "Run quarry login again.",
            retryLabel: "Reload Config"
        ) {}
        XCTAssertNotNil(view.body)
    }

    func testErrorStateViewWithoutHintBuildsBody() {
        let view = ErrorStateView(
            title: "Quarry Unavailable",
            message: "Could not reach Quarry.",
            hint: nil,
            retryLabel: "Retry"
        ) {}
        XCTAssertNotNil(view.body)
    }
}
