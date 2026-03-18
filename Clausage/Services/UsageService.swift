import Foundation
import SwiftData

struct UsageData: Equatable {
    var fiveHourPercent: Double?
    var fiveHourResetsAt: Date?
    var weeklyPercent: Double?
    var weeklyResetsAt: Date?
    var lastUpdated: Date?
    var error: String?

    static func == (lhs: UsageData, rhs: UsageData) -> Bool {
        lhs.fiveHourPercent == rhs.fiveHourPercent
        && lhs.weeklyPercent == rhs.weeklyPercent
        && lhs.lastUpdated == rhs.lastUpdated
        && lhs.error == rhs.error
    }
}

@Observable
final class UsageService {
    var usage = UsageData()
    var isLoading = false

    private var refreshTimer: Timer?
    private var consecutiveFailures = 0
    private var lastSuccessfulUsage: UsageData?
    private var modelContainer: ModelContainer?

    init() {
        startRefreshTimer()
        Task { @MainActor in
            self.fetch()
        }
    }

    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        let interval = AppSettings.shared.refreshInterval
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetch()
            }
        }
    }

    func updateRefreshInterval() {
        startRefreshTimer()
    }

    @MainActor
    func fetch() {
        isLoading = true

        Task.detached(priority: .utility) { [weak self] in
            let result = Self.fetchUsage()

            await MainActor.run {
                guard let self else { return }

                if result.error != nil {
                    self.consecutiveFailures += 1
                    if let lastGood = self.lastSuccessfulUsage, self.consecutiveFailures <= 5 {
                        self.usage = lastGood
                    } else {
                        self.usage = result
                    }

                    let delay = min(15.0 * pow(2.0, Double(self.consecutiveFailures - 1)), 120.0)
                    Task {
                        try? await Task.sleep(for: .seconds(delay))
                        self.fetch()
                    }
                } else {
                    self.consecutiveFailures = 0
                    self.lastSuccessfulUsage = result
                    self.usage = result
                    self.persistSnapshot(result)
                }
                self.isLoading = false
            }
        }
    }

    private func persistSnapshot(_ data: UsageData) {
        guard let container = modelContainer,
              let fiveHour = data.fiveHourPercent,
              let weekly = data.weeklyPercent else { return }

        let snapshot = UsageSnapshot(
            timestamp: Date(),
            fiveHourPercent: fiveHour,
            weeklyPercent: weekly,
            fiveHourResetsAt: data.fiveHourResetsAt,
            weeklyResetsAt: data.weeklyResetsAt
        )

        Task.detached {
            let context = ModelContext(container)
            context.insert(snapshot)
            try? context.save()
        }
    }

    // MARK: - API

    private static func fetchUsage() -> UsageData {
        guard let token = KeychainService.getAccessToken() else {
            return UsageData(error: "No Claude Code credentials found. Open Claude Code and log in first.")
        }

        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            return UsageData(error: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("clausage/1.0.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseError: Error?
        var httpStatusCode: Int?

        URLSession.shared.dataTask(with: request) { data, response, error in
            responseData = data
            responseError = error
            httpStatusCode = (response as? HTTPURLResponse)?.statusCode
            semaphore.signal()
        }.resume()
        semaphore.wait()

        if let error = responseError {
            return UsageData(error: error.localizedDescription)
        }

        // On 401, refresh token from Claude Code's keychain and retry
        if httpStatusCode == 401 {
            guard let freshToken = KeychainService.refreshToken() else {
                return UsageData(error: "Authentication failed. Re-login to Claude Code.")
            }
            request.setValue("Bearer \(freshToken)", forHTTPHeaderField: "Authorization")

            let retrySemaphore = DispatchSemaphore(value: 0)
            var retryData: Data?
            var retryError: Error?
            URLSession.shared.dataTask(with: request) { data, _, error in
                retryData = data
                retryError = error
                retrySemaphore.signal()
            }.resume()
            retrySemaphore.wait()

            if let error = retryError {
                return UsageData(error: error.localizedDescription)
            }
            guard let data = retryData else {
                return UsageData(error: "No data received")
            }
            return parseResponse(data)
        }

        if httpStatusCode == 429 {
            return UsageData(error: "Rate limited")
        }

        if let code = httpStatusCode, code != 200 {
            return UsageData(error: "API error (\(code))")
        }

        guard let data = responseData else {
            return UsageData(error: "No data received")
        }

        return parseResponse(data)
    }

    private static func parseResponse(_ data: Data) -> UsageData {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return UsageData(error: "Failed to parse response")
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return UsageData(error: message)
        }

        var usage = UsageData(lastUpdated: Date())

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let fiveHour = json["five_hour"] as? [String: Any] {
            usage.fiveHourPercent = parseDouble(fiveHour["utilization"])
            if let resetStr = fiveHour["resets_at"] as? String {
                usage.fiveHourResetsAt = isoFormatter.date(from: resetStr)
            }
        }

        if let sevenDay = json["seven_day"] as? [String: Any] {
            usage.weeklyPercent = parseDouble(sevenDay["utilization"])
            if let resetStr = sevenDay["resets_at"] as? String {
                usage.weeklyResetsAt = isoFormatter.date(from: resetStr)
            }
        }

        if usage.fiveHourPercent == nil && usage.weeklyPercent == nil {
            let rawStr = String(data: data, encoding: .utf8) ?? "unknown"
            usage.error = "Unexpected response: \(rawStr.prefix(200))"
        }

        return usage
    }

    private static func parseDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }

    static func resetTimeString(_ date: Date?) -> String {
        guard let date = date else { return "\u{2014}" }
        let interval = date.timeIntervalSince(Date())
        if interval <= 0 { return "now" }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 24 {
            let days = hours / 24
            return "in \(days)d \(hours % 24)h"
        } else if hours > 0 {
            return "in \(hours)h \(minutes)m"
        } else {
            return "in \(minutes)m"
        }
    }
}
