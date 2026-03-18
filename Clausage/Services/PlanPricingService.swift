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

    /// Analyze usage and produce per-plan projections
    func analyzePlans(
        snapshots: [UsageSnapshot],
        currentPlanId: String
    ) -> PlanAnalysis? {
        guard let pricing = pricing else { return nil }
        guard let currentPlan = pricing.plans.first(where: { $0.id == currentPlanId }) else { return nil }

        guard snapshots.count >= 10 else {
            return PlanAnalysis(
                currentPlan: currentPlan,
                projections: [],
                insight: "Need more usage data for analysis. Keep using Claude and check back later.",
                dataPoints: snapshots.count,
                dataDays: 0
            )
        }

        // Use recent data (last 7 days, or all if less)
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        let recent = snapshots.filter { $0.timestamp > weekAgo }
        let analyzed: [UsageSnapshot] = recent.isEmpty ? Array(snapshots.suffix(200)) : recent

        let dataDays: Double
        if let first = analyzed.first, let last = analyzed.last {
            dataDays = max(1, last.timestamp.timeIntervalSince(first.timestamp) / 86400)
        } else {
            dataDays = 1
        }

        // Compute projections for each plan
        let projections: [PlanProjection] = pricing.plans.map { plan in
            projectPlan(plan, from: analyzed, currentMultiplier: currentPlan.usageMultiplier)
        }

        // Generate insight text
        let currentProjection = projections.first(where: { $0.plan.id == currentPlanId })
        let insight = generateInsight(
            currentPlan: currentPlan,
            currentProjection: currentProjection,
            allProjections: projections
        )

        return PlanAnalysis(
            currentPlan: currentPlan,
            projections: projections,
            insight: insight,
            dataPoints: analyzed.count,
            dataDays: Int(dataDays)
        )
    }

    private func projectPlan(
        _ plan: PlanTier,
        from snapshots: [UsageSnapshot],
        currentMultiplier: Double
    ) -> PlanProjection {
        let scale = currentMultiplier / plan.usageMultiplier

        // Project what utilization would look like on this plan
        let projected5h = snapshots.map { min($0.fiveHourPercent * scale, 100) }
        let projectedWeekly = snapshots.map { min($0.weeklyPercent * scale, 100) }

        let avg5h = projected5h.reduce(0, +) / Double(max(projected5h.count, 1))
        let avgWeekly = projectedWeekly.reduce(0, +) / Double(max(projectedWeekly.count, 1))

        let pctAt5hLimit = Double(projected5h.filter { $0 >= 95 }.count) / Double(max(snapshots.count, 1)) * 100
        let pctAtWeeklyLimit = Double(projectedWeekly.filter { $0 >= 95 }.count) / Double(max(snapshots.count, 1)) * 100

        // Overflow: how much over 100% the raw (unclamped) projection goes
        let rawProjected5h = snapshots.map { $0.fiveHourPercent * scale }
        let overflowSamples = rawProjected5h.filter { $0 > 100 }
        let avgOverflow = overflowSamples.isEmpty ? 0 : overflowSamples.map { $0 - 100 }.reduce(0, +) / Double(overflowSamples.count)

        // Headroom: how much capacity is left (negative = over limit)
        let headroom5h = 100 - avg5h
        let headroomWeekly = 100 - avgWeekly

        return PlanProjection(
            plan: plan,
            projectedAvg5h: avg5h,
            projectedAvgWeekly: avgWeekly,
            pctTimeAt5hLimit: pctAt5hLimit,
            pctTimeAtWeeklyLimit: pctAtWeeklyLimit,
            avgOverflowPct: avgOverflow,
            headroom: min(headroom5h, headroomWeekly)
        )
    }

    private func generateInsight(
        currentPlan: PlanTier,
        currentProjection: PlanProjection?,
        allProjections: [PlanProjection]
    ) -> String {
        guard let current = currentProjection else {
            return "Unable to analyze current plan usage."
        }

        var parts: [String] = []

        // Current usage summary
        let avgStr = "You use about \(Int(current.projectedAvg5h))% of your \(currentPlan.name) plan's 5-hour window on average"

        if current.pctTimeAt5hLimit > 0 {
            parts.append("\(avgStr), and are at the limit \(formatPct(current.pctTimeAt5hLimit)) of the time.")
        } else {
            parts.append("\(avgStr).")
        }

        if current.pctTimeAtWeeklyLimit > 0 {
            parts.append("You hit the weekly limit \(formatPct(current.pctTimeAtWeeklyLimit)) of the time.")
        }

        // Find the cheapest plan with < 5% time at limit
        let affordable = allProjections
            .filter { $0.pctTimeAt5hLimit < 5 && $0.pctTimeAtWeeklyLimit < 5 }
            .sorted(by: { $0.plan.monthlyPrice < $1.plan.monthlyPrice })

        if let bestFit = affordable.first, bestFit.plan.id != currentPlan.id {
            let priceDiff = bestFit.plan.monthlyPrice - currentPlan.monthlyPrice
            if priceDiff < 0 {
                parts.append("You could save $\(Int(abs(priceDiff)))/mo by switching to \(bestFit.plan.name) and still rarely hit limits.")
            } else if priceDiff > 0 && (current.pctTimeAt5hLimit > 5 || current.pctTimeAtWeeklyLimit > 5) {
                parts.append("\(bestFit.plan.name) ($\(Int(priceDiff))/mo more) would keep you under limits almost all the time.")
            }
        }

        // If hitting limits on current plan, add supplementation note
        if current.pctTimeAt5hLimit > 10 && current.avgOverflowPct > 5 {
            parts.append("During rate-limited periods, you'd need roughly \(Int(current.avgOverflowPct))% more capacity than your plan provides. Compare the cost of upgrading vs. supplementing with API tokens for those periods.")
        }

        return parts.joined(separator: " ")
    }

    private func formatPct(_ pct: Double) -> String {
        if pct < 1 { return "<1%" }
        return "\(Int(pct))%"
    }
}

// MARK: - Analysis Models

struct PlanAnalysis {
    let currentPlan: PlanTier
    let projections: [PlanProjection]
    let insight: String
    let dataPoints: Int
    let dataDays: Int
}

struct PlanProjection: Identifiable {
    var id: String { plan.id }
    let plan: PlanTier
    let projectedAvg5h: Double        // Average 5h utilization on this plan
    let projectedAvgWeekly: Double     // Average weekly utilization on this plan
    let pctTimeAt5hLimit: Double       // % of time at 5h limit
    let pctTimeAtWeeklyLimit: Double   // % of time at weekly limit
    let avgOverflowPct: Double         // When over limit, avg % over
    let headroom: Double               // Min headroom across both windows
}
