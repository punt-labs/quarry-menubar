import Foundation
import Observation
import os

@MainActor
@Observable
final class ConnectionManager {

    // MARK: Lifecycle

    init(
        profileLoader: any ConnectionProfileLoading = ConnectionProfileLoader(),
        clientFactory: @escaping (ConnectionProfile) throws -> QuarryClient = {
            try QuarryClient(profile: $0)
        }
    ) {
        self.profileLoader = profileLoader
        self.clientFactory = clientFactory
    }

    // MARK: Internal

    private(set) var state: ConnectionState = .idle
    private(set) var profile: ConnectionProfile?
    private(set) var status: StatusResponse?
    private(set) var databases: [DatabaseSummary] = []
    private(set) var searchViewModel: SearchViewModel?
    private(set) var failureOrigin: ConnectionOrigin?

    var activeDatabaseName: String? {
        databaseName(from: status?.databasePath)
            ?? (databases.count == 1 ? databases.first?.name : nil)
    }

    var allowsLocalFileAccess: Bool {
        profile?.allowsLocalFileAccess ?? false
    }

    /// Start the initial connection if — and only if — the manager is idle and no
    /// connect is already in flight.
    ///
    /// The resulting network work runs in a manager-owned, unstructured `Task`
    /// (`connectTask`) rather than inheriting the caller's task. This is the fix
    /// for the MenuBarExtra(`.window`) lifecycle bug: the panel's `.task` is
    /// cancelled whenever the window is torn down (panel close, first-open
    /// re-render), and if the connect ran *as* that `.task` the in-flight
    /// URLSession request was cancelled mid-await. A cancelled request surfaces as
    /// `CancellationError`, which the app then displayed as "Unavailable". By
    /// spawning an owned top-level task here, panel teardown no longer reaches the
    /// connect. Safe to call from every panel `onAppear`/`.task` and from app
    /// scope; it is idempotent.
    func connectIfNeeded() {
        guard case .idle = state, connectTask == nil else { return }
        connectTask = Task { [weak self] in
            await self?.performRefresh()
            self?.connectTask = nil
        }
    }

    func refresh() async {
        await performRefresh()
    }

    // MARK: Private

    private let profileLoader: any ConnectionProfileLoading
    private let clientFactory: (ConnectionProfile) throws -> QuarryClient
    private let log = Logger(subsystem: "com.puntlabs.quarry-menubar", category: "connection")
    private var refreshGeneration = 0
    private var connectTask: Task<Void, Never>?

    private func performRefresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration

        state = .connecting
        profile = nil
        status = nil
        databases = []
        searchViewModel = nil
        failureOrigin = nil

        do {
            let resolvedProfile = try profileLoader.load()
            guard generation == refreshGeneration else { return }
            profile = resolvedProfile
            failureOrigin = resolvedProfile.origin

            let client = try clientFactory(resolvedProfile)
            async let healthResponse = client.health()
            async let statusResponse = client.status()
            async let databasesResponse = client.databases()

            _ = try await healthResponse
            let resolvedStatus = try await statusResponse
            let resolvedDatabases = try await databasesResponse
            guard generation == refreshGeneration else { return }
            status = resolvedStatus
            databases = resolvedDatabases.databases
            searchViewModel = SearchViewModel(client: client)
            state = .connected
            log.info("Connected to Quarry (\(resolvedProfile.mode.rawValue, privacy: .public)).")
        } catch is CancellationError {
            handleCancellation(generation: generation)
        } catch let error as URLError where error.code == .cancelled {
            handleCancellation(generation: generation)
        } catch let error as ConnectionProfileLoaderError {
            guard generation == refreshGeneration else { return }
            failureOrigin = error.connectionOrigin
            applyFailure(
                message: error.localizedDescription,
                configurationIssue: true
            )
        } catch let error as QuarryClientError {
            guard generation == refreshGeneration else { return }
            applyFailure(
                message: error.localizedDescription,
                configurationIssue: error.isConfigurationIssue
            )
        } catch {
            guard generation == refreshGeneration else { return }
            applyFailure(
                message: error.localizedDescription,
                configurationIssue: false
            )
        }
    }

    /// Handle a cancelled connection attempt without surfacing it as a failure.
    ///
    /// A `CancellationError` (or `URLError.cancelled` raised because the task was
    /// cancelled) means the attempt was abandoned, not that Quarry is unavailable.
    /// Reset to `.idle` — never `.unavailable`/`.misconfigured` — so the next
    /// `connectIfNeeded()` (e.g. the next panel open) starts a fresh attempt rather
    /// than stranding the user on a spurious error. Superseded generations return
    /// without touching state, leaving the newer attempt in control.
    private func handleCancellation(generation: Int) {
        guard generation == refreshGeneration else { return }
        log.debug("Connection attempt cancelled; returning to idle.")
        profile = nil
        failureOrigin = nil
        state = .idle
    }

    private func applyFailure(
        message: String,
        configurationIssue: Bool
    ) {
        status = nil
        databases = []
        searchViewModel = nil
        state = configurationIssue
            ? .misconfigured(message)
            : .unavailable(message)
    }

    private func databaseName(from databasePath: String?) -> String? {
        guard let databasePath else { return nil }
        return URL(fileURLWithPath: databasePath)
            .deletingLastPathComponent()
            .lastPathComponent
    }
}
