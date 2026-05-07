import Foundation

/// Reads OpenAI Codex CLI credentials from `~/.codex/auth.json`.
///
/// Clausage does NOT manage the Codex OAuth flow itself — Codex CLI owns the file
/// and refreshes its tokens on its own ~10-day cycle. We just read what's there.
/// If the file is missing or the access_token has expired, we surface a clear
/// "run `codex login`" message and let the user fix it externally.
///
/// Schema (verified 2026-05-07):
/// ```json
/// {
///   "auth_mode": "chatgpt",
///   "OPENAI_API_KEY": null,
///   "tokens": {
///     "id_token": "<JWT>",
///     "access_token": "<JWT>",
///     "refresh_token": "<opaque>",
///     "account_id": "<UUID>"
///   },
///   "last_refresh": "<ISO datetime>"
/// }
/// ```
enum CodexAuthService {
    struct Credentials: Equatable {
        let accessToken: String
        let accountId: String
        let planType: String?       // pulled from id_token claims when available
        let lastRefresh: Date?
    }

    enum CodexAuthError: Error, LocalizedError, Equatable {
        case fileMissing
        case fileUnreadable
        case malformedFile
        case missingTokens
        case tokenExpired

        var errorDescription: String? {
            switch self {
            case .fileMissing:    return "No Codex credentials found. Run `codex login` in a terminal first."
            case .fileUnreadable: return "Could not read ~/.codex/auth.json (permission denied?)."
            case .malformedFile:  return "~/.codex/auth.json has an unexpected shape — Codex CLI may have changed its format."
            case .missingTokens:  return "~/.codex/auth.json is missing access_token or account_id."
            case .tokenExpired:   return "Your Codex token has expired. Run `codex login` to refresh it."
            }
        }
    }

    /// Read and validate the Codex credentials file.
    static func load() -> Result<Credentials, CodexAuthError> {
        let path = NSHomeDirectory() + "/.codex/auth.json"
        guard FileManager.default.fileExists(atPath: path) else {
            return .failure(.fileMissing)
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return .failure(.fileUnreadable)
        }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.malformedFile)
        }
        guard let tokens = raw["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              let accountId = tokens["account_id"] as? String,
              !accessToken.isEmpty, !accountId.isEmpty else {
            return .failure(.missingTokens)
        }

        let idToken = tokens["id_token"] as? String
        let planType = idToken.flatMap { extractPlanType(fromIDToken: $0) }
        let lastRefresh = (raw["last_refresh"] as? String).flatMap { iso8601.date(from: $0) }

        if let exp = idToken.flatMap({ extractExp(fromJWT: $0) }), exp < Date() {
            // id_token expiry mirrors access_token expiry closely enough to use as a
            // pre-flight check. If you really only care about access_token expiry,
            // decode that one instead.
            return .failure(.tokenExpired)
        }

        return .success(Credentials(
            accessToken: accessToken,
            accountId: accountId,
            planType: planType,
            lastRefresh: lastRefresh
        ))
    }

    // MARK: - JWT helpers

    /// Decode the `chatgpt_plan_type` claim (`pro`, `prolite`, `plus`, …) from the id_token.
    /// Best-effort: returns nil if the JWT is malformed.
    private static func extractPlanType(fromIDToken token: String) -> String? {
        guard let claims = decodeJWTPayload(token) else { return nil }
        // OpenAI nests their custom claims under the JWT-standard
        // `https://api.openai.com/auth` namespace.
        if let auth = claims["https://api.openai.com/auth"] as? [String: Any],
           let plan = auth["chatgpt_plan_type"] as? String {
            return plan
        }
        return claims["chatgpt_plan_type"] as? String
    }

    private static func extractExp(fromJWT token: String) -> Date? {
        guard let claims = decodeJWTPayload(token),
              let exp = claims["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    private static func decodeJWTPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let payload = String(parts[1])
        guard let data = base64URLDecode(payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var s = string.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Re-pad for standard base64 decoding.
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
