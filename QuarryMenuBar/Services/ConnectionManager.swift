import Foundation
import Observation

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
        databases.first?.name ?? databaseName(from: status?.databasePath)
    }

    var allowsLocalFileAccess: Bool {
        profile?.allowsLocalFileAccess ?? false
    }

    func refresh() async {
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

    // MARK: Private

    private let profileLoader: any ConnectionProfileLoading
    private let clientFactory: (ConnectionProfile) throws -> QuarryClient
    private var refreshGeneration = 0

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
