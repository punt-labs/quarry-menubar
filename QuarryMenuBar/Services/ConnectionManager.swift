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

    var activeDatabaseName: String? {
        databases.first?.name ?? databaseName(from: status?.databasePath)
    }

    var allowsLocalFileAccess: Bool {
        profile?.allowsLocalFileAccess ?? false
    }

    func refresh() async {
        state = .connecting
        status = nil
        databases = []
        searchViewModel = nil

        do {
            let resolvedProfile = try profileLoader.load()
            profile = resolvedProfile

            let client = try clientFactory(resolvedProfile)
            async let healthResponse = client.health()
            async let statusResponse = client.status()
            async let databasesResponse = client.databases()

            _ = try await healthResponse
            status = try await statusResponse
            let resolvedDatabases = try await databasesResponse
            databases = resolvedDatabases.databases
            searchViewModel = SearchViewModel(client: client)
            state = .connected
        } catch let error as ConnectionProfileLoaderError {
            profile = nil
            applyFailure(
                message: error.localizedDescription,
                configurationIssue: true
            )
        } catch let error as QuarryClientError {
            applyFailure(
                message: error.localizedDescription,
                configurationIssue: error.isConfigurationIssue
            )
        } catch {
            applyFailure(
                message: error.localizedDescription,
                configurationIssue: false
            )
        }
    }

    // MARK: Private

    private let profileLoader: any ConnectionProfileLoading
    private let clientFactory: (ConnectionProfile) throws -> QuarryClient

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
