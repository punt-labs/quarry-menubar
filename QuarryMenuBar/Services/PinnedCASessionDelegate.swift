import Foundation
import Security

final class PinnedCASessionDelegate: NSObject, URLSessionDelegate {

    // MARK: Lifecycle

    init(certificateData: Data) {
        self.certificateData = certificateData
    }

    // MARK: Internal

    func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              let pinnedCertificate = SecCertificateCreateWithData(nil, certificateData as CFData)
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        SecTrustSetAnchorCertificates(serverTrust, [pinnedCertificate] as CFArray)
        SecTrustSetAnchorCertificatesOnly(serverTrust, true)

        var error: CFError?
        if SecTrustEvaluateWithError(serverTrust, &error) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    // MARK: Private

    private let certificateData: Data
}
