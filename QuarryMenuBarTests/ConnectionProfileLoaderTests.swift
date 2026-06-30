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
        XCTAssertEqual(profile.baseURL.absoluteString, "https://127.0.0.1:8420")
        XCTAssertEqual(profile.caCertificateURL, localCA)
        XCTAssertNil(profile.authToken)
        // The app dials 127.0.0.1 but still presents the host as "localhost" for the user.
        XCTAssertEqual(profile.hostDisplayName, "localhost")
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
        XCTAssertEqual(profile.baseURL.absoluteString, "https://127.0.0.1:8420")
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
            guard case let .missingProxyCACertificate(url) = error as? ConnectionProfileLoaderError else {
                XCTFail("Expected missingProxyCACertificate, got \(error)")
                return
            }
            XCTAssertEqual(url, proxyConfig)
        }
    }

    func testProxyConfigRejectsInsecureRemoteProfile() throws {
        let tempDirectory = try XCTUnwrap(tempDirectory)
        let proxyConfig = tempDirectory.appendingPathComponent("quarry.toml")
        try """
        [quarry]
        url = "http://remote.example:8420"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: proxyConfig,
            localCAURL: tempDirectory.appendingPathComponent("unused-local-ca.crt")
        )

        XCTAssertThrowsError(try loader.load()) { error in
            guard case let .insecureRemoteProxyURL(url) = error as? ConnectionProfileLoaderError else {
                XCTFail("Expected insecureRemoteProxyURL, got \(error)")
                return
            }
            XCTAssertEqual(url, "http://remote.example:8420")
        }
    }

    func testProxyConfigAllowsInsecureLoopbackProfile() throws {
        let tempDirectory = try XCTUnwrap(tempDirectory)
        let proxyConfig = tempDirectory.appendingPathComponent("quarry.toml")
        try """
        [quarry]
        url = "ws://127.0.0.1:8420/mcp"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: proxyConfig,
            localCAURL: tempDirectory.appendingPathComponent("unused-local-ca.crt")
        )

        let profile = try loader.load()

        XCTAssertEqual(profile.mode, .local)
        XCTAssertEqual(profile.baseURL.absoluteString, "http://127.0.0.1:8420")
        XCTAssertNil(profile.caCertificateURL)
    }

    func testProxyConfigNormalizesSecureLocalhostToIPv4() throws {
        let tempDirectory = try XCTUnwrap(tempDirectory)
        let proxyConfig = tempDirectory.appendingPathComponent("quarry.toml")
        let pinnedCA = tempDirectory.appendingPathComponent("quarry-ca.crt")
        try "pem".write(to: pinnedCA, atomically: true, encoding: .utf8)
        try """
        [quarry]
        url = "wss://localhost:8420/mcp"
        ca_cert = "\(pinnedCA.path)"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: proxyConfig,
            localCAURL: tempDirectory.appendingPathComponent("unused-local-ca.crt")
        )

        let profile = try loader.load()

        XCTAssertEqual(profile.mode, .local)
        XCTAssertEqual(profile.origin, .proxyConfig)
        XCTAssertEqual(profile.baseURL.scheme, "https")
        XCTAssertEqual(profile.baseURL.host, "127.0.0.1")
        XCTAssertEqual(profile.baseURL.port, 8420)
        XCTAssertEqual(profile.baseURL.absoluteString, "https://127.0.0.1:8420")
        XCTAssertEqual(profile.hostDisplayName, "localhost")
    }

    func testProxyConfigNormalizesInsecureLocalhostToIPv4() throws {
        let tempDirectory = try XCTUnwrap(tempDirectory)
        let proxyConfig = tempDirectory.appendingPathComponent("quarry.toml")
        try """
        [quarry]
        url = "ws://localhost:8420/mcp"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: proxyConfig,
            localCAURL: tempDirectory.appendingPathComponent("unused-local-ca.crt")
        )

        let profile = try loader.load()

        XCTAssertEqual(profile.mode, .local)
        XCTAssertEqual(profile.baseURL.scheme, "http")
        XCTAssertEqual(profile.baseURL.host, "127.0.0.1")
        XCTAssertEqual(profile.baseURL.port, 8420)
        XCTAssertEqual(profile.baseURL.absoluteString, "http://127.0.0.1:8420")
        XCTAssertEqual(profile.hostDisplayName, "localhost")
    }

    func testProxyConfigNormalizesIPv6LoopbackToIPv4() throws {
        let tempDirectory = try XCTUnwrap(tempDirectory)
        let proxyConfig = tempDirectory.appendingPathComponent("quarry.toml")
        let pinnedCA = tempDirectory.appendingPathComponent("quarry-ca.crt")
        try "pem".write(to: pinnedCA, atomically: true, encoding: .utf8)
        try """
        [quarry]
        url = "wss://[::1]:8420/mcp"
        ca_cert = "\(pinnedCA.path)"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: proxyConfig,
            localCAURL: tempDirectory.appendingPathComponent("unused-local-ca.crt")
        )

        let profile = try loader.load()

        XCTAssertEqual(profile.mode, .local)
        XCTAssertEqual(profile.baseURL.host, "127.0.0.1")
        XCTAssertEqual(profile.baseURL.absoluteString, "https://127.0.0.1:8420")
        XCTAssertEqual(profile.hostDisplayName, "::1")
    }

    func testProxyConfigNormalizesUppercaseLocalhostToIPv4() throws {
        let tempDirectory = try XCTUnwrap(tempDirectory)
        let proxyConfig = tempDirectory.appendingPathComponent("quarry.toml")
        let pinnedCA = tempDirectory.appendingPathComponent("quarry-ca.crt")
        try "pem".write(to: pinnedCA, atomically: true, encoding: .utf8)
        try """
        [quarry]
        url = "wss://LOCALHOST:8420/mcp"
        ca_cert = "\(pinnedCA.path)"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: proxyConfig,
            localCAURL: tempDirectory.appendingPathComponent("unused-local-ca.crt")
        )

        let profile = try loader.load()

        XCTAssertEqual(profile.mode, .local)
        XCTAssertEqual(profile.baseURL.host, "127.0.0.1")
        XCTAssertEqual(profile.baseURL.absoluteString, "https://127.0.0.1:8420")
        XCTAssertEqual(profile.hostDisplayName, "LOCALHOST")
    }

    func testProxyConfigNormalizesLocalhostHostButKeepsNonDefaultPort() throws {
        let tempDirectory = try XCTUnwrap(tempDirectory)
        let proxyConfig = tempDirectory.appendingPathComponent("quarry.toml")
        let pinnedCA = tempDirectory.appendingPathComponent("quarry-ca.crt")
        try "pem".write(to: pinnedCA, atomically: true, encoding: .utf8)
        try """
        [quarry]
        url = "wss://localhost:9000/mcp"
        ca_cert = "\(pinnedCA.path)"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: proxyConfig,
            localCAURL: tempDirectory.appendingPathComponent("unused-local-ca.crt")
        )

        let profile = try loader.load()

        XCTAssertEqual(profile.mode, .local)
        XCTAssertEqual(profile.baseURL.host, "127.0.0.1")
        XCTAssertEqual(profile.baseURL.port, 9000)
        XCTAssertEqual(profile.baseURL.absoluteString, "https://127.0.0.1:9000")
    }

    func testProxyConfigKeepsRemoteIPv6LiteralBracketed() throws {
        let tempDirectory = try XCTUnwrap(tempDirectory)
        let proxyConfig = tempDirectory.appendingPathComponent("quarry.toml")
        let pinnedCA = tempDirectory.appendingPathComponent("quarry-ca.crt")
        try "pem".write(to: pinnedCA, atomically: true, encoding: .utf8)
        try """
        [quarry]
        url = "wss://[2001:db8::1]:8420/mcp"
        ca_cert = "\(pinnedCA.path)"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: proxyConfig,
            localCAURL: tempDirectory.appendingPathComponent("unused-local-ca.crt")
        )

        let profile = try loader.load()

        XCTAssertEqual(profile.mode, .remote)
        XCTAssertEqual(profile.baseURL.absoluteString, "https://[2001:db8::1]:8420")
        XCTAssertEqual(profile.hostDisplayName, "2001:db8::1")
    }

    func testProxyConfigDoesNotRewriteRemoteHost() throws {
        let tempDirectory = try XCTUnwrap(tempDirectory)
        let proxyConfig = tempDirectory.appendingPathComponent("quarry.toml")
        let pinnedCA = tempDirectory.appendingPathComponent("quarry-ca.crt")
        try "pem".write(to: pinnedCA, atomically: true, encoding: .utf8)
        try """
        [quarry]
        url = "wss://quarry.example.com/mcp"
        ca_cert = "\(pinnedCA.path)"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: proxyConfig,
            localCAURL: tempDirectory.appendingPathComponent("unused-local-ca.crt")
        )

        let profile = try loader.load()

        XCTAssertEqual(profile.mode, .remote)
        XCTAssertEqual(profile.baseURL.host, "quarry.example.com")
        XCTAssertEqual(profile.hostDisplayName, "quarry.example.com")
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
