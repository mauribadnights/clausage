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

    private static func findResourceBundle() -> Bundle {
        // In .app distribution: SPM resource bundle is at Contents/Resources/Clausage_Clausage.bundle
        if let bundlePath = Bundle.main.path(forResource: "Clausage_Clausage", ofType: "bundle"),
           let bundle = Bundle(path: bundlePath) {
            return bundle
        }
        // In SPM dev builds: Bundle.module works directly
        return Bundle.module
    }

    private func loadBundled() {
        let url = Self.findResourceBundle().url(forResource: "pricing", withExtension: "json")
            ?? Bundle.main.url(forResource: "pricing", withExtension: "json")

        guard let url,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PricingData.self, from: data) else {
            return
        }
        pricing = decoded
        PromoSchedule.shared.update(from: decoded.promo)
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
                    PromoSchedule.shared.update(from: decoded.promo)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.lastFetchError = error.localizedDescription
                }
            }
        }
    }

    /// Analyze usage and produce per-plan projections using peak-at-reset detection
    func analyzePlans(
        snapshots: [UsageSnapshot],
        currentPlanId: String,
        planHistory: [PlanChange] = []
    ) -> PlanAnalysis? {
        guard let pricing = pricing else { return nil }
        guard let currentPlan = pricing.plans.first(where: { $0.id == currentPlanId }) else { return nil }

        let sorted = snapshots.sorted(by: { $0.timestamp < $1.timestamp })

        guard sorted.count >= 10 else {
            return PlanAnalysis(
                currentPlan: currentPlan,
                projections: [],
                insight: "Need more usage data for analysis. Keep using Claude and check back later.",
                dataPoints: sorted.count,
                dataDays: 0,
                fiveHourCycles: 0,
                weeklyCycles: 0
            )
        }

        let dataDays: Double
        if let first = sorted.first, let last = sorted.last {
            dataDays = max(1, last.timestamp.timeIntervalSince(first.timestamp) / 86400)
        } else {
            dataDays = 1
        }

        // Extract end-of-window peaks using reset detection
        let peaks5h = extractWindowPeaks(from: sorted, window: .fiveHour)
        let peaksWeekly = extractWindowPeaks(from: sorted, window: .weekly)

        // Resolve per-peak plan multiplier using plan history
        let resolveMultiplier: (Date) -> Double = { timestamp in
            let planId = planHistory
                .filter { $0.date <= timestamp }
                .max(by: { $0.date < $1.date })?
                .planId ?? currentPlanId
            return pricing.plans.first(where: { $0.id == planId })?.usageMultiplier
                ?? currentPlan.usageMultiplier
        }

        // Compute projections for each plan
        let projections: [PlanProjection] = pricing.plans.map { plan in
            projectPlan(
                plan,
                peaks5h: peaks5h,
                peaksWeekly: peaksWeekly,
                resolveMultiplier: resolveMultiplier
            )
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
            dataPoints: sorted.count,
            dataDays: Int(dataDays),
            fiveHourCycles: peaks5h.count,
            weeklyCycles: peaksWeekly.count
        )
    }

    // MARK: - Peak Detection

    struct WindowPeak {
        let value: Double
        let timestamp: Date
    }

    enum WindowType {
        case fiveHour, weekly
    }

    /// Detect window resets and extract the peak utilization before each reset.
    /// Uses the stored `resetsAt` timestamp to determine if a reset occurred between
    /// consecutive snapshots. When the laptop is closed during a reset, the last
    /// snapshot before the gap is used as the end-of-window value.
    func extractWindowPeaks(from snapshots: [UsageSnapshot], window: WindowType) -> [WindowPeak] {
        guard snapshots.count >= 2 else { return [] }

        var peaks: [WindowPeak] = []

        for i in 0..<(snapshots.count - 1) {
            let current = snapshots[i]
            let next = snapshots[i + 1]

            let currentPercent: Double
            let nextPercent: Double
            let currentResetsAt: Date?

            switch window {
            case .fiveHour:
                currentPercent = current.fiveHourPercent
                nextPercent = next.fiveHourPercent
                currentResetsAt = current.fiveHourResetsAt
            case .weekly:
                currentPercent = current.weeklyPercent
                nextPercent = next.weeklyPercent
                currentResetsAt = current.weeklyResetsAt
            }

            // Method 1: Known reset time — resetsAt falls between current and next snapshot
            if let resetTime = currentResetsAt,
               resetTime > current.timestamp,
               resetTime <= next.timestamp {
                peaks.append(WindowPeak(value: currentPercent, timestamp: current.timestamp))
                continue
            }

            // Method 2: Fallback — detect reset by significant usage drop without a known reset time
            // This handles cases where resetsAt wasn't available in older snapshots
            if currentPercent > 10 && nextPercent < currentPercent * 0.4 {
                peaks.append(WindowPeak(value: currentPercent, timestamp: current.timestamp))
            }
        }

        return peaks
    }

    // MARK: - Projection

    /// Half-life for recency weighting (days). Data this many days old has half the weight of today's.
    static let recencyHalfLifeDays: Double = 3.0

    private func weightedAverage(_ items: [(value: Double, timestamp: Date)]) -> Double {
        guard !items.isEmpty else { return 0 }
        let now = Date()
        var weightedSum = 0.0
        var totalWeight = 0.0
        for item in items {
            let ageDays = max(0, now.timeIntervalSince(item.timestamp)) / 86400
            let weight = pow(2.0, -ageDays / Self.recencyHalfLifeDays)
            weightedSum += item.value * weight
            totalWeight += weight
        }
        return totalWeight > 0 ? weightedSum / totalWeight : 0
    }

    private func projectPlan(
        _ plan: PlanTier,
        peaks5h: [WindowPeak],
        peaksWeekly: [WindowPeak],
        resolveMultiplier: (Date) -> Double
    ) -> PlanProjection {
        // Project each peak using its own plan's multiplier (handles plan switches mid-history)
        let projected5h: [(value: Double, timestamp: Date)] = peaks5h.map { peak in
            (peak.value * (resolveMultiplier(peak.timestamp) / plan.usageMultiplier), peak.timestamp)
        }
        let projectedWeekly: [(value: Double, timestamp: Date)] = peaksWeekly.map { peak in
            (peak.value * (resolveMultiplier(peak.timestamp) / plan.usageMultiplier), peak.timestamp)
        }

        // Recency-weighted averages: recent data matters more (3-day half-life)
        let avgPeak5h = weightedAverage(projected5h)
        let avgPeakWeekly = weightedAverage(projectedWeekly)

        let maxPeak5h = projected5h.map(\.value).max() ?? 0
        let maxPeakWeekly = projectedWeekly.map(\.value).max() ?? 0

        let cyclesOver5h = projected5h.filter { $0.value > 100 }.count
        let cyclesOverWeekly = projectedWeekly.filter { $0.value > 100 }.count

        // Headroom based on average peaks (negative = over capacity)
        let headroom5h = 100 - avgPeak5h
        let headroomWeekly = 100 - avgPeakWeekly

        return PlanProjection(
            plan: plan,
            avgPeak5h: avgPeak5h,
            avgPeakWeekly: avgPeakWeekly,
            maxPeak5h: maxPeak5h,
            maxPeakWeekly: maxPeakWeekly,
            cyclesOver5h: cyclesOver5h,
            cyclesOverWeekly: cyclesOverWeekly,
            total5hCycles: peaks5h.count,
            totalWeeklyCycles: peaksWeekly.count,
            headroom: min(headroom5h, headroomWeekly)
        )
    }

    // MARK: - Insight Generation

    private func generateInsight(
        currentPlan: PlanTier,
        currentProjection: PlanProjection?,
        allProjections: [PlanProjection]
    ) -> String {
        guard let current = currentProjection else {
            return "Unable to analyze current plan usage."
        }

        // Need at least some detected cycles to give meaningful advice
        if current.total5hCycles == 0 && current.totalWeeklyCycles == 0 {
            return "Not enough window resets detected yet. Keep using Claude — the optimizer will improve as more data accumulates."
        }

        var parts: [String] = []

        // Current usage summary based on peaks
        if current.total5hCycles > 0 {
            let peakStr = "Based on recent usage trends, you typically reach \(Int(current.avgPeak5h))% of your \(currentPlan.name) plan's capacity by end of each 5-hour window"
            if current.cyclesOver5h > 0 {
                let pctOver = Double(current.cyclesOver5h) / Double(current.total5hCycles) * 100
                parts.append("\(peakStr), exceeding the limit in \(formatPct(pctOver)) of windows.")
            } else {
                parts.append("\(peakStr).")
            }
        }

        if current.totalWeeklyCycles > 0 && current.cyclesOverWeekly > 0 {
            let pctOver = Double(current.cyclesOverWeekly) / Double(current.totalWeeklyCycles) * 100
            parts.append("You exceed the weekly limit in \(formatPct(pctOver)) of weeks.")
        }

        // Find the cheapest plan where < 10% of cycles exceed capacity
        let affordable = allProjections
            .filter { projection in
                let pctOver5h = projection.total5hCycles > 0
                    ? Double(projection.cyclesOver5h) / Double(projection.total5hCycles)
                    : 0
                let pctOverWeekly = projection.totalWeeklyCycles > 0
                    ? Double(projection.cyclesOverWeekly) / Double(projection.totalWeeklyCycles)
                    : 0
                return pctOver5h < 0.1 && pctOverWeekly < 0.1
            }
            .sorted(by: { $0.plan.monthlyPrice < $1.plan.monthlyPrice })

        if let bestFit = affordable.first, bestFit.plan.id != currentPlan.id {
            let priceDiff = bestFit.plan.monthlyPrice - currentPlan.monthlyPrice
            if priceDiff < 0 {
                parts.append("You could save $\(Int(abs(priceDiff)))/mo by switching to \(bestFit.plan.name) — you'd still rarely exceed limits.")
            } else if priceDiff > 0 && (current.cyclesOver5h > 0 || current.cyclesOverWeekly > 0) {
                parts.append("\(bestFit.plan.name) ($\(Int(priceDiff))/mo more) would keep you under limits in nearly all windows.")
            }
        }

        // Worst-case note
        if current.maxPeak5h > 100 {
            let overBy = Int(current.maxPeak5h - 100)
            parts.append("Your heaviest 5-hour window exceeded capacity by \(overBy)% — consider whether API tokens could cover those spikes.")
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
    let fiveHourCycles: Int
    let weeklyCycles: Int
}

struct PlanProjection: Identifiable {
    var id: String { plan.id }
    let plan: PlanTier
    let avgPeak5h: Double           // Avg end-of-window 5h utilization on this plan
    let avgPeakWeekly: Double       // Avg end-of-window weekly utilization on this plan
    let maxPeak5h: Double           // Worst-case 5h window
    let maxPeakWeekly: Double       // Worst-case weekly window
    let cyclesOver5h: Int           // 5h windows that would exceed 100%
    let cyclesOverWeekly: Int       // Weekly windows that would exceed 100%
    let total5hCycles: Int          // Total 5h cycles detected
    let totalWeeklyCycles: Int      // Total weekly cycles detected
    let headroom: Double            // Min headroom based on avg peaks (negative = over)
}
