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

    // MARK: - Loopback (serve.port + serve.token)

    func testMissingProxyConfigResolvesLoopbackWithServeToken() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let localCA = try writeLocalCA()
        let dataRoot = try writeRunDir(port: "8420", token: "srv-token-abc")

        let loader = ConnectionProfileLoader(
            proxyConfigURL: temp.appendingPathComponent("quarry.toml"),
            localCAURL: localCA,
            dataRootURL: dataRoot,
            quarryConfigURL: temp.appendingPathComponent("config.toml")
        )

        let profile = try loader.load()

        XCTAssertEqual(profile.mode, .local)
        XCTAssertEqual(profile.origin, .localDefault)
        XCTAssertEqual(profile.baseURL.absoluteString, "https://127.0.0.1:8420")
        XCTAssertEqual(profile.caCertificateURL, localCA)
        // The daemon now requires its live serve.token even on loopback (DES-031
        // v2.2 R4); the loader must present it, not a nil bearer.
        XCTAssertEqual(profile.authToken, "srv-token-abc")
        // The app dials 127.0.0.1 but still presents the host as "localhost".
        XCTAssertEqual(profile.hostDisplayName, "localhost")
    }

    func testLoopbackUsesServePortNotHardcodedDefault() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let localCA = try writeLocalCA()
        let dataRoot = try writeRunDir(port: "9137", token: "tok")

        let loader = ConnectionProfileLoader(
            proxyConfigURL: temp.appendingPathComponent("quarry.toml"),
            localCAURL: localCA,
            dataRootURL: dataRoot,
            quarryConfigURL: temp.appendingPathComponent("config.toml")
        )

        let profile = try loader.load()

        XCTAssertEqual(profile.baseURL.absoluteString, "https://127.0.0.1:9137")
    }

    func testMissingServePortThrowsDaemonNotRunning() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let localCA = try writeLocalCA()
        // Run dir exists but no serve.port sidecar (daemon down).
        let dataRoot = temp.appendingPathComponent("data")
        try FileManager.default.createDirectory(
            at: dataRoot.appendingPathComponent("default"),
            withIntermediateDirectories: true
        )

        let loader = ConnectionProfileLoader(
            proxyConfigURL: temp.appendingPathComponent("quarry.toml"),
            localCAURL: localCA,
            dataRootURL: dataRoot,
            quarryConfigURL: temp.appendingPathComponent("config.toml")
        )

        XCTAssertThrowsError(try loader.load()) { error in
            guard case .daemonNotRunning = error as? ConnectionProfileLoaderError else {
                XCTFail("Expected daemonNotRunning, got \(error)")
                return
            }
        }
    }

    func testMissingServeTokenThrowsServeTokenUnreadable() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let localCA = try writeLocalCA()
        let dataRoot = try writeRunDir(port: "8420", token: nil)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: temp.appendingPathComponent("quarry.toml"),
            localCAURL: localCA,
            dataRootURL: dataRoot,
            quarryConfigURL: temp.appendingPathComponent("config.toml")
        )

        XCTAssertThrowsError(try loader.load()) { error in
            guard case .serveTokenUnreadable = error as? ConnectionProfileLoaderError else {
                XCTFail("Expected serveTokenUnreadable, got \(error)")
                return
            }
        }
    }

    func testEmptyServeTokenThrowsServeTokenUnreadable() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let localCA = try writeLocalCA()
        let dataRoot = try writeRunDir(port: "8420", token: "   \n")

        let loader = ConnectionProfileLoader(
            proxyConfigURL: temp.appendingPathComponent("quarry.toml"),
            localCAURL: localCA,
            dataRootURL: dataRoot,
            quarryConfigURL: temp.appendingPathComponent("config.toml")
        )

        XCTAssertThrowsError(try loader.load()) { error in
            guard case .serveTokenUnreadable = error as? ConnectionProfileLoaderError else {
                XCTFail("Expected serveTokenUnreadable, got \(error)")
                return
            }
        }
    }

    func testMissingLocalCAThrowsMissingLocalCACertificate() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let dataRoot = try writeRunDir(port: "8420", token: "tok")

        let loader = ConnectionProfileLoader(
            proxyConfigURL: temp.appendingPathComponent("quarry.toml"),
            localCAURL: temp.appendingPathComponent("missing-ca.crt"),
            dataRootURL: dataRoot,
            quarryConfigURL: temp.appendingPathComponent("config.toml")
        )

        XCTAssertThrowsError(try loader.load()) { error in
            guard case .missingLocalCACertificate = error as? ConnectionProfileLoaderError else {
                XCTFail("Expected missingLocalCACertificate, got \(error)")
                return
            }
        }
    }

    func testActiveDatabaseFromConfigTomlSelectsRunDir() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let localCA = try writeLocalCA()
        // Two run dirs; config.toml points startup at "work".
        _ = try writeRunDir(db: "default", port: "8420", token: "default-token")
        let dataRoot = try writeRunDir(db: "work", port: "8500", token: "work-token")
        let configURL = temp.appendingPathComponent("config.toml")
        try """
        [default]
        database = "work"
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: temp.appendingPathComponent("quarry.toml"),
            localCAURL: localCA,
            dataRootURL: dataRoot,
            quarryConfigURL: configURL
        )

        let profile = try loader.load()

        XCTAssertEqual(profile.baseURL.absoluteString, "https://127.0.0.1:8500")
        XCTAssertEqual(profile.authToken, "work-token")
    }

    func testConfigTomlInlineCommentResolvesDatabase() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let localCA = try writeLocalCA()
        let dataRoot = try writeRunDir(db: "work", port: "8500", token: "work-token")
        let configURL = temp.appendingPathComponent("config.toml")
        try """
        [default]
        database = "work"  # the active project
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: temp.appendingPathComponent("quarry.toml"),
            localCAURL: localCA,
            dataRootURL: dataRoot,
            quarryConfigURL: configURL
        )

        let profile = try loader.load()

        XCTAssertEqual(profile.baseURL.absoluteString, "https://127.0.0.1:8500")
        XCTAssertEqual(profile.authToken, "work-token")
    }

    func testConfigTomlSingleQuotedDatabaseResolves() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let localCA = try writeLocalCA()
        let dataRoot = try writeRunDir(db: "work", port: "8500", token: "work-token")
        let configURL = temp.appendingPathComponent("config.toml")
        try """
        [default]
        database = 'work'
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: temp.appendingPathComponent("quarry.toml"),
            localCAURL: localCA,
            dataRootURL: dataRoot,
            quarryConfigURL: configURL
        )

        let profile = try loader.load()

        XCTAssertEqual(profile.baseURL.absoluteString, "https://127.0.0.1:8500")
        XCTAssertEqual(profile.authToken, "work-token")
    }

    func testConfigTomlEmptyDatabaseFallsBackToDefault() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let localCA = try writeLocalCA()
        let dataRoot = try writeRunDir(db: "default", port: "8420", token: "default-token")
        let configURL = temp.appendingPathComponent("config.toml")
        try """
        [default]
        database = ""
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: temp.appendingPathComponent("quarry.toml"),
            localCAURL: localCA,
            dataRootURL: dataRoot,
            quarryConfigURL: configURL
        )

        let profile = try loader.load()

        XCTAssertEqual(profile.baseURL.absoluteString, "https://127.0.0.1:8420")
        XCTAssertEqual(profile.authToken, "default-token")
    }

    func testConfigTomlUnparseableDatabaseThrowsMalformed() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let localCA = try writeLocalCA()
        let dataRoot = try writeRunDir(port: "8420", token: "tok")
        let configURL = temp.appendingPathComponent("config.toml")
        // Bare, unquoted value — not a well-formed TOML string.
        try """
        [default]
        database = work
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: temp.appendingPathComponent("quarry.toml"),
            localCAURL: localCA,
            dataRootURL: dataRoot,
            quarryConfigURL: configURL
        )

        XCTAssertThrowsError(try loader.load()) { error in
            guard case let .malformedQuarryConfig(url, _) = error as? ConnectionProfileLoaderError else {
                XCTFail("Expected malformedQuarryConfig, got \(error)")
                return
            }
            XCTAssertEqual(url, configURL)
        }
    }

    func testConfigTomlTraversalDatabaseNameThrowsMalformed() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let localCA = try writeLocalCA()
        let dataRoot = try writeRunDir(port: "8420", token: "tok")
        let configURL = temp.appendingPathComponent("config.toml")
        try """
        [default]
        database = "../escape"
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: temp.appendingPathComponent("quarry.toml"),
            localCAURL: localCA,
            dataRootURL: dataRoot,
            quarryConfigURL: configURL
        )

        XCTAssertThrowsError(try loader.load()) { error in
            guard case .malformedQuarryConfig = error as? ConnectionProfileLoaderError else {
                XCTFail("Expected malformedQuarryConfig, got \(error)")
                return
            }
        }
    }

    func testServePortPresentButInvalidThrowsServePortUnreadable() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let localCA = try writeLocalCA()
        // serve.port exists (daemon claims a run dir) but holds garbage.
        let dataRoot = try writeRunDir(port: "not-a-number", token: "tok")

        let loader = ConnectionProfileLoader(
            proxyConfigURL: temp.appendingPathComponent("quarry.toml"),
            localCAURL: localCA,
            dataRootURL: dataRoot,
            quarryConfigURL: temp.appendingPathComponent("config.toml")
        )

        XCTAssertThrowsError(try loader.load()) { error in
            guard case .servePortUnreadable = error as? ConnectionProfileLoaderError else {
                XCTFail("Expected servePortUnreadable, got \(error)")
                return
            }
        }
    }

    // MARK: - quarry.toml fall-through

    func testProxyConfigWithoutQuarrySectionFallsThroughToLoopback() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let localCA = try writeLocalCA()
        let dataRoot = try writeRunDir(port: "8420", token: "tok")
        let proxyConfig = temp.appendingPathComponent("quarry.toml")
        try """
        [other]
        foo = "bar"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: proxyConfig,
            localCAURL: localCA,
            dataRootURL: dataRoot,
            quarryConfigURL: temp.appendingPathComponent("config.toml")
        )

        let profile = try loader.load()

        XCTAssertEqual(profile.mode, .local)
        XCTAssertEqual(profile.origin, .localDefault)
        XCTAssertEqual(profile.authToken, "tok")
    }

    func testLoopbackProxyConfigIsIgnoredInFavorOfServeToken() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let localCA = try writeLocalCA()
        let dataRoot = try writeRunDir(port: "8420", token: "live-serve-token")
        let proxyConfig = temp.appendingPathComponent("quarry.toml")
        // A loopback login carries no usable token; the loader must fall through
        // to the live serve.token, never the (absent) toml credential.
        try """
        [quarry]
        url = "wss://localhost:8420/mcp"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: proxyConfig,
            localCAURL: localCA,
            dataRootURL: dataRoot,
            quarryConfigURL: temp.appendingPathComponent("config.toml")
        )

        let profile = try loader.load()

        XCTAssertEqual(profile.mode, .local)
        XCTAssertEqual(profile.origin, .localDefault)
        XCTAssertEqual(profile.baseURL.absoluteString, "https://127.0.0.1:8420")
        XCTAssertEqual(profile.caCertificateURL, localCA)
        XCTAssertEqual(profile.authToken, "live-serve-token")
    }

    func testIPv6LoopbackProxyConfigFallsThroughToServeToken() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let localCA = try writeLocalCA()
        let dataRoot = try writeRunDir(port: "8420", token: "tok6")
        let proxyConfig = temp.appendingPathComponent("quarry.toml")
        try """
        [quarry]
        url = "wss://[::1]:8420/mcp"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: proxyConfig,
            localCAURL: localCA,
            dataRootURL: dataRoot,
            quarryConfigURL: temp.appendingPathComponent("config.toml")
        )

        let profile = try loader.load()

        XCTAssertEqual(profile.mode, .local)
        XCTAssertEqual(profile.baseURL.absoluteString, "https://127.0.0.1:8420")
        XCTAssertEqual(profile.authToken, "tok6")
    }

    func testProxyConfigWithQuarrySectionButNoURLThrowsMissingProxyURL() throws {
        let temp = try XCTUnwrap(tempDirectory)
        let localCA = try writeLocalCA()
        let dataRoot = try writeRunDir(port: "8420", token: "tok")
        let proxyConfig = temp.appendingPathComponent("quarry.toml")
        try """
        [quarry]
        ca_cert = "/tmp/whatever.crt"
        """.write(to: proxyConfig, atomically: true, encoding: .utf8)

        let loader = ConnectionProfileLoader(
            proxyConfigURL: proxyConfig,
            localCAURL: localCA,
            dataRootURL: dataRoot,
            quarryConfigURL: temp.appendingPathComponent("config.toml")
        )

        XCTAssertThrowsError(try loader.load()) { error in
            guard case let .missingProxyURL(url) = error as? ConnectionProfileLoaderError else {
                XCTFail("Expected missingProxyURL, got \(error)")
                return
            }
            XCTAssertEqual(url, proxyConfig)
        }
    }

    // MARK: Private

    private var tempDirectory: URL?

    /// Write a `ca.crt` into the temp dir and return its URL.
    private func writeLocalCA() throws -> URL {
        let temp = try XCTUnwrap(tempDirectory)
        let localCA = temp.appendingPathComponent("ca.crt")
        try "pem".write(to: localCA, atomically: true, encoding: .utf8)
        return localCA
    }

    /// Create `<dataRoot>/<db>/` with `serve.port` (and optionally `serve.token`),
    /// returning the data root the loader should read.
    @discardableResult
    private func writeRunDir(
        db: String = "default",
        port: String,
        token: String?
    ) throws -> URL {
        let temp = try XCTUnwrap(tempDirectory)
        let dataRoot = temp.appendingPathComponent("data")
        let runDir = dataRoot.appendingPathComponent(db)
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
        try port.write(
            to: runDir.appendingPathComponent("serve.port"),
            atomically: true,
            encoding: .utf8
        )
        if let token {
            try token.write(
                to: runDir.appendingPathComponent("serve.token"),
                atomically: true,
                encoding: .utf8
            )
        }
        return dataRoot
    }
}
