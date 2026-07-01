@testable import QuarryMenuBar
import Security
import XCTest

final class PinnedCASessionDelegateTests: XCTestCase {

    // MARK: Internal

    func testAllowsServerAuthenticationWhenExtendedKeyUsageIsAbsent() {
        XCTAssertTrue(PinnedCASessionDelegate.allowsServerAuthentication(extendedKeyUsageValue: nil))
    }

    func testAllowsServerAuthenticationWhenOIDDataMatchesServerAuth() {
        XCTAssertTrue(
            PinnedCASessionDelegate.allowsServerAuthentication(
                extendedKeyUsageValue: [Data([0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01])]
            )
        )
    }

    func testAllowsServerAuthenticationWhenSecurityReturnsPropertyDictionaries() {
        let extendedKeyUsageValue: [Any] = [[
            kSecPropertyKeyValue as String: "TLS Web Server Authentication"
        ]]

        XCTAssertTrue(
            PinnedCASessionDelegate.allowsServerAuthentication(
                extendedKeyUsageValue: extendedKeyUsageValue
            )
        )
    }

    func testRejectsCertificatesWhenParsedExtendedKeyUsageExcludesServerAuth() {
        XCTAssertFalse(
            PinnedCASessionDelegate.allowsServerAuthentication(
                extendedKeyUsageValue: [Data([0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x02])]
            )
        )
    }

    // The loopback-normalization fix dials 127.0.0.1; it is only safe because the local Quarry
    // cert carries `IP Address:127.0.0.1` in its SAN. These two tests pin that contract.

    func testHostMatchesCertificateWhenSANContainsIPAddress() throws {
        let delegate = try PinnedCASessionDelegate(certificateData: Self.decode(Self.ipSANCertificateBase64DER))
        let leaf = try Self.certificate(from: Self.ipSANCertificateBase64DER)

        XCTAssertTrue(delegate.hostMatchesCertificate("127.0.0.1", certificate: leaf))
    }

    func testHostDoesNotMatchCertificateWhenSANIsDNSOnly() throws {
        let delegate = try PinnedCASessionDelegate(certificateData: Self.decode(Self.dnsSANCertificateBase64DER))
        let leaf = try Self.certificate(from: Self.dnsSANCertificateBase64DER)

        XCTAssertFalse(delegate.hostMatchesCertificate("127.0.0.1", certificate: leaf))
        // The same cert still matches its actual DNS SAN, proving the negative is about the host.
        XCTAssertTrue(delegate.hostMatchesCertificate("localhost", certificate: leaf))
    }

    // MARK: Private

    /// Self-signed test certificates (DER, base64). Generated with:
    ///   openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=quarry-test-ip" \
    ///     -addext "subjectAltName=IP:127.0.0.1"
    ///   openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=quarry-test-dns" \
    ///     -addext "subjectAltName=DNS:localhost"
    private static let ipSANCertificateBase64DER = """
    MIIDJDCCAgygAwIBAgIUDW7CHIdw9roYoWTsJENXrixeXmQwDQYJKoZIhvcNAQELBQAwGTEXMBUGA1UEAwwOcXVhcnJ5LXRlc3QtaXAwHhcNMjYwNjMwMjMxNDQyWhcNMzYwNjI3MjMxNDQyWjAZMRcwFQYDVQQDDA5xdWFycnktdGVzdC1pcDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALUL241FZ9jNNfcUf6u1ez+bO9eISGwksmZZTTYHgYor6CJ707bvmGS/5nM8LCmKvuVwSjjW0+71Id/KhPpLXJ3scXlNJHGwrn+T6KlCFg4EGefSYwPvTbGr1M0WKcTGZL2nE3shzdNv+1CsTLYCiii9itpXAQcxH1UD3Q4JD4FXcBmdOxZWVfuD2PcGICYl1WkSBvc/ZKS69J6ZkgbdP+CEAuYevuzrk1iS7PNqFXipYCfg3y1DaS0pNXZwZkThSZvsYqI9RWvjQcU/C83MZWBqiQa4gX1bOlw9fxYLtzLCbBicjQg35F+8ef49GT2/qolzlHo/TYjlN79RaaCui5ECAwEAAaNkMGIwHQYDVR0OBBYEFH3HdlHInpRW22raxhuzCruslqa3MB8GA1UdIwQYMBaAFH3HdlHInpRW22raxhuzCruslqa3MA8GA1UdEwEB/wQFMAMBAf8wDwYDVR0RBAgwBocEfwAAATANBgkqhkiG9w0BAQsFAAOCAQEAnADUwAOB1eF/m9eo2KywecJF1sUBEO+L964V7m0a0HAX5l0kWNNDAZuqOTmFbgJD7u3D5IQuBE1AzUdVj2Cv9k+6wBvsobijCU1uKB0exVXOeWCXSmmMI+gTZ61iVjqlwdcnBAmHoId5n/YcOfdoz8yuF3J4NeAWfNHuGZRecOSqWC90MvG7dccBQn+stoQZEWsY9Svldx5iznUojnlgR2jK97UrZejkluMu/kSll9FAT6FMjpdpwy30UK4nWpKGPUYF5yRoPtA+mLxn5Z9RhdA/qOQR3IJgyBsXYoswMUbMgLiIlsK14G1fOFT5rUUleYDXVstXS7eshfJSOMDrxQ==
    """

