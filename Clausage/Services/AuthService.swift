import Foundation
import AppKit

/// Top-level OAuth orchestrator. Owns:
/// - The credential file (via `CredentialStore`)
/// - The browser-based Authorization Code + PKCE flow
/// - Token refresh against `https://platform.claude.com/v1/oauth/token`
/// - One-time legacy bootstrap from Claude Code's keychain item
///
/// Replaces the old `KeychainService`. The static surface (`getAccessToken`,
/// `refreshToken`) is preserved so existing call sites in `UsageService` keep working
/// without changes; the new `signInWithBrowser` and observable `state` drive the UI.
@MainActor
@Observable
final class AuthService {
    // MARK: - Shared singleton (for SwiftUI binding)

    static let shared = AuthService()

    // MARK: - Observable state

    enum State: Equatable {
        case unknown
        case signedOut
        case signingIn
        case signedIn(source: StoredCredentials.Source)
        case error(String)

        var isSignedIn: Bool {
            if case .signedIn = self { return true }
            return false
        }
    }

    private(set) var state: State = .unknown

    // Constants live in `AuthConstants` (file-private) so both `@MainActor` instance code
    // and `nonisolated` static helpers can read them without actor-isolation warnings.

    // MARK: - Init / restore

    init() {
        rehydrateState()
    }

    private func rehydrateState() {
        if let cred = CredentialStore.load() {
            state = .signedIn(source: cred.source)
        } else if Self.readClaudeCodeKeychain() != nil {
            // We can bootstrap silently on first token request — surface as signed-out
            // until user takes an action, OR auto-import. We auto-import: it's the
            // smoothest upgrade path for existing users.
            if let imported = bootstrapFromClaudeCodeIfPossible() {
                state = .signedIn(source: imported.source)
            } else {
                state = .signedOut
            }
        } else {
            state = .signedOut
        }
    }

    // MARK: - Public sync API (drop-in for legacy KeychainService callers)

    /// Returns a non-expired access token, refreshing if necessary. Synchronous because
    /// the existing `UsageService` calls this from a non-async context. The refresh round-trip
    /// uses a `DispatchSemaphore` internally.
    ///
    /// `nonisolated` because this is callable from any thread — it only touches `CredentialStore`
    /// (file-based) and performs network I/O; no `@MainActor` instance state is read.
    nonisolated static func getAccessToken() -> String? {
        if let cached = CredentialStore.load() {
            if !isExpiringSoon(cached) {
                return cached.accessToken
            }
            if let refreshed = performTokenRefresh(using: cached.refreshToken) {
                let updated = StoredCredentials(
                    accessToken: refreshed.accessToken,
                    refreshToken: refreshed.refreshToken,
                    expiresAt: refreshed.expiresAt,
                    source: cached.source
                )
                try? CredentialStore.save(updated)
                return refreshed.accessToken
            }
            // Refresh failed but the access token might still be valid — return it.
            if !isExpired(cached) {
                return cached.accessToken
            }
        }

        // No file → try one-time keychain bootstrap from Claude Code
        if let bootstrapped = staticBootstrapFromClaudeCode() {
            return bootstrapped.accessToken
        }
        return nil
    }

    /// Force-refresh. Used by `UsageService` on 401 responses.
    /// `nonisolated` for the same reason as `getAccessToken()`.
    nonisolated static func refreshToken() -> String? {
        if let cached = CredentialStore.load(),
           let refreshed = performTokenRefresh(using: cached.refreshToken) {
            let updated = StoredCredentials(
                accessToken: refreshed.accessToken,
                refreshToken: refreshed.refreshToken,
                expiresAt: refreshed.expiresAt,
                source: cached.source
            )
            try? CredentialStore.save(updated)
            return refreshed.accessToken
        }

        // File-based refresh failed — try keychain bootstrap as a last resort.
        if let bootstrapped = staticBootstrapFromClaudeCode() {
            return bootstrapped.accessToken
        }
        return nil
    }

    // MARK: - Browser sign-in flow

