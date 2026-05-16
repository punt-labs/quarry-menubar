import Foundation
@testable import QuarryMenuBar
import XCTest

// MARK: - MockURLProtocol

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            let fallbackURL = request.url ?? defaultTestURL
            guard let response = HTTPURLResponse(
                url: fallbackURL,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            ) else {
                preconditionFailure("Failed to create fallback response for \(fallbackURL)")
            }

            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(
                self,
                didLoad: Data(#"{"error":"No request handler set"}"#.utf8)
            )
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Helpers

private let defaultTestURL = URL(string: "http://127.0.0.1:9999") ?? URL(fileURLWithPath: "/")

func mockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

func testProfile(
    baseURL: URL = defaultTestURL,
    mode: ConnectionMode = .local,
    origin: ConnectionOrigin = .localDefault,
    caCertificateURL: URL? = nil,
    authToken: String? = nil,
    hostDisplayName: String = "localhost"
) -> ConnectionProfile {
    ConnectionProfile(
        mode: mode,
        origin: origin,
        baseURL: baseURL,
        caCertificateURL: caCertificateURL,
        authToken: authToken,
        hostDisplayName: hostDisplayName
    )
}

func mockClient(
    profile: ConnectionProfile = testProfile(),
    session: URLSession = mockSession()
) throws -> QuarryClient {
    try QuarryClient(profile: profile, session: session)
}

// MARK: - StubProfileLoader

struct StubProfileLoader: ConnectionProfileLoading {
    let loadBlock: () throws -> ConnectionProfile

    func load() throws -> ConnectionProfile {
        try loadBlock()
    }
}

func jsonResponse(
    _ json: String,
    statusCode: Int = 200,
    url: URL = defaultTestURL
) -> (Data, HTTPURLResponse) {
    let data = Data(json.utf8)
    guard let response = HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    ) else {
        preconditionFailure("Failed to create HTTPURLResponse for \(url)")
    }
    return (data, response)
}
