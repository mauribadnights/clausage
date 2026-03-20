import Foundation
import Security

/// Manages OAuth token retrieval with caching and proactive refresh.
/// Reads from Claude Code's keychain item and caches in our own item.
/// Proactively refreshes tokens before they expire using the OAuth refresh_token grant.
enum KeychainService {
    private static let claudeCodeService = "Claude Code-credentials"
    private static let cacheService = "com.clausage.app.token-cache"
    private static let cacheAccount = "claude-oauth"

    private static let tokenEndpoint = "https://platform.claude.com/v1/oauth/token"
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    /// Refresh 5 minutes before expiry
    private static let refreshMarginSeconds: TimeInterval = 300

    // MARK: - Public API

    /// Get the OAuth access token, refreshing proactively if near expiry.
    static func getAccessToken() -> String? {
        // 1. Try our cached copy first (never prompts)
        if let cached = readCachedOAuth() {
            // If token is still fresh, return it
            if !isExpiringSoon(cached) {
                return cached.accessToken
            }
            // Token is expiring soon — try to refresh it
            if let refreshed = performTokenRefresh(using: cached.refreshToken) {
                cacheOAuth(refreshed)
                return refreshed.accessToken
            }
            // Refresh failed but token might still be valid — use it anyway
            if !isExpired(cached) {
                return cached.accessToken
            }
        }

        // 2. Fall back to Claude Code's keychain item (may prompt once)
        if let original = readClaudeCodeOAuth() {
            if !isExpiringSoon(original) {
                cacheOAuth(original)
                return original.accessToken
            }
            // Token from Claude Code is also expiring — try refresh
            if let refreshed = performTokenRefresh(using: original.refreshToken) {
                cacheOAuth(refreshed)
                return refreshed.accessToken
            }
            // Use it anyway if not fully expired
            cacheOAuth(original)
            return original.accessToken
        }

        return nil
    }

    /// Force refresh: try OAuth refresh first, fall back to re-reading Claude Code's keychain.
    static func refreshToken() -> String? {
        // Try refreshing via OAuth first
        if let cached = readCachedOAuth(),
           let refreshed = performTokenRefresh(using: cached.refreshToken) {
            cacheOAuth(refreshed)
            return refreshed.accessToken
        }

        // Fall back to re-reading from Claude Code (they may have refreshed)
        deleteCachedToken()
        if let fresh = readClaudeCodeOAuth() {
            // Try refreshing this one too
            if let refreshed = performTokenRefresh(using: fresh.refreshToken) {
                cacheOAuth(refreshed)
                return refreshed.accessToken
            }
            cacheOAuth(fresh)
            return fresh.accessToken
        }
        return nil
    }

    // MARK: - OAuth token refresh

    private static func performTokenRefresh(using refreshToken: String) -> OAuthTokenData? {
        guard let url = URL(string: tokenEndpoint) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ]
        request.httpBody = body
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseError: Error?
        var httpStatus: Int?

        URLSession.shared.dataTask(with: request) { data, response, error in
            responseData = data
            responseError = error
            httpStatus = (response as? HTTPURLResponse)?.statusCode
            semaphore.signal()
        }.resume()
        semaphore.wait()

        guard responseError == nil, httpStatus == 200, let data = responseData else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = json["access_token"] as? String else {
            return nil
        }

        let newRefreshToken = json["refresh_token"] as? String ?? refreshToken
        let expiresIn = json["expires_in"] as? Int ?? 86400
        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))

        return OAuthTokenData(
            accessToken: newAccessToken,
            refreshToken: newRefreshToken,
            expiresAt: expiresAt
        )
    }

    // MARK: - Token expiry checks

    private static func isExpiringSoon(_ token: OAuthTokenData) -> Bool {
        token.expiresAt.timeIntervalSinceNow < refreshMarginSeconds
    }

    private static func isExpired(_ token: OAuthTokenData) -> Bool {
        token.expiresAt.timeIntervalSinceNow <= 0
    }

    // MARK: - Claude Code keychain

    private static func readClaudeCodeOAuth() -> OAuthTokenData? {
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

        return parseClaudeCodeCredentials(data)
    }

    private static func parseClaudeCodeCredentials(_ data: Data) -> OAuthTokenData? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String,
              let refreshToken = oauth["refreshToken"] as? String else {
            return nil
        }

        // expiresAt is stored as epoch milliseconds
        let expiresAt: Date
        if let expiresMs = oauth["expiresAt"] as? Double {
            expiresAt = Date(timeIntervalSince1970: expiresMs / 1000.0)
        } else if let expiresMs = oauth["expiresAt"] as? Int {
            expiresAt = Date(timeIntervalSince1970: Double(expiresMs) / 1000.0)
        } else {
            // If no expiry info, assume it expires in 1 hour (conservative)
            expiresAt = Date().addingTimeInterval(3600)
        }

        return OAuthTokenData(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )
    }

    // MARK: - Token cache (our own keychain item, no prompts)

    private static func readCachedOAuth() -> OAuthTokenData? {
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

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["accessToken"] as? String,
              let refreshToken = json["refreshToken"] as? String,
              let expiresAtMs = json["expiresAt"] as? Double else {
            return nil
        }

        return OAuthTokenData(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: expiresAtMs / 1000.0)
        )
    }

    private static func cacheOAuth(_ token: OAuthTokenData) {
        deleteCachedToken()

        let json: [String: Any] = [
            "accessToken": token.accessToken,
            "refreshToken": token.refreshToken,
            "expiresAt": token.expiresAt.timeIntervalSince1970 * 1000.0
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: cacheService,
            kSecAttrAccount as String: cacheAccount,
            kSecValueData as String: data
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

// MARK: - Internal model

struct OAuthTokenData {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}