    /// Run the full OAuth Authorization Code + PKCE flow. Opens the system browser,
    /// listens for the redirect, exchanges the code for tokens, persists them.
    /// Throws on failure; updates `state` along the way.
    func signInWithBrowser() async throws {
        state = .signingIn
        do {
            let credentials = try await runBrowserOAuthFlow()
            try CredentialStore.save(credentials)
            state = .signedIn(source: credentials.source)
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }

    func signOut() {
        CredentialStore.delete()
        state = .signedOut
    }

    /// Manual re-import of Claude Code keychain creds. UI exposes this as a fallback.
    @discardableResult
    func bootstrapFromClaudeCodeIfPossible() -> StoredCredentials? {
        guard let creds = Self.staticBootstrapFromClaudeCode() else { return nil }
        state = .signedIn(source: creds.source)
        return creds
    }

    // MARK: - Browser flow internals

    private func runBrowserOAuthFlow() async throws -> StoredCredentials {
        let pkce = PKCE.generate()
        let stateParam = PKCE.randomState()

        let server = try LocalCallbackServer(path: "/callback")
        let redirectURL = try await server.start()

        guard var comps = URLComponents(string: AuthConstants.authorizeEndpoint) else {
            throw AuthError.invalidAuthorizeURL
        }
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: AuthConstants.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString),
            URLQueryItem(name: "scope", value: AuthConstants.scope),
            URLQueryItem(name: "state", value: stateParam),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
        ]
        guard let authURL = comps.url else {
            throw AuthError.invalidAuthorizeURL
        }

        NSWorkspace.shared.open(authURL)

        let params = try await server.waitForCallback()

        if let err = params.value(for: "error") {
            let desc = params.value(for: "error_description") ?? err
            throw AuthError.providerError(desc)
        }
        guard let code = params.value(for: "code") else {
            throw AuthError.missingCode
        }
        guard params.value(for: "state") == stateParam else {
            throw AuthError.stateMismatch
        }

        let token = try await exchangeCodeForTokens(
            code: code,
            verifier: pkce.verifier,
            redirectURL: redirectURL
        )

        return StoredCredentials(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: token.expiresAt,
            source: .browser
        )
    }

    private func exchangeCodeForTokens(
        code: String,
        verifier: String,
        redirectURL: URL
    ) async throws -> OAuthTokenData {
        guard let url = URL(string: AuthConstants.tokenEndpoint) else {
            throw AuthError.invalidTokenURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURL.absoluteString,
            "client_id": AuthConstants.clientID,
            "code_verifier": verifier,
        ]
        request.httpBody = body.formURLEncoded()

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.tokenExchangeFailed("No HTTP response")
        }
        guard http.statusCode == 200 else {
            let bodyText = String(data: data, encoding: .utf8) ?? "<no body>"
            throw AuthError.tokenExchangeFailed("HTTP \(http.statusCode): \(bodyText)")
        }
        guard let parsed = OAuthTokenData(json: data) else {
            throw AuthError.tokenExchangeFailed("Invalid JSON response")
        }
        return parsed
    }

    // MARK: - Static helpers (sync, for legacy callers)

    nonisolated private static func staticBootstrapFromClaudeCode() -> StoredCredentials? {
        guard let raw = readClaudeCodeKeychain() else { return nil }
        let creds = StoredCredentials(
            accessToken: raw.accessToken,
            refreshToken: raw.refreshToken,
            expiresAt: raw.expiresAt,
            source: .claudeCodeImport
        )
        try? CredentialStore.save(creds)
        return creds
    }

    nonisolated private static func readClaudeCodeKeychain() -> OAuthTokenData? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AuthConstants.claudeCodeKeychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String,
              let refreshToken = oauth["refreshToken"] as? String else {
            return nil
        }
        let expiresAt: Date
        if let expiresMs = oauth["expiresAt"] as? Double {
            expiresAt = Date(timeIntervalSince1970: expiresMs / 1000.0)
        } else if let expiresMs = oauth["expiresAt"] as? Int {
            expiresAt = Date(timeIntervalSince1970: Double(expiresMs) / 1000.0)
        } else {
            expiresAt = Date().addingTimeInterval(3600)
        }
        return OAuthTokenData(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )
    }

    nonisolated private static func performTokenRefresh(using refreshToken: String) -> OAuthTokenData? {
        guard let url = URL(string: AuthConstants.tokenEndpoint) else { return nil }

        // Try the modern client_id first, fall back to the legacy UUID for tokens that
        // were issued against the old client (e.g. Claude Code keychain imports).
        for clientID in [AuthConstants.clientID, AuthConstants.legacyClientID] {
            if let token = synchronousRefresh(url: url, refreshToken: refreshToken, clientID: clientID) {
                return token
            }
        }
        return nil
    }

    nonisolated private static func synchronousRefresh(url: URL, refreshToken: String, clientID: String) -> OAuthTokenData? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]
        request.httpBody = body.formURLEncoded()

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var status: Int?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            responseData = data
            status = (response as? HTTPURLResponse)?.statusCode
            semaphore.signal()
        }.resume()
        // 12-second cap to avoid blocking the UI in pathological cases.
        _ = semaphore.wait(timeout: .now() + 12)

        guard status == 200, let data = responseData else { return nil }
        return OAuthTokenData(
            json: data,
            fallbackRefreshToken: refreshToken
        )
    }

    nonisolated private static func isExpiringSoon(_ token: StoredCredentials) -> Bool {
        token.expiresAt.timeIntervalSinceNow < AuthConstants.refreshMarginSeconds
    }

    nonisolated private static func isExpired(_ token: StoredCredentials) -> Bool {
        token.expiresAt.timeIntervalSinceNow <= 0
    }
}

