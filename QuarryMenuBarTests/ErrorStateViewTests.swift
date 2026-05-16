@testable import QuarryMenuBar
import XCTest

@MainActor
final class ErrorStateViewTests: XCTestCase {
    func testErrorStateViewStoresDisplayConfigurationAndRetryAction() {
        var didRetry = false
        let view = ErrorStateView(
            title: "Quarry Configuration",
            message: "Pinned CA certificate not found.",
            hint: "Run quarry login again.",
            retryLabel: "Reload Config"
        ) {
            didRetry = true
        }

        XCTAssertEqual(view.title, "Quarry Configuration")
        XCTAssertEqual(view.message, "Pinned CA certificate not found.")
        XCTAssertEqual(view.hint, "Run quarry login again.")
        XCTAssertEqual(view.retryLabel, "Reload Config")

        view.onRetry()
        XCTAssertTrue(didRetry)
    }

    func testErrorStateViewSupportsNilHint() {
        let view = ErrorStateView(
            title: "Quarry Unavailable",
            message: "Could not reach Quarry.",
            hint: nil,
            retryLabel: "Retry"
        ) {}

        XCTAssertEqual(view.title, "Quarry Unavailable")
        XCTAssertEqual(view.message, "Could not reach Quarry.")
        XCTAssertNil(view.hint)
        XCTAssertEqual(view.retryLabel, "Retry")
    }
}
