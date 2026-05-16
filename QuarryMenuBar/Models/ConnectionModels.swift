import Foundation

// MARK: - ConnectionMode

enum ConnectionMode: String, Equatable {
    case local
    case remote
}

// MARK: - ConnectionOrigin

enum ConnectionOrigin: String, Equatable {
    case localDefault
    case proxyConfig
}

// MARK: - ConnectionProfile

struct ConnectionProfile: Equatable {

    // MARK: - Test Support

    static let previewLocal = ConnectionProfile(
        mode: .local,
        origin: .localDefault,
        baseURL: URL(string: "http://127.0.0.1:8420") ?? URL(fileURLWithPath: "/"),
        caCertificateURL: nil,
        authToken: nil,
        hostDisplayName: "localhost"
    )

    let mode: ConnectionMode
    let origin: ConnectionOrigin
    let baseURL: URL
    let caCertificateURL: URL?
    let authToken: String?
    let hostDisplayName: String

    var allowsLocalFileAccess: Bool {
        mode == .local
    }

    var displayName: String {
        switch mode {
        case .local:
            "Local"
        case .remote:
            hostDisplayName
        }
    }

    var usesTLS: Bool {
        baseURL.scheme?.lowercased() == "https"
    }

}

// MARK: - ConnectionState

enum ConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case unavailable(String)
    case misconfigured(String)
}
