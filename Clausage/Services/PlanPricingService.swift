import Foundation

@Observable
final class PlanPricingService {
    var pricing: PricingData?
    var lastFetchError: String?

    private static let remoteURL = "https://raw.githubusercontent.com/mauribadnights/clausage/main/pricing.json"

    init() {
        loadBundled()
        fetchRemote()
    }

    private func loadBundled() {
        // SPM resources are in Bundle.module, .app bundle resources in Bundle.main
        let url = Bundle.module.url(forResource: "pricing", withExtension: "json")
            ?? Bundle.main.url(forResource: "pricing", withExtension: "json")

        guard let url,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PricingData.self, from: data) else {
            return
        }
        pricing = decoded
    }

    func fetchRemote() {
        Task.detached(priority: .utility) {
            guard let url = URL(string: Self.remoteURL) else { return }

            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.cachePolicy = .reloadIgnoringLocalCacheData

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    return
                }
                let decoded = try JSONDecoder().decode(PricingData.self, from: data)

                await MainActor.run { [weak self] in
                    self?.pricing = decoded
                    self?.lastFetchError = nil
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.lastFetchError = error.localizedDescription
                }
            }
        }
    }

    /// Analyze usage history and recommend plan changes
    func analyzeUsage(
        snapshots: [UsageSnapshot],
        currentPlanId: String
    ) -> PlanRecommendation? {
        guard let pricing = pricing else { return nil }
        guard let currentPlan = pricing.plans.first(where: { $0.id == currentPlanId }) else { return nil }
        guard snapshots.count >= 10 else {
            return PlanRecommendation(
                recommendation: .insufficientData,
                currentPlan: currentPlan,
                suggestedPlan: nil,
                reasoning: "Need more usage data to make a recommendation. Keep using Claude and check back later.",
                avgFiveHourUsage: nil,
                avgWeeklyUsage: nil,
                timesHitLimit: 0
            )
        }

        // Analyze recent snapshots (last 7 days)
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        let recentSnapshots = snapshots.filter { $0.timestamp > weekAgo }
        let analyzed = recentSnapshots.isEmpty ? snapshots.suffix(50) : ArraySlice(recentSnapshots)

        let avgFiveHour = analyzed.map(\.fiveHourPercent).reduce(0, +) / Double(analyzed.count)
        let avgWeekly = analyzed.map(\.weeklyPercent).reduce(0, +) / Double(analyzed.count)
        let timesHitLimit = analyzed.filter { $0.fiveHourPercent >= 95 || $0.weeklyPercent >= 95 }.count

        // Determine recommendation
        let hitLimitFrequency = Double(timesHitLimit) / Double(analyzed.count)

        if hitLimitFrequency > 0.3 || avgWeekly > 80 {
            let upgrades = pricing.plans.filter { $0.usageMultiplier > currentPlan.usageMultiplier }
            if let nextUp = upgrades.first {
                return PlanRecommendation(
                    recommendation: .upgrade,
                    currentPlan: currentPlan,
                    suggestedPlan: nextUp,
                    reasoning: "You're hitting usage limits \(Int(hitLimitFrequency * 100))% of the time with an average weekly usage of \(Int(avgWeekly))%. Upgrading to \(nextUp.name) would give you \(nextUp.usageMultiplier / currentPlan.usageMultiplier)x more capacity for $\(Int(nextUp.monthlyPrice))/mo.",
                    avgFiveHourUsage: avgFiveHour,
                    avgWeeklyUsage: avgWeekly,
                    timesHitLimit: timesHitLimit
                )
            }
        }

        if avgWeekly < 20 && avgFiveHour < 30 && currentPlan.monthlyPrice > 0 {
            let downgrades = pricing.plans.filter { $0.usageMultiplier < currentPlan.usageMultiplier && $0.monthlyPrice < currentPlan.monthlyPrice }
            if let nextDown = downgrades.last {
                let savings = currentPlan.monthlyPrice - nextDown.monthlyPrice
                return PlanRecommendation(
                    recommendation: .downgrade,
                    currentPlan: currentPlan,
                    suggestedPlan: nextDown,
                    reasoning: "Your average weekly usage is only \(Int(avgWeekly))%. You could save $\(Int(savings))/mo by switching to \(nextDown.name) and still have plenty of headroom.",
                    avgFiveHourUsage: avgFiveHour,
                    avgWeeklyUsage: avgWeekly,
                    timesHitLimit: timesHitLimit
                )
            }
        }

        return PlanRecommendation(
            recommendation: .stayPut,
            currentPlan: currentPlan,
            suggestedPlan: nil,
            reasoning: "Your current plan fits your usage well. Average weekly usage: \(Int(avgWeekly))%, hitting limits \(Int(hitLimitFrequency * 100))% of the time.",
            avgFiveHourUsage: avgFiveHour,
            avgWeeklyUsage: avgWeekly,
            timesHitLimit: timesHitLimit
        )
    }
}

enum RecommendationType {
    case upgrade
    case downgrade
    case stayPut
    case insufficientData
}

struct PlanRecommendation {
    let recommendation: RecommendationType
    let currentPlan: PlanTier
    let suggestedPlan: PlanTier?
    let reasoning: String
    let avgFiveHourUsage: Double?
    let avgWeeklyUsage: Double?
    let timesHitLimit: Int
}
