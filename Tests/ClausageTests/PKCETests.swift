import XCTest
import CryptoKit
@testable import Clausage

final class PKCETests: XCTestCase {

    // MARK: - Verifier shape

    func testVerifierLengthMatchesByteCount() {
        // 64 random bytes base64url-encoded with no padding = ceil(64 * 4 / 3) = 86 chars.
        let challenge = PKCE.generate()
        XCTAssertEqual(challenge.verifier.count, 86)
    }

    func testVerifierIsURLSafe() {
        let challenge = PKCE.generate()
        // RFC 7636 / 4648 §5: only A-Z, a-z, 0-9, '-', '_'.
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        for scalar in challenge.verifier.unicodeScalars {
            XCTAssertTrue(allowed.contains(scalar), "Found disallowed char: \(scalar)")
        }
    }

    func testTwoChallengesAreDifferent() {
        let a = PKCE.generate()
        let b = PKCE.generate()
        XCTAssertNotEqual(a.verifier, b.verifier)
        XCTAssertNotEqual(a.challenge, b.challenge)
    }

    // MARK: - Challenge math

    func testChallengeIsSHA256OfVerifier() {
        let challenge = PKCE.generate()
        let expectedDigest = SHA256.hash(data: Data(challenge.verifier.utf8))
        let expected = Data(expectedDigest).base64URLEncodedString()
        XCTAssertEqual(challenge.challenge, expected)
    }

    func testChallengeMethodIsS256() {
        XCTAssertEqual(PKCE.generate().method, "S256")
    }

    // MARK: - State

    func testStateIsURLSafeAndUnique() {
        let s1 = PKCE.randomState()
        let s2 = PKCE.randomState()
        XCTAssertNotEqual(s1, s2)
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        for scalar in s1.unicodeScalars {
            XCTAssertTrue(allowed.contains(scalar))
        }
    }

    // MARK: - base64URL

    func testBase64URLNoPaddingNoPlusNoSlash() {
        let raw = Data([0xFB, 0xEF, 0xFF, 0xFE])
        let encoded = raw.base64URLEncodedString()
        XCTAssertFalse(encoded.contains("="))
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
    }
}
