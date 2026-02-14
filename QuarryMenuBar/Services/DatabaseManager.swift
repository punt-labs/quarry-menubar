import Foundation
import os

// MARK: - DatabaseInfo

struct DatabaseInfo: Sendable, Identifiable, Equatable {

    let name: String
    let documentCount: Int
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

/// Runs `quarry databases` and parses the human-readable output.
///
/// Output format: `name: N documents, X.X MB` (one line per database).
struct CLIDatabaseDiscovery: DatabaseDiscovery {

    // MARK: Lifecycle

    init(
        executablePath: String = "/usr/bin/env",
        processArguments: [String]? = nil
    ) {
        self.executablePath = executablePath
        self.processArguments = processArguments ?? ["quarry", "databases"]
    }

    // MARK: Internal

    /// Parse lines matching `name: N documents, size`.
    static func parse(_ output: String) -> [DatabaseInfo] {
        output.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }

            // Format: "name: N documents, X.X MB"
            guard let colonIndex = trimmed.firstIndex(of: ":") else { return nil }
            let name = String(trimmed[trimmed.startIndex ..< colonIndex])
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }

            let rest = String(trimmed[trimmed.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)

            // Extract document count
            var documentCount = 0
            if let docsRange = rest.range(of: #"(\d+) documents?"#, options: .regularExpression) {
                let digits = rest[docsRange].split(separator: " ").first ?? ""
                documentCount = Int(digits) ?? 0
            }

            // Extract size description (everything after the comma)
            var sizeDescription = ""
            if let commaIndex = rest.firstIndex(of: ",") {
                sizeDescription = String(rest[rest.index(after: commaIndex)...])
                    .trimmingCharacters(in: .whitespaces)
            }

            return DatabaseInfo(name: name, documentCount: documentCount, sizeDescription: sizeDescription)
        }
    }

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
        let output = String(data: data, encoding: .utf8) ?? ""
        return Self.parse(output)
    }

    // MARK: Private

    private let executablePath: String
    private let processArguments: [String]
}

// MARK: - DatabaseManagerError

enum DatabaseManagerError: LocalizedError {
    case discoveryFailed(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .discoveryFailed(message):
            "Database discovery failed: \(message)"
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
        userDefaults: UserDefaults = .standard
    ) {
        self.discovery = discovery
        self.userDefaults = userDefaults
        currentDatabase = userDefaults.string(forKey: Self.selectedDatabaseKey) ?? "default"
    }

    // MARK: Internal

    private(set) var availableDatabases: [DatabaseInfo] = []
    private(set) var isDiscovering = false

    private(set) var currentDatabase: String {
        didSet {
            userDefaults.set(currentDatabase, forKey: Self.selectedDatabaseKey)
        }
    }

    func loadDatabases() async {
        isDiscovering = true
        defer { isDiscovering = false }

        do {
            let discovered = try await discovery.discoverDatabases()
            availableDatabases = discovered
            logger.info("Discovered \(discovered.count) databases")
        } catch {
            logger.error("Discovery failed: \(error)")
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

    private let discovery: DatabaseDiscovery
    private let userDefaults: UserDefaults
    private let logger = Logger(subsystem: "com.puntlabs.quarry-menubar", category: "DatabaseManager")
}