    private static let dnsSANCertificateBase64DER = """
    MIIDKzCCAhOgAwIBAgIUbavJhRohBTTMZjVEEapbyjIKFyYwDQYJKoZIhvcNAQELBQAwGjEYMBYGA1UEAwwPcXVhcnJ5LXRlc3QtZG5zMB4XDTI2MDYzMDIzMTQ0NFoXDTM2MDYyNzIzMTQ0NFowGjEYMBYGA1UEAwwPcXVhcnJ5LXRlc3QtZG5zMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnfAhTGLdFbkUQv/05HPXgftco53+QGJWdj+ESP3ku+KRX/LEw5GJsV1YmhcNCeKXpd0RaFXptBfv+EYvjgcm9LdRpMrLgKNVk9yHlf/dT6tk8JqwxDdlvG6FK2eVRhEuyCzGblhaXmC4fxRQLN83+/zn2hE/7LsZKDNLzSNV/LaofvjhkkNzhGzIWCqyMr0vTBC6U6tRhEk4ua8vrMS+is+ugG/tM2iCbM+psmdDi1v5wGaziShchw7WpcfQoC5oli3Kmjd8zCrjXLxi5D1+JszAVPrJOZ84lD/0Dy5AWBcdjcAxMnuMSOgYb2TevgeKuSU4RLI98I5efsUgIfPEoQIDAQABo2kwZzAdBgNVHQ4EFgQUdkhlLjvoSTNZM4j0z+UNX5bBg4QwHwYDVR0jBBgwFoAUdkhlLjvoSTNZM4j0z+UNX5bBg4QwDwYDVR0TAQH/BAUwAwEB/zAUBgNVHREEDTALgglsb2NhbGhvc3QwDQYJKoZIhvcNAQELBQADggEBAEJ0RM1g9kCpf2z5++Wh/dhR/MuFVOIvKPrVQRL/vuZE3iBN9yjX7CjV0OlNRWc9Vj0zVlqgeqVjgWdRCoFcmUUz6HoDz3jv2B+1buyQ0srAcxMPhznaDiYponykGE8IkqSd5rFnDPKxcHud2+5X/Il6RV0PtNiGcaAjeVNQqwnix6OC00dI/TJgJ1w4sO1/cce4PDkQuPZmd55P534iuYmsbHU6Nd2tTshDXbaPXPpGQMHwZRwof9KnwfuTWW1o3TNVedId9fZ3DbcsEy+x//dDAEMEw8KOpqU3gIYr13hsdWonCiN5KXLTwcdKMy/KDYlhN600ClW8KCHQkYwK1bE=
    """

    private static func decode(_ base64DER: String) throws -> Data {
        try XCTUnwrap(Data(base64Encoded: base64DER.replacingOccurrences(of: "\n", with: "")))
    }

    private static func certificate(from base64DER: String) throws -> SecCertificate {
        let data = try decode(base64DER)
        return try XCTUnwrap(SecCertificateCreateWithData(nil, data as CFData))
    }
}
