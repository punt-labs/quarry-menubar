@testable import QuarryMenuBar
import XCTest

/// Remote (`quarry.toml`) resolution for `ConnectionProfileLoader`. Split from
/// `ConnectionProfileLoaderTests` (loopback/serve.token/config.toml) to keep each
/// test type body under the SwiftLint length limit.
final class ConnectionProfileLoaderRemoteTests: XCTestCase {

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

    func testRemoteProxyConfigLoadsProfileAndAuthHeader() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let proxyConfig = temp.appendingPathComponent("quarry.toml")
        let pinnedCA = temp.appendingPathComponent("quarry-ca.crt")
        try "pem".write(to: pinnedCA, atomically: true, encoding: .utf8)
        try """
        [quarry]
        url = "wss://okinos.user.home.lab:8420/mcp"
        ca_cert = "\(pinnedCA.path)"

        [quarry.headers]
        Authorization = "Bearer sk-test"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = makeRemoteLoader(proxyConfig: proxyConfig)

        let profile = try loader.load()

        XCTAssertEqual(profile.mode, .remote)
        XCTAssertEqual(profile.origin, .proxyConfig)
        XCTAssertEqual(profile.baseURL.absoluteString, "https://okinos.user.home.lab:8420")
        XCTAssertEqual(profile.caCertificateURL, pinnedCA)
        XCTAssertEqual(profile.authToken, "sk-test")
        XCTAssertEqual(profile.hostDisplayName, "okinos.user.home.lab")
    }

    func testRemoteProxyConfigDefaultsMissingPortToQuarryPort() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let proxyConfig = temp.appendingPathComponent("quarry.toml")
        let pinnedCA = temp.appendingPathComponent("quarry-ca.crt")
        try "pem".write(to: pinnedCA, atomically: true, encoding: .utf8)
        try """
        [quarry]
        url = "wss://okinos.user.home.lab/mcp"
        ca_cert = "\(pinnedCA.path)"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = makeRemoteLoader(proxyConfig: proxyConfig)

        let profile = try loader.load()

        XCTAssertEqual(profile.baseURL.absoluteString, "https://okinos.user.home.lab:8420")
    }

    func testRemoteProxyConfigRejectsSecureURLWithoutPinnedCA() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let proxyConfig = temp.appendingPathComponent("quarry.toml")
        try """
        [quarry]
        url = "https://remote.example:8420"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = makeRemoteLoader(proxyConfig: proxyConfig)

        XCTAssertThrowsError(try loader.load()) { error in
            guard case let .missingProxyCACertificate(url) = error as? ConnectionProfileLoaderError else {
                XCTFail("Expected missingProxyCACertificate, got \(error)")
                return
            }
            XCTAssertEqual(url, proxyConfig)
        }
    }

    func testRemoteProxyConfigRejectsInsecureRemoteProfile() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let proxyConfig = temp.appendingPathComponent("quarry.toml")
        try """
        [quarry]
        url = "http://remote.example:8420"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = makeRemoteLoader(proxyConfig: proxyConfig)

        XCTAssertThrowsError(try loader.load()) { error in
            guard case let .insecureRemoteProxyURL(url) = error as? ConnectionProfileLoaderError else {
                XCTFail("Expected insecureRemoteProxyURL, got \(error)")
                return
            }
            XCTAssertEqual(url, "http://remote.example:8420")
        }
    }

    func testRemoteProxyConfigKeepsRemoteIPv6LiteralBracketed() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let proxyConfig = temp.appendingPathComponent("quarry.toml")
        let pinnedCA = temp.appendingPathComponent("quarry-ca.crt")
        try "pem".write(to: pinnedCA, atomically: true, encoding: .utf8)
        try """
        [quarry]
        url = "wss://[2001:db8::1]:8420/mcp"
        ca_cert = "\(pinnedCA.path)"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = makeRemoteLoader(proxyConfig: proxyConfig)

        let profile = try loader.load()

        XCTAssertEqual(profile.mode, .remote)
        XCTAssertEqual(profile.baseURL.absoluteString, "https://[2001:db8::1]:8420")
        XCTAssertEqual(profile.hostDisplayName, "2001:db8::1")
    }

    func testRemoteProxyConfigDoesNotRewriteRemoteHost() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let proxyConfig = temp.appendingPathComponent("quarry.toml")
        let pinnedCA = temp.appendingPathComponent("quarry-ca.crt")
        try "pem".write(to: pinnedCA, atomically: true, encoding: .utf8)
        try """
        [quarry]
        url = "wss://quarry.example.com/mcp"
        ca_cert = "\(pinnedCA.path)"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = makeRemoteLoader(proxyConfig: proxyConfig)

        let profile = try loader.load()

        XCTAssertEqual(profile.mode, .remote)
        XCTAssertEqual(profile.baseURL.host, "quarry.example.com")
        XCTAssertEqual(profile.hostDisplayName, "quarry.example.com")
    }

    func testRemoteProxyConfigRejectsUnsupportedAuthorizationHeader() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let proxyConfig = temp.appendingPathComponent("quarry.toml")
        let pinnedCA = temp.appendingPathComponent("quarry-ca.crt")
        try "pem".write(to: pinnedCA, atomically: true, encoding: .utf8)
        try """
        [quarry]
        url = "wss://remote.example:8420/mcp"
        ca_cert = "\(pinnedCA.path)"

        [quarry.headers]
        Authorization = "Basic abc123"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = makeRemoteLoader(proxyConfig: proxyConfig)

        XCTAssertThrowsError(try loader.load()) { error in
            guard case .invalidAuthorizationHeader = error as? ConnectionProfileLoaderError else {
                XCTFail("Expected invalidAuthorizationHeader, got \(error)")
                return
            }
        }
    }

    // MARK: Private

    private var tempDirectory: URL?

    /// A loader whose loopback paths point at nonexistent temp dirs, so a remote
    /// `quarry.toml` test never accidentally reads the real home run dir.
    private func makeRemoteLoader(proxyConfig: URL) -> ConnectionProfileLoader {
        let temp = tempDirectory ?? FileManager.default.temporaryDirectory
        return ConnectionProfileLoader(
            proxyConfigURL: proxyConfig,
            localCAURL: temp.appendingPathComponent("unused-local-ca.crt"),
            dataRootURL: temp.appendingPathComponent("unused-data"),
            quarryConfigURL: temp.appendingPathComponent("unused-config.toml")
        )
    }
}
