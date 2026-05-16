import Foundation
import Security

final class PinnedCASessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {

    // MARK: Lifecycle

    init(certificateData: Data) throws {
        certificate = try Self.makeCertificate(from: certificateData)
    }

    // MARK: Internal

    static func allowsServerAuthentication(extendedKeyUsageValue: Any?) -> Bool {
        guard let extendedKeyUsageValue else { return true }
        return containsServerAuthentication(in: extendedKeyUsageValue) ?? true
    }

    func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge: challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge: challenge, completionHandler: completionHandler)
    }

    func consumeLastTrustFailureMessage() -> String? {
        trustFailureLock.lock()
        defer {
            lastTrustFailureMessage = nil
            trustFailureLock.unlock()
        }
        return lastTrustFailureMessage
    }

    func clearLastTrustFailureMessage() {
        trustFailureLock.lock()
        lastTrustFailureMessage = nil
        trustFailureLock.unlock()
    }

    // MARK: Private

    private enum CertificateError: Error {
        case invalidFormat
    }

    private static let serverAuthenticationOID = Data([0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01])

    private let certificate: SecCertificate
    private let trustFailureLock = NSLock()
    private var lastTrustFailureMessage: String?

    private static func makeCertificate(from certificateData: Data) throws -> SecCertificate {
        if let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) {
            return certificate
        }

        guard let pemString = String(data: certificateData, encoding: .utf8),
              let derData = pemToDER(pemString),
              let certificate = SecCertificateCreateWithData(nil, derData as CFData)
        else {
            throw CertificateError.invalidFormat
        }

        return certificate
    }

    private static func pemToDER(_ pemString: String) -> Data? {
        var base64Lines: [String] = []
        var collecting = false

        for line in pemString.components(separatedBy: .newlines) {
            if line == "-----BEGIN CERTIFICATE-----" {
                collecting = true
                continue
            }
            if line == "-----END CERTIFICATE-----" {
                break
            }
            if collecting {
                base64Lines.append(line)
            }
        }

        guard !base64Lines.isEmpty else { return nil }
        return Data(base64Encoded: base64Lines.joined())
    }

    private static func containsServerAuthentication(in value: Any) -> Bool? {
        switch value {
        case let data as Data:
            return data == serverAuthenticationOID
        case let string as String:
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "1.3.6.1.5.5.7.3.1"
                || normalized == "tls web server authentication"
                || normalized == "serverauth"
        case let dictionary as [CFString: Any]:
            guard let nestedValue = dictionary[kSecPropertyKeyValue] else { return nil }
            return containsServerAuthentication(in: nestedValue)
        case let dictionary as [String: Any]:
            guard let nestedValue = dictionary[kSecPropertyKeyValue as String] ?? dictionary["value"] else {
                return nil
            }
            return containsServerAuthentication(in: nestedValue)
        case let values as [Any]:
            var sawParsedValue = false
            for entry in values {
                guard let matches = containsServerAuthentication(in: entry) else { continue }
                sawParsedValue = true
                if matches {
                    return true
                }
            }
            return sawParsedValue ? false : nil
        default:
            return nil
        }
    }

    private func handle(
        challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        clearLastTrustFailureMessage()

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let leafCertificate = leafCertificate(from: serverTrust) else {
            recordTrustFailure("Missing Quarry server certificate.")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        SecTrustSetAnchorCertificates(serverTrust, [certificate] as CFArray)
        SecTrustSetAnchorCertificatesOnly(serverTrust, true)
        // Use the pinned CA for chain validation, then restore TLS-specific checks
        // ourselves so private Quarry certs still validate on macOS.
        SecTrustSetPolicies(serverTrust, SecPolicyCreateBasicX509())

        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            recordTrustFailure(error?.localizedDescription ?? "Pinned Quarry CA validation failed.")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard hostMatchesCertificate(challenge.protectionSpace.host, certificate: leafCertificate) else {
            recordTrustFailure(
                "Quarry certificate does not match host \(challenge.protectionSpace.host)."
            )
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard allowsServerAuthentication(for: leafCertificate) else {
            recordTrustFailure("Quarry certificate is not valid for TLS server authentication.")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    private func hostMatchesCertificate(
        _ host: String,
        certificate leafCertificate: SecCertificate
    ) -> Bool {
        let alternativeNames = subjectAlternativeNames(for: leafCertificate)
        if !alternativeNames.isEmpty {
            return alternativeNames.contains { matches(host: host, pattern: $0) }
        }

        guard let commonName = commonName(for: leafCertificate) else {
            return false
        }
        return matches(host: host, pattern: commonName)
    }

    private func subjectAlternativeNames(for certificate: SecCertificate) -> [String] {
        guard let values = SecCertificateCopyValues(
            certificate,
            [kSecOIDSubjectAltName] as CFArray,
            nil
        ) as? [CFString: Any],
            let altNameDictionary = values[kSecOIDSubjectAltName] as? [CFString: Any],
            let entries = altNameDictionary[kSecPropertyKeyValue] as? [[CFString: Any]]
        else {
            return []
        }

        return entries.compactMap { entry in
            guard let label = entry[kSecPropertyKeyLabel] as? String,
                  label == "DNS Name" || label == "IP Address"
            else {
                return nil
            }
            return entry[kSecPropertyKeyValue] as? String
        }
    }

    private func commonName(for certificate: SecCertificate) -> String? {
        guard let values = SecCertificateCopyValues(
            certificate,
            [kSecOIDCommonName] as CFArray,
            nil
        ) as? [CFString: Any],
            let commonNameDictionary = values[kSecOIDCommonName] as? [CFString: Any]
        else {
            return nil
        }

        if let commonName = commonNameDictionary[kSecPropertyKeyValue] as? String {
            return commonName
        }

        let names = commonNameDictionary[kSecPropertyKeyValue] as? [String]
        return names?.first
    }

    private func allowsServerAuthentication(for certificate: SecCertificate) -> Bool {
        guard let values = SecCertificateCopyValues(
            certificate,
            [kSecOIDExtendedKeyUsage] as CFArray,
            nil
        ) as? [CFString: Any],
            let extendedUsageDictionary = values[kSecOIDExtendedKeyUsage] as? [CFString: Any]
        else {
            return true
        }

        return Self.allowsServerAuthentication(
            extendedKeyUsageValue: extendedUsageDictionary[kSecPropertyKeyValue]
        )
    }

    private func leafCertificate(from serverTrust: SecTrust) -> SecCertificate? {
        (SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate])?.first
    }

    private func recordTrustFailure(_ message: String) {
        trustFailureLock.lock()
        lastTrustFailureMessage = message
        trustFailureLock.unlock()
    }

    private func matches(
        host: String,
        pattern: String
    ) -> Bool {
        let normalizedHost = host.lowercased()
        let normalizedPattern = pattern.lowercased()

        guard normalizedPattern.hasPrefix("*.") else {
            return normalizedHost == normalizedPattern
        }

        let suffix = String(normalizedPattern.dropFirst(1))
        guard normalizedHost.hasSuffix(suffix) else {
            return false
        }

        let prefix = normalizedHost.dropLast(suffix.count)
        return !prefix.isEmpty && !prefix.contains(".")
    }

}
