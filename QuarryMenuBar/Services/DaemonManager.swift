import Foundation
import os

// MARK: - DaemonState

enum DaemonState: Sendable, Equatable {
    case stopped
    case starting
    case running(pid: Int32)
    case error(String)
}

// MARK: - DaemonManager

/// Manages the lifecycle of the `quarry serve` background process.
///
/// Responsibilities:
/// - Spawn `quarry serve` as a child process
/// - Monitor health via `/health` endpoint
/// - Detect when the process exits unexpectedly
/// - Provide clean shutdown
@MainActor
@Observable
final class DaemonManager {

    // MARK: Lifecycle

    init(
        databaseName: String = "default",
        executablePath: String = "/usr/bin/env",
        processArguments: [String]? = nil
    ) {
        self.databaseName = databaseName
        self.executablePath = executablePath
        self.processArguments = processArguments ?? ["quarry", "serve", "--db", databaseName]
    }

    // Process cleanup happens in stop() — callers must call stop()
    // before releasing the DaemonManager. deinit cannot access
    // @MainActor-isolated properties.

    // MARK: Internal

    private(set) var state: DaemonState = .stopped

    func start() {
        guard case .stopped = state else { return }
        state = .starting

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = processArguments
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        proc.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let code = process.terminationStatus
                if case .running = state {
                    state = code == 0
                        ? .stopped
                        : .error("Process exited with code \(code)")
                }
                self.process = nil
            }
        }

        do {
            try proc.run()
            process = proc
            state = .running(pid: proc.processIdentifier)
            logger.info("Started quarry serve (PID \(proc.processIdentifier))")
            scheduleHealthCheck()
        } catch {
            state = .error("Failed to start: \(error.localizedDescription)")
            logger.error("Failed to start quarry serve: \(error)")
        }
    }

    func stop() {
        healthTask?.cancel()
        healthTask = nil
        guard let proc = process, proc.isRunning else {
            state = .stopped
            process = nil
            return
        }
        proc.terminate()
        state = .stopped
        logger.info("Stopped quarry serve")
    }

    func restart() {
        stop()
        // Small delay to let the port file be cleaned up
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            start()
        }
    }

    // MARK: Private

    private let databaseName: String
    private let executablePath: String
    private let processArguments: [String]
    private var process: Process?
    private var healthTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.puntlabs.quarry-menubar", category: "DaemonManager")

    private func scheduleHealthCheck() {
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            // Wait for the server to start listening
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }

            let client = QuarryClient(databaseName: databaseName)
            do {
                _ = try await client.health()
                logger.info("Health check passed")
            } catch {
                logger.warning("Health check failed: \(error)")
            }
        }
    }
}