// MARK: - Constants

private enum AuthConstants {
    /// `claude.com/cai/oauth/authorize` 307-redirects here; we bypass the hop.
    static let authorizeEndpoint = "https://claude.ai/oauth/authorize"
    static let tokenEndpoint     = "https://platform.claude.com/v1/oauth/token"
    /// Public client metadata URL — used as `client_id` per Anthropic's dynamic-registration
    /// scheme for the Claude Code OAuth client. The Authorization Code flow expects this URL.
    static let clientID          = "https://claude.ai/oauth/claude-code-client-metadata"
    /// Legacy client_id used by Claude Code; kept as a fallback for refresh-token grants
    /// imported from a Claude Code keychain bootstrap (those tokens were issued against this
    /// client and the modern metadata client_id may reject them).
    static let legacyClientID    = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let scope             = "openid user:inference user:profile"
    static let claudeCodeKeychainService = "Claude Code-credentials"
    /// Refresh `refreshMarginSeconds` before expiry.
    static let refreshMarginSeconds: TimeInterval = 300
}

// MARK: - Errors

enum AuthError: Error, LocalizedError {
    case invalidAuthorizeURL
    case invalidTokenURL
    case missingCode
    case stateMismatch
    case providerError(String)
    case tokenExchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAuthorizeURL:        return "Internal error: malformed authorize URL."
        case .invalidTokenURL:            return "Internal error: malformed token URL."
        case .missingCode:                return "The browser callback did not include an authorization code."
        case .stateMismatch:              return "The OAuth state value did not match. Try signing in again."
        case .providerError(let msg):     return "Anthropic returned an error: \(msg)"
        case .tokenExchangeFailed(let m): return "Could not exchange code for tokens: \(m)"
        }
    }
}

// MARK: - Token DTO

struct OAuthTokenData {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// Decode `{access_token, refresh_token, expires_in}` payload.
    init?(json data: Data, fallbackRefreshToken: String? = nil) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            return nil
        }
        let refreshToken = (json["refresh_token"] as? String) ?? fallbackRefreshToken
        guard let refresh = refreshToken else { return nil }

        let expiresIn = (json["expires_in"] as? Int) ?? 3600
        self.accessToken = accessToken
        self.refreshToken = refresh
        self.expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
    }
}

// MARK: - Form encoding

private extension Dictionary where Key == String, Value == String {
    func formURLEncoded() -> Data? {
        let allowed = CharacterSet.urlQueryAllowed
            .subtracting(CharacterSet(charactersIn: "&=+"))
        let pairs = self.map { key, value -> String in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        return pairs.joined(separator: "&").data(using: .utf8)
    }
}
