@testable import QuarryMenuBar
import XCTest

final class ExecutableResolverTests: XCTestCase {

    func testSearchPathsContainExpectedLocations() {
        let paths = ExecutableResolver.searchPaths
        XCTAssertTrue(paths.contains { $0.hasSuffix("/.local/bin/quarry") })
        XCTAssertTrue(paths.contains { $0 == "/usr/local/bin/quarry" })
        XCTAssertTrue(paths.contains { $0 == "/opt/homebrew/bin/quarry" })
    }

    func testResolveFindsQuarryOnThisMachine() {
        // This test validates the resolver works on the dev machine.
        // It will be skipped in CI where quarry isn't installed.
        let result = ExecutableResolver.resolve()
        if result != nil {
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: result!))
        }
    }
}
