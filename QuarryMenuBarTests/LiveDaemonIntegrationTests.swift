@testable import QuarryMenuBar
import XCTest

/// End-to-end probe against a running `quarryd`. Exercises the app's *own*
/// resolution (`ConnectionProfileLoader` reading the real `~/.punt-labs` paths)
/// and its real TLS `QuarryClient` — no mocks — proving a live 200 from
/// `/v1/status` and `/v1/search`.
///
/// Skipped unless the marker file `~/.qmb-live-integration` exists, so
/// `make check` stays hermetic (an app-hosted xctest bundle does not inherit
/// the launching shell's environment, so a marker file is the reliable opt-in).
/// Run with:
///
///     touch ~/.qmb-live-integration
///     xcodebuild test -scheme QuarryMenuBar -destination 'platform=macOS' \
///       -only-testing:QuarryMenuBarTests/LiveDaemonIntegrationTests
///     rm ~/.qmb-live-integration
final class LiveDaemonIntegrationTests: XCTestCase {

    func testResolvesLoopbackAndReachesV1Endpoints() async throws {
        let marker = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".qmb-live-integration")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: marker),
            "Create ~/.qmb-live-integration to run the live daemon integration test."
        )

        let loader = ConnectionProfileLoader()
        let profile = try loader.load()
        print(
            "LIVE profile: mode=\(profile.mode.rawValue) "
                + "base=\(profile.baseURL.absoluteString) tls=\(profile.usesTLS) "
                + "tokenPresent=\(profile.authToken != nil) "
                + "ca=\(profile.caCertificateURL?.path ?? "nil")"
        )

        let client = try QuarryClient(profile: profile)

        let health = try await client.health()
        print("LIVE /health -> status=\(health.status)")

        let status = try await client.status()
        print(
            "LIVE /v1/status -> documents=\(status.documentCount) "
                + "collections=\(status.collectionCount) provider=\(status.provider ?? "nil")"
        )

        let databases = try await client.databases()
        print("LIVE /v1/databases -> total=\(databases.totalDatabases)")

        let search = try await client.search(query: "quarry", limit: 3)
        print(
            "LIVE /v1/search -> total=\(search.totalResults) returned=\(search.results.count)"
        )

        XCTAssertFalse(
            profile.authToken?.isEmpty ?? true,
            "Loopback profile must carry the live serve.token bearer."
        )
        XCTAssertGreaterThanOrEqual(status.documentCount, 0)

        if let first = search.results.first {
            let page = try await client.show(
                document: first.documentName,
                page: first.pageNumber,
                collection: first.collection
            )
            print(
                "LIVE /v1/show -> document=\(page.documentName) page=\(page.pageNumber) "
                    + "textChars=\(page.text.count)"
            )
            XCTAssertEqual(page.documentName, first.documentName)
        }
    }
}
