@testable import QuarryMenuBar
import Security
import XCTest

final class PinnedCASessionDelegateTests: XCTestCase {
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
}
