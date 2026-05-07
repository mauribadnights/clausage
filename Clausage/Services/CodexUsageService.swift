import Foundation

/// Polls `https://chatgpt.com/api/codex/usage` for the current ChatGPT/Codex
/// rate-limit windows. Returns `used_percent` for the primary (5-hour) and
/// secondary (weekly) windows, mirroring the shape Anthropic's usage endpoint
/// returns.
///
/// Cloudflare protects this endpoint with TLS-fingerprint and JS challenges.
/// `URLSession` from a native macOS app generally passes (different fingerprint
/// than `curl`), but if it doesn't, the service surfaces the raw HTTP status
/// to the dashboard so the user knows it's blocked rather than silently zeroing.
struct CodexUsageData: Equatable {
    var primaryUsedPercent: Double?
    var primaryWindowSeconds: Int?
    var primaryResetsAt: Date?
    var secondaryUsedPercent: Double?
    var secondaryWindowSeconds: Int?
    var secondaryResetsAt: Date?
    var planType: String?
    var lastUpdated: Date?
    var error: String?
    var isStale: Bool = false
}

@Observable
final class CodexUsageService {
    var usage = CodexUsageData()
    var isLoading = false

    private var refreshTimer: Timer?
    private var consecutiveFailures = 0

    init(autostart: Bool = true) {
        guard autostart else { return }
        startRefreshTimer()
        Task { @MainActor in self.fetch() }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func startRefreshTimer() {
        refreshTimer?.invalidate()
        // Codex usage doesn't change as fast as Claude; 10-min poll is fine.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.fetch() }
        }
    }

    @MainActor
    func fetch() {
        isLoading = true
        Task.detached(priority: .utility) { [weak self] in
            let result = Self.fetchUsage()
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.isLoading = false
                if result.error != nil {
                    self.consecutiveFailures += 1
                    // Keep last successful values; mark stale.
                    var carried = self.usage
                    carried.error = result.error
                    carried.isStale = true
                    self.usage = carried
                } else {
                    self.consecutiveFailures = 0
                    self.usage = result
                }
            }
        }
    }

    // MARK: - Network

    /// Endpoint extracted from the strings table of the codex-rs binary at
    /// `node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/codex/codex`.
    /// Verified live with a real OAuth bearer + account-id header (returns 200 + the
    /// `rate_limit.{primary,secondary}_window.used_percent` shape).
    private static let endpoint = "https://chatgpt.com/backend-api/codex/usage"

    nonisolated private static func fetchUsage() -> CodexUsageData {
        let creds: CodexAuthService.Credentials
        switch CodexAuthService.load() {
        case .success(let c): creds = c
        case .failure(let err):
            return CodexUsageData(error: err.errorDescription)
        }

        guard let url = URL(string: endpoint) else {
            return CodexUsageData(error: "Invalid Codex usage URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(creds.accountId, forHTTPHeaderField: "chatgpt-account-id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Mirror the codex-rs binary's User-Agent so Cloudflare treats us as a
        // recognized client rather than a generic HTTP library.
        request.setValue("codex_cli_rs/0.1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var status: Int?
        var responseError: Error?
        URLSession.shared.dataTask(with: request) { data, response, error in
            responseData = data
            status = (response as? HTTPURLResponse)?.statusCode
            responseError = error
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 12)

        if let error = responseError {
            return CodexUsageData(planType: creds.planType, error: error.localizedDescription)
        }

        switch status {
        case 200:
            return parseResponse(responseData ?? Data(), planType: creds.planType, now: Date())
        case 401, 403:
            return CodexUsageData(
                planType: creds.planType,
                error: "Codex API rejected the token (HTTP \(status ?? 0)). Run `codex login` to refresh."
            )
        case 429:
            return CodexUsageData(
                planType: creds.planType,
                error: "Codex usage API rate limited. Will retry."
            )
        default:
            // Likely Cloudflare (522/525/1020) or a network error.
            return CodexUsageData(
                planType: creds.planType,
                error: "Codex usage unavailable (HTTP \(status ?? 0)). The endpoint may be blocking this client."
            )
        }
    }

    /// Parse a `chatgpt.com/api/codex/usage` JSON payload into our model. Exposed
    /// (internal) so tests can pin the schema.
    nonisolated static func parseResponse(_ data: Data, planType: String? = nil, now: Date = Date()) -> CodexUsageData {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return CodexUsageData(planType: planType, error: "Codex usage response was not JSON")
        }

        let plan = (json["plan_type"] as? String) ?? planType
        let rateLimit = json["rate_limit"] as? [String: Any]
        let primary = rateLimit?["primary_window"] as? [String: Any]
        let secondary = rateLimit?["secondary_window"] as? [String: Any]

        return CodexUsageData(
            primaryUsedPercent: primary?["used_percent"] as? Double,
            primaryWindowSeconds: primary?["limit_window_seconds"] as? Int,
            primaryResetsAt: epochSeconds(primary?["reset_at"]),
            secondaryUsedPercent: secondary?["used_percent"] as? Double,
            secondaryWindowSeconds: secondary?["limit_window_seconds"] as? Int,
            secondaryResetsAt: epochSeconds(secondary?["reset_at"]),
            planType: plan,
            lastUpdated: now,
            error: nil,
            isStale: false
        )
    }

    nonisolated private static func epochSeconds(_ value: Any?) -> Date? {
        if let v = value as? Double { return Date(timeIntervalSince1970: v) }
        if let v = value as? Int { return Date(timeIntervalSince1970: TimeInterval(v)) }
        return nil
    }
}
