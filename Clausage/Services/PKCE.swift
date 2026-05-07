import Foundation
import CryptoKit

/// Proof Key for Code Exchange (PKCE) — RFC 7636.
///
/// Generates a cryptographically random `code_verifier` and the matching
/// SHA-256 `code_challenge` used in the OAuth Authorization Code flow.
/// Required for public OAuth clients (apps that can't keep a client_secret).
enum PKCE {
    /// Single-use challenge pair. The verifier is sent at token-exchange time;
    /// the challenge accompanies the initial authorize redirect.
    struct Challenge: Equatable {
        let verifier: String
        let challenge: String
        let method: String  // always "S256"
    }

    /// Generate a fresh PKCE challenge.
    /// - 64-byte random base, base64url-encoded → 86-char verifier (well within RFC's 43–128 range).
    /// - SHA-256 of the verifier ASCII bytes, base64url-encoded → challenge.
    static func generate() -> Challenge {
        let verifier = randomURLSafeString(byteCount: 64)
        let challenge = sha256Base64URL(verifier)
        return Challenge(verifier: verifier, challenge: challenge, method: "S256")
    }

    /// Generate an opaque URL-safe random string for use as `state` in the OAuth flow
    /// (binds the redirect to this specific authorize request).
    static func randomState(byteCount: Int = 32) -> String {
        randomURLSafeString(byteCount: byteCount)
    }

    // MARK: - Internal

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return Data(bytes).base64URLEncodedString()
    }

    private static func sha256Base64URL(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

// MARK: - Base64URL

extension Data {
    /// RFC 4648 Section 5 — base64url encoding, no padding.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
