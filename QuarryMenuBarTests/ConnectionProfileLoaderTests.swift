@testable import QuarryMenuBar
import XCTest

final class ConnectionProfileLoaderTests: XCTestCase {

    // MARK: Internal

    override func setUpWithError() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        tempDirectory = directory
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
    }

    func testMissingProxyConfigFallsBackToLocalProfile() throws {
        let tempDirectory = try XCTUnwrap(tempDirectory)
        let localCA = tempDirectory.appendingPathComponent("ca.crt")
        try "pem".write(to: localCA, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: tempDirectory.appendingPathComponent("quarry.toml"),
            localCAURL: localCA
        )

        let profile = try loader.load()

        XCTAssertEqual(profile.mode, .local)
        XCTAssertEqual(profile.origin, .localDefault)
        XCTAssertEqual(profile.baseURL.absoluteString, "https://localhost:8420")
        XCTAssertEqual(profile.caCertificateURL, localCA)
        XCTAssertNil(profile.authToken)
    }

    func testProxyConfigLoadsRemoteProfileAndAuthHeader() throws {
        let tempDirectory = try XCTUnwrap(tempDirectory)
        let proxyConfig = tempDirectory.appendingPathComponent("quarry.toml")
        let pinnedCA = tempDirectory.appendingPathComponent("quarry-ca.crt")
        try "pem".write(to: pinnedCA, atomically: true, encoding: .utf8)
        try """
        [quarry]
        url = "wss://okinos.user.home.lab:8420/mcp"
        ca_cert = "\(pinnedCA.path)"

        [quarry.headers]
        Authorization = "Bearer sk-test"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: proxyConfig,
            localCAURL: tempDirectory.appendingPathComponent("unused-local-ca.crt")
        )

        let profile = try loader.load()

        XCTAssertEqual(profile.mode, .remote)
        XCTAssertEqual(profile.origin, .proxyConfig)
        XCTAssertEqual(profile.baseURL.absoluteString, "https://okinos.user.home.lab:8420")
        XCTAssertEqual(profile.caCertificateURL, pinnedCA)
        XCTAssertEqual(profile.authToken, "sk-test")
        XCTAssertEqual(profile.hostDisplayName, "okinos.user.home.lab")
    }

    func testProxyConfigWithoutQuarrySectionFallsBackToLocalProfile() throws {
        let tempDirectory = try XCTUnwrap(tempDirectory)
        let proxyConfig = tempDirectory.appendingPathComponent("quarry.toml")
        let localCA = tempDirectory.appendingPathComponent("ca.crt")
        try "pem".write(to: localCA, atomically: true, encoding: .utf8)
        try """
        [other]
        foo = "bar"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: proxyConfig,
            localCAURL: localCA
        )

        let profile = try loader.load()

        XCTAssertEqual(profile.mode, .local)
        XCTAssertEqual(profile.origin, .localDefault)
        XCTAssertEqual(profile.baseURL.absoluteString, "https://localhost:8420")
    }

    func testProxyConfigDefaultsMissingPortToQuarryPort() throws {
        let tempDirectory = try XCTUnwrap(tempDirectory)
        let proxyConfig = tempDirectory.appendingPathComponent("quarry.toml")
        let pinnedCA = tempDirectory.appendingPathComponent("quarry-ca.crt")
        try "pem".write(to: pinnedCA, atomically: true, encoding: .utf8)
        try """
        [quarry]
        url = "wss://okinos.user.home.lab/mcp"
        ca_cert = "\(pinnedCA.path)"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: proxyConfig,
            localCAURL: tempDirectory.appendingPathComponent("unused-local-ca.crt")
        )

        let profile = try loader.load()

        XCTAssertEqual(profile.baseURL.absoluteString, "https://okinos.user.home.lab:8420")
    }

    func testProxyConfigRejectsSecureURLWithoutPinnedCA() throws {
        let tempDirectory = try XCTUnwrap(tempDirectory)
        let proxyConfig = tempDirectory.appendingPathComponent("quarry.toml")
        try """
        [quarry]
        url = "https://remote.example:8420"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: proxyConfig,
            localCAURL: tempDirectory.appendingPathComponent("unused-local-ca.crt")
        )

        XCTAssertThrowsError(try loader.load()) { error in
            guard case .missingPinnedCACertificate = error as? ConnectionProfileLoaderError else {
                XCTFail("Expected missingPinnedCACertificate, got \(error)")
                return
            }
        }
    }

    func testProxyConfigRejectsUnsupportedAuthorizationHeader() throws {
        let tempDirectory = try XCTUnwrap(tempDirectory)
        let proxyConfig = tempDirectory.appendingPathComponent("quarry.toml")
        try """
        [quarry]
        url = "ws://localhost:8420/mcp"

        [quarry.headers]
        Authorization = "Basic abc123"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: proxyConfig,
            localCAURL: tempDirectory.appendingPathComponent("unused-local-ca.crt")
        )

        XCTAssertThrowsError(try loader.load()) { error in
            guard case .invalidAuthorizationHeader = error as? ConnectionProfileLoaderError else {
                XCTFail("Expected invalidAuthorizationHeader, got \(error)")
                return
            }
        }
    }

    // MARK: Private

    private var tempDirectory: URL?
}
