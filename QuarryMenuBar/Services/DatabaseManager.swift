import Foundation
import os

// MARK: - DatabaseInfo

struct DatabaseInfo: Sendable, Identifiable, Equatable, Codable {

    let name: String
    let documentCount: Int
    let sizeBytes: Int
    let sizeDescription: String

    var id: String {
        name
    }
}

// MARK: - DatabaseDiscovery

/// Abstraction over `quarry databases` CLI for testability.
protocol DatabaseDiscovery: Sendable {
    func discoverDatabases() async throws -> [DatabaseInfo]
}

// MARK: - CLIDatabaseDiscovery

/// Runs `quarry databases --json` and decodes the JSON output.
struct CLIDatabaseDiscovery: DatabaseDiscovery {

    // MARK: Lifecycle

    init(
        executablePath: String = "/usr/bin/env",
        processArguments: [String]? = nil
    ) {
        self.executablePath = executablePath
        self.processArguments = processArguments ?? ["quarry", "databases", "--json"]
    }

    // MARK: Internal

    func discoverDatabases() async throws -> [DatabaseInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = processArguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        // Set terminationHandler BEFORE run() to avoid a race where the
        // process completes before the handler is registered.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        guard process.terminationStatus == 0 else {
            throw DatabaseManagerError.discoveryFailed("quarry databases exited with code \(process.terminationStatus)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([DatabaseInfo].self, from: data)
    }

    // MARK: Private

    private let executablePath: String
    private let processArguments: [String]
}

// MARK: - DatabaseManagerError

enum DatabaseManagerError: LocalizedError {
    case discoveryFailed(String)
    case discoveryTimedOut

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .discoveryFailed(message):
            "Database discovery failed: \(message)"
        case .discoveryTimedOut:
            "Database discovery timed out"
        }
    }
}

// MARK: - DatabaseManager

/// Manages database selection, discovery, and persistence.
@MainActor
@Observable
final class DatabaseManager {

    // MARK: Lifecycle

    init(
        discovery: DatabaseDiscovery = CLIDatabaseDiscovery(),
        userDefaults: UserDefaults = .standard,
        discoveryTimeout: Duration = .seconds(5)
    ) {
        self.discovery = discovery
        self.userDefaults = userDefaults
        self.discoveryTimeout = discoveryTimeout
        currentDatabase = userDefaults.string(forKey: Self.selectedDatabaseKey) ?? "default"
        availableDatabases = Self.loadCachedDatabases(from: userDefaults)
    }

    // MARK: Internal

    private(set) var availableDatabases: [DatabaseInfo] = []
    private(set) var isDiscovering = false
    private(set) var discoveryTimedOut = false

    private(set) var currentDatabase: String {
        didSet {
            userDefaults.set(currentDatabase, forKey: Self.selectedDatabaseKey)
        }
    }

    func loadDatabases() async {
        guard !isDiscovering else { return }
        isDiscovering = true
        discoveryTimedOut = false
        defer { isDiscovering = false }

        let timeout = discoveryTimeout
        do {
            let discovered = try await withThrowingTaskGroup(of: [DatabaseInfo].self) { group in
                group.addTask {
                    try await self.discovery.discoverDatabases()
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw DatabaseManagerError.discoveryTimedOut
                }
                guard let result = try await group.next() else {
                    throw DatabaseManagerError.discoveryFailed("No discovery result")
                }
                group.cancelAll()
                return result
            }
            availableDatabases = discovered
            Self.cacheDatabases(discovered, to: userDefaults)
            logger.info("Discovered \(discovered.count) databases")
        } catch {
            if case DatabaseManagerError.discoveryTimedOut = error {
                discoveryTimedOut = true
                logger.warning("Database discovery timed out after \(timeout)")
            } else {
                logger.error("Discovery failed: \(error)")
            }
            // Keep existing list; UI can still show what we had
        }
    }

    func selectDatabase(_ name: String) {
        guard name != currentDatabase else { return }
        currentDatabase = name
        logger.info("Selected database: \(name)")
    }

    // MARK: Private

    private static let selectedDatabaseKey = "com.puntlabs.quarry-menubar.selectedDatabase"
    private static let cachedDatabasesKey = "com.puntlabs.quarry-menubar.cachedDatabases"

    private let discovery: DatabaseDiscovery
    private let discoveryTimeout: Duration
    private let userDefaults: UserDefaults
    private let logger = Logger(subsystem: "com.puntlabs.quarry-menubar", category: "DatabaseManager")

    private static func loadCachedDatabases(from defaults: UserDefaults) -> [DatabaseInfo] {
        guard let data = defaults.data(forKey: cachedDatabasesKey) else { return [] }
        return (try? JSONDecoder().decode([DatabaseInfo].self, from: data)) ?? []
    }

    private static func cacheDatabases(_ databases: [DatabaseInfo], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(databases) else { return }
        defaults.set(data, forKey: cachedDatabasesKey)
    }
}
