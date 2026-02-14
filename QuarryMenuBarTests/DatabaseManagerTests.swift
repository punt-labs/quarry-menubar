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

// MARK: - SlowDatabaseDiscovery

/// Mock that sleeps before returning, useful for testing timeouts and reentrancy.
final class SlowDatabaseDiscovery: DatabaseDiscovery, @unchecked Sendable {

    // MARK: Lifecycle

    init(delay: Duration, databases: [DatabaseInfo] = []) {
        self.delay = delay
        self.databases = databases
    }

    // MARK: Internal

    private(set) var callCount = 0

    func discoverDatabases() async throws -> [DatabaseInfo] {
        callCount += 1
        try await Task.sleep(for: delay)
        return databases
    }

    // MARK: Private

    private let delay: Duration
    private let databases: [DatabaseInfo]
}

// MARK: - TwoPhaseDiscovery

/// Returns results immediately on first call, then hangs on subsequent calls.
final class TwoPhaseDiscovery: DatabaseDiscovery, @unchecked Sendable {

    // MARK: Lifecycle

    init(firstResult: [DatabaseInfo], subsequentDelay: Duration) {
        self.firstResult = firstResult
        self.subsequentDelay = subsequentDelay
    }

    // MARK: Internal

    func discoverDatabases() async throws -> [DatabaseInfo] {
        callCount += 1
        if callCount == 1 {
            return firstResult
        }
        try await Task.sleep(for: subsequentDelay)
        return []
    }

    // MARK: Private

    private var callCount = 0
    private let firstResult: [DatabaseInfo]
    private let subsequentDelay: Duration
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
            DatabaseInfo(name: "demo", documentCount: 28, sizeBytes: 2_831_155, sizeDescription: "2.7 MB"),
            DatabaseInfo(name: "courses", documentCount: 0, sizeBytes: 0, sizeDescription: "0 bytes")
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

    func testReentrancyGuardPreventsSecondDiscovery() async {
        let slow = SlowDatabaseDiscovery(delay: .milliseconds(200))
        let manager = DatabaseManager(
            discovery: slow,
            userDefaults: defaults
        )

        async let first: Void = manager.loadDatabases()
        async let second: Void = manager.loadDatabases()
        _ = await (first, second)

        XCTAssertEqual(slow.callCount, 1)
        XCTAssertFalse(manager.isDiscovering)
    }

    func testDiscoveryTimeoutSetsFlag() async {
        let manager = DatabaseManager(
            discovery: SlowDatabaseDiscovery(delay: .seconds(10)),
            userDefaults: defaults,
            discoveryTimeout: .milliseconds(100)
        )

        await manager.loadDatabases()

        XCTAssertTrue(manager.discoveryTimedOut)
        XCTAssertFalse(manager.isDiscovering)
        XCTAssertTrue(manager.availableDatabases.isEmpty)
    }

    func testSuccessfulDiscoveryDoesNotSetTimedOut() async {
        let mockDBs = [
            DatabaseInfo(name: "test", documentCount: 1, sizeBytes: 100, sizeDescription: "100 bytes")
        ]
        let manager = DatabaseManager(
            discovery: MockDatabaseDiscovery(databases: mockDBs),
            userDefaults: defaults
        )

        await manager.loadDatabases()

        XCTAssertFalse(manager.discoveryTimedOut)
        XCTAssertEqual(manager.availableDatabases.count, 1)
    }

    func testTimeoutPreservesExistingDatabases() async {
        let mockDBs = [
            DatabaseInfo(name: "cached", documentCount: 5, sizeBytes: 500, sizeDescription: "500 bytes")
        ]
        let discovery = TwoPhaseDiscovery(firstResult: mockDBs, subsequentDelay: .seconds(10))
        let manager = DatabaseManager(
            discovery: discovery,
            userDefaults: defaults,
            discoveryTimeout: .milliseconds(100)
        )

        // First load succeeds (returns immediately)
        await manager.loadDatabases()
        XCTAssertEqual(manager.availableDatabases.count, 1)
        XCTAssertFalse(manager.discoveryTimedOut)

        // Second load times out — cached data preserved
        await manager.loadDatabases()
        XCTAssertTrue(manager.discoveryTimedOut)
        XCTAssertEqual(manager.availableDatabases.count, 1)
        XCTAssertEqual(manager.availableDatabases[0].name, "cached")
    }

    // MARK: Private

    private let suiteName = "com.puntlabs.quarry-menubar.tests"
    private var defaults: UserDefaults = .standard
}

// MARK: - DatabaseInfoDecodingTests

final class DatabaseInfoDecodingTests: XCTestCase {

    // MARK: Internal

    func testDecodeSingleDatabase() throws {
        let json = """
        [{"name": "demo", "document_count": 28, "size_bytes": 2831155, "size_description": "2.7 MB"}]
        """
        let results = try decode(json)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "demo")
        XCTAssertEqual(results[0].documentCount, 28)
        XCTAssertEqual(results[0].sizeBytes, 2_831_155)
        XCTAssertEqual(results[0].sizeDescription, "2.7 MB")
    }

    func testDecodeMultipleDatabases() throws {
        let json = """
        [
          {"name": "demo", "document_count": 28, "size_bytes": 2831155, "size_description": "2.7 MB"},
          {"name": "courses", "document_count": 0, "size_bytes": 0, "size_description": "0 bytes"}
        ]
        """
        let results = try decode(json)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].name, "demo")
        XCTAssertEqual(results[1].name, "courses")
        XCTAssertEqual(results[1].documentCount, 0)
        XCTAssertEqual(results[1].sizeBytes, 0)
    }

    func testDecodeEmptyArray() throws {
        let results = try decode("[]")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: Private

    private func decode(_ json: String) throws -> [DatabaseInfo] {
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([DatabaseInfo].self, from: data)
    }
}
