@testable import QuarryMenuBar
import XCTest

// MARK: - MockDatabaseDiscovery

struct MockDatabaseDiscovery: DatabaseDiscovery {

    let databases: [DatabaseInfo]

    func discoverDatabases() async throws -> [DatabaseInfo] {
        databases
    }
}

// MARK: - FailingDatabaseDiscovery

struct FailingDatabaseDiscovery: DatabaseDiscovery {
    func discoverDatabases() async throws -> [DatabaseInfo] {
        throw DatabaseManagerError.discoveryFailed("mock failure")
    }
}

// MARK: - DatabaseManagerTests

@MainActor
final class DatabaseManagerTests: XCTestCase {

    // MARK: Internal

    override func setUp() {
        super.setUp()
        guard let suite = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults = suite
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultDatabaseIsDefault() {
        let manager = DatabaseManager(
            discovery: MockDatabaseDiscovery(databases: []),
            userDefaults: defaults
        )
        XCTAssertEqual(manager.currentDatabase, "default")
    }

    func testPersistsSelectedDatabase() {
        let manager = DatabaseManager(
            discovery: MockDatabaseDiscovery(databases: []),
            userDefaults: defaults
        )
        manager.selectDatabase("demo")
        XCTAssertEqual(manager.currentDatabase, "demo")

        // New manager reads persisted value
        let manager2 = DatabaseManager(
            discovery: MockDatabaseDiscovery(databases: []),
            userDefaults: defaults
        )
        XCTAssertEqual(manager2.currentDatabase, "demo")
    }

    func testSelectSameDatabaseIsNoOp() {
        let manager = DatabaseManager(
            discovery: MockDatabaseDiscovery(databases: []),
            userDefaults: defaults
        )
        manager.selectDatabase("default")
        XCTAssertEqual(manager.currentDatabase, "default")
    }

    func testLoadDatabasesPopulatesAvailableDatabases() async {
        let mockDBs = [
            DatabaseInfo(name: "demo", documentCount: 28, sizeDescription: "2.7 MB"),
            DatabaseInfo(name: "courses", documentCount: 0, sizeDescription: "0.0 KB")
        ]
        let manager = DatabaseManager(
            discovery: MockDatabaseDiscovery(databases: mockDBs),
            userDefaults: defaults
        )

        await manager.loadDatabases()

        XCTAssertEqual(manager.availableDatabases.count, 2)
        XCTAssertEqual(manager.availableDatabases[0].name, "demo")
        XCTAssertEqual(manager.availableDatabases[1].name, "courses")
        XCTAssertFalse(manager.isDiscovering)
    }

    func testFailedDiscoveryKeepsEmptyList() async {
        let manager = DatabaseManager(
            discovery: FailingDatabaseDiscovery(),
            userDefaults: defaults
        )
        await manager.loadDatabases()
        // On failure, available databases remain empty (not set to an error state)
        XCTAssertTrue(manager.availableDatabases.isEmpty)
        XCTAssertFalse(manager.isDiscovering)
    }

    func testIsDiscoveringTransitions() async {
        let manager = DatabaseManager(
            discovery: MockDatabaseDiscovery(databases: []),
            userDefaults: defaults
        )
        XCTAssertFalse(manager.isDiscovering)
        await manager.loadDatabases()
        // After completion, isDiscovering is false
        XCTAssertFalse(manager.isDiscovering)
    }

    // MARK: Private

    private let suiteName = "com.puntlabs.quarry-menubar.tests"
    private var defaults: UserDefaults = .standard
}

// MARK: - CLIDatabaseDiscoveryParseTests

final class CLIDatabaseDiscoveryParseTests: XCTestCase {

    // MARK: Internal

    func testParseSingleDatabase() {
        let output = "demo: 28 documents, 2.7 MB\n"
        let results = parseCLIOutput(output)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "demo")
        XCTAssertEqual(results[0].documentCount, 28)
        XCTAssertEqual(results[0].sizeDescription, "2.7 MB")
    }

    func testParseMultipleDatabases() {
        let output = """
        demo: 28 documents, 2.7 MB
        courses: 0 documents, 0.0 KB
        """
        let results = parseCLIOutput(output)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].name, "demo")
        XCTAssertEqual(results[1].name, "courses")
        XCTAssertEqual(results[1].documentCount, 0)
        XCTAssertEqual(results[1].sizeDescription, "0.0 KB")
    }

    func testParseSingularDocument() {
        let output = "single: 1 document, 0.1 MB\n"
        let results = parseCLIOutput(output)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].documentCount, 1)
    }

    func testParseEmptyOutput() {
        let results = parseCLIOutput("")
        XCTAssertTrue(results.isEmpty)
    }

    func testParseBlankLines() {
        let output = "\n\n  \n"
        let results = parseCLIOutput(output)
        XCTAssertTrue(results.isEmpty)
    }

    func testParseMalformedLineSkipped() {
        let output = "no colon here\ndemo: 28 documents, 2.7 MB\n"
        let results = parseCLIOutput(output)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "demo")
    }

    // MARK: Private

    private func parseCLIOutput(_ output: String) -> [DatabaseInfo] {
        CLIDatabaseDiscovery.parse(output)
    }
}
