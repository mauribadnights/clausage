import Foundation
import Security

/// Manages OAuth token retrieval with caching to avoid repeated Keychain prompts.
/// First read from Claude Code's keychain item triggers a system prompt (once).
/// After that, the token is cached in our own keychain item (no prompts ever).
enum KeychainService {
    private static let claudeCodeService = "Claude Code-credentials"
    private static let cacheService = "com.mauricio.Clausage.token-cache"
    private static let cacheAccount = "claude-oauth"

    /// Get the OAuth access token, using cache to avoid keychain prompts.
    static func getAccessToken() -> String? {
        // 1. Try our cached copy first (never prompts)
        if let cached = readCachedToken() {
            return cached
        }

        // 2. Fall back to Claude Code's keychain item (may prompt once)
        if let original = readClaudeCodeToken() {
            cacheToken(original)
            return original
        }

        return nil
    }

    /// Force refresh from Claude Code's keychain (on 401)
    static func refreshToken() -> String? {
        deleteCachedToken()
        if let fresh = readClaudeCodeToken() {
            cacheToken(fresh)
            return fresh
        }
        return nil
    }

    // MARK: - Claude Code keychain

    private static func readClaudeCodeToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: claudeCodeService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            return nil
        }

        return token
    }

    // MARK: - Token cache (our own keychain item, no prompts)

    private static func readCachedToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: cacheService,
            kSecAttrAccount as String: cacheAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func cacheToken(_ token: String) {
        deleteCachedToken()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: cacheService,
            kSecAttrAccount as String: cacheAccount,
            kSecValueData as String: token.data(using: .utf8)!
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func deleteCachedToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: cacheService,
            kSecAttrAccount as String: cacheAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
