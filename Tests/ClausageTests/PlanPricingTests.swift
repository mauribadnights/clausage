import XCTest
import SwiftData
@testable import Clausage

@MainActor
final class PlanPricingTests: XCTestCase {

    private var container: ModelContainer!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: UsageSnapshot.self, configurations: config)
    }

    // MARK: - PricingData decoding

    func testDecodeBundledPricing() throws {
        guard let url = Bundle.module.url(forResource: "pricing", withExtension: "json") else {
            XCTFail("pricing.json not found in bundle")
            return
        }
        let data = try Data(contentsOf: url)
        let pricing = try JSONDecoder().decode(PricingData.self, from: data)

        XCTAssertFalse(pricing.plans.isEmpty, "Should have plans")
        XCTAssertFalse(pricing.tokenPricing.isEmpty, "Should have token pricing")
        XCTAssertFalse(pricing.lastUpdated.isEmpty, "Should have lastUpdated date")
    }

    func testPlansHaveRequiredFields() throws {
        let pricing = try loadBundledPricing()

        for plan in pricing.plans {
            XCTAssertFalse(plan.id.isEmpty, "Plan id should not be empty")
            XCTAssertFalse(plan.name.isEmpty, "Plan name should not be empty")
            XCTAssertGreaterThanOrEqual(plan.monthlyPrice, 0, "Price should be >= 0")
            XCTAssertGreaterThan(plan.usageMultiplier, 0, "Usage multiplier should be > 0")
        }
    }

    func testTokenPricingHasRequiredFields() throws {
        let pricing = try loadBundledPricing()

        for token in pricing.tokenPricing {
            XCTAssertFalse(token.model.isEmpty, "Model id should not be empty")
            XCTAssertFalse(token.displayName.isEmpty, "Display name should not be empty")
            XCTAssertGreaterThan(token.inputPerMillion, 0, "Input price should be > 0")
            XCTAssertGreaterThan(token.outputPerMillion, 0, "Output price should be > 0")
        }
    }

    func testFreePlanExists() throws {
        let pricing = try loadBundledPricing()
        let free = pricing.plans.first(where: { $0.id == "free" })
        XCTAssertNotNil(free, "Free plan should exist")
        XCTAssertEqual(free?.monthlyPrice, 0)
    }

    func testProPlanExists() throws {
        let pricing = try loadBundledPricing()
        let pro = pricing.plans.first(where: { $0.id == "pro" })
        XCTAssertNotNil(pro, "Pro plan should exist")
        XCTAssertEqual(pro?.monthlyPrice, 20)
    }

    func testPlansAreOrderedByPrice() throws {
        let pricing = try loadBundledPricing()
        let prices = pricing.plans.map(\.monthlyPrice)
        XCTAssertEqual(prices, prices.sorted(), "Plans should be ordered by price ascending")
    }

    func testUsageMultipliersIncreaseWithPrice() throws {
        let pricing = try loadBundledPricing()
        let multipliers = pricing.plans.map(\.usageMultiplier)
        XCTAssertEqual(multipliers, multipliers.sorted(), "Usage multipliers should increase with price")
    }

    // MARK: - Peak detection

    func testDetectsResetViaResetsAtTimestamp() {
        let service = makeService()
        let now = Date()
        let context = container.mainContext

        // Snapshot A: 80% usage, resets in 30 min
        let a = UsageSnapshot(
            timestamp: now.addingTimeInterval(-3600),
            fiveHourPercent: 80,
            weeklyPercent: 60,
            fiveHourResetsAt: now.addingTimeInterval(-1800),
            weeklyResetsAt: now.addingTimeInterval(86400)
        )
        // Snapshot B: after 5h reset, usage dropped
        let b = UsageSnapshot(
            timestamp: now,
            fiveHourPercent: 10,
            weeklyPercent: 65,
            fiveHourResetsAt: now.addingTimeInterval(18000),
            weeklyResetsAt: now.addingTimeInterval(86400)
        )
        context.insert(a)
        context.insert(b)

        let peaks5h = service.extractWindowPeaks(from: [a, b], window: .fiveHour)
        let peaksWeekly = service.extractWindowPeaks(from: [a, b], window: .weekly)

        XCTAssertEqual(peaks5h.count, 1, "Should detect one 5h reset")
        XCTAssertEqual(peaks5h.first?.value, 80, "Peak should be the value before reset")
        XCTAssertEqual(peaksWeekly.count, 0, "No weekly reset occurred")
    }

    func testDetectsResetDuringLaptopSleep() {
        let service = makeService()
        let now = Date()
        let context = container.mainContext

        // Snapshot A: 75% weekly, resets in 2 hours — then laptop closed for 8 hours
        let a = UsageSnapshot(
            timestamp: now.addingTimeInterval(-28800), // 8h ago
            fiveHourPercent: 50,
            weeklyPercent: 75,
            fiveHourResetsAt: now.addingTimeInterval(-25200), // 7h ago
            weeklyResetsAt: now.addingTimeInterval(-21600) // 6h ago
        )
        // Snapshot B: laptop reopened, both windows have reset
        let b = UsageSnapshot(
            timestamp: now,
            fiveHourPercent: 5,
            weeklyPercent: 3,
            fiveHourResetsAt: now.addingTimeInterval(18000),
            weeklyResetsAt: now.addingTimeInterval(604800)
        )
        context.insert(a)
        context.insert(b)

        let peaks5h = service.extractWindowPeaks(from: [a, b], window: .fiveHour)
        let peaksWeekly = service.extractWindowPeaks(from: [a, b], window: .weekly)

        XCTAssertEqual(peaks5h.count, 1, "Should detect 5h reset during sleep")
        XCTAssertEqual(peaks5h.first?.value, 50)
        XCTAssertEqual(peaksWeekly.count, 1, "Should detect weekly reset during sleep")
        XCTAssertEqual(peaksWeekly.first?.value, 75)
    }

    func testFallbackDropDetection() {
        let service = makeService()
        let now = Date()
        let context = container.mainContext

        // Old snapshots without resetsAt data
        let a = UsageSnapshot(
            timestamp: now.addingTimeInterval(-600),
            fiveHourPercent: 70,
            weeklyPercent: 85
        )
        let b = UsageSnapshot(
            timestamp: now,
            fiveHourPercent: 5,
            weeklyPercent: 10
        )
        context.insert(a)
        context.insert(b)

        let peaks5h = service.extractWindowPeaks(from: [a, b], window: .fiveHour)
        let peaksWeekly = service.extractWindowPeaks(from: [a, b], window: .weekly)

        XCTAssertEqual(peaks5h.count, 1, "Should detect reset via drop fallback")
        XCTAssertEqual(peaksWeekly.count, 1, "Should detect reset via drop fallback")
    }

    func testNoFalseResetOnSmallDrop() {
        let service = makeService()
        let now = Date()
        let context = container.mainContext

        // Usage decreases slightly (not a reset)
        let a = UsageSnapshot(
            timestamp: now.addingTimeInterval(-300),
            fiveHourPercent: 50,
            weeklyPercent: 60
        )
        let b = UsageSnapshot(
            timestamp: now,
            fiveHourPercent: 48,
            weeklyPercent: 58
        )
        context.insert(a)
        context.insert(b)

        let peaks5h = service.extractWindowPeaks(from: [a, b], window: .fiveHour)
        let peaksWeekly = service.extractWindowPeaks(from: [a, b], window: .weekly)

        XCTAssertEqual(peaks5h.count, 0, "Small drop should not trigger reset detection")
        XCTAssertEqual(peaksWeekly.count, 0)
    }

    func testMultipleResetsDetected() {
        let service = makeService()
        let now = Date()
        let context = container.mainContext

        // Simulate 3 five-hour windows
        var snapshots: [UsageSnapshot] = []
        for cycle in 0..<3 {
            let baseTime = now.addingTimeInterval(Double(-cycle) * 18000) // 5h apart
            let resetTime = baseTime.addingTimeInterval(18000) // resets at end
            let s = UsageSnapshot(
                timestamp: baseTime,
                fiveHourPercent: Double(60 + cycle * 10),
                weeklyPercent: 40,
                fiveHourResetsAt: resetTime,
                weeklyResetsAt: now.addingTimeInterval(86400)
            )
            context.insert(s)
            snapshots.append(s)
        }
        // Add a final post-reset snapshot
        let final_ = UsageSnapshot(
            timestamp: now.addingTimeInterval(300),
            fiveHourPercent: 5,
            weeklyPercent: 42
        )
        context.insert(final_)
        snapshots.append(final_)

        // Sort by timestamp
        snapshots.sort(by: { $0.timestamp < $1.timestamp })

        let peaks5h = service.extractWindowPeaks(from: snapshots, window: .fiveHour)
        XCTAssertEqual(peaks5h.count, 3, "Should detect 3 five-hour window resets")
    }

    // MARK: - Plan analysis

    func testInsufficientDataReturnsEmptyProjections() {
        let service = makeService()
        let snapshots = makeSnapshotsWithResets(windowCount: 1, peakFiveHour: 50, peakWeekly: 50, snapshotsPerWindow: 3)
        let result = service.analyzePlans(snapshots: snapshots, currentPlanId: "pro")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.projections.isEmpty)
        XCTAssertTrue(result!.insight.contains("Need more"))
    }

    func testAnalysisReturnsProjectionPerPlan() {
        let service = makeService()
        let snapshots = makeSnapshotsWithResets(windowCount: 5, peakFiveHour: 50, peakWeekly: 40)
        let result = service.analyzePlans(snapshots: snapshots, currentPlanId: "pro")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.projections.count, 4, "Should have one projection per plan")
    }

    func testHigherPlanReducesProjectedUtilization() {
        let service = makeService()
        let snapshots = makeSnapshotsWithResets(windowCount: 5, peakFiveHour: 80, peakWeekly: 60)
        let result = service.analyzePlans(snapshots: snapshots, currentPlanId: "pro")!

        let proProj = result.projections.first(where: { $0.plan.id == "pro" })!.avgPeak5h
        let maxProj = result.projections.first(where: { $0.plan.id == "max_5x" })!.avgPeak5h

        XCTAssertGreaterThan(proProj, maxProj, "Higher plan should have lower projected utilization")
    }

    func testLowerPlanIncreasesProjectedUtilization() {
        let service = makeService()
        let snapshots = makeSnapshotsWithResets(windowCount: 5, peakFiveHour: 50, peakWeekly: 30)
        let result = service.analyzePlans(snapshots: snapshots, currentPlanId: "pro")!

        let proProj = result.projections.first(where: { $0.plan.id == "pro" })!.avgPeak5h
        let freeProj = result.projections.first(where: { $0.plan.id == "free" })!.avgPeak5h

        XCTAssertLessThan(proProj, freeProj, "Lower plan should have higher projected utilization")
    }

    func testHeavyUserShowsCyclesOverLimit() {
        let service = makeService()
        // 97% on Pro (5x multiplier), projected to Free (1x): 97 * 5 = 485% — way over
        let snapshots = makeSnapshotsWithResets(windowCount: 5, peakFiveHour: 97, peakWeekly: 85)
        let result = service.analyzePlans(snapshots: snapshots, currentPlanId: "pro")!

        let freeProj = result.projections.first(where: { $0.plan.id == "free" })!
        XCTAssertGreaterThan(freeProj.cyclesOver5h, 0, "Heavy user should show cycles over limit on free plan")
    }

    func testLightUserHasHeadroom() {
        let service = makeService()
        let snapshots = makeSnapshotsWithResets(windowCount: 5, peakFiveHour: 10, peakWeekly: 8)
        let result = service.analyzePlans(snapshots: snapshots, currentPlanId: "pro")!

        let proProj = result.projections.first(where: { $0.plan.id == "pro" })!
        XCTAssertGreaterThan(proProj.headroom, 50, "Light user should have plenty of headroom")
        XCTAssertEqual(proProj.cyclesOver5h, 0, "Light user should never exceed limit")
    }

    func testInsightContainsUsageInfo() {
        let service = makeService()
        let snapshots = makeSnapshotsWithResets(windowCount: 5, peakFiveHour: 60, peakWeekly: 40)
        let result = service.analyzePlans(snapshots: snapshots, currentPlanId: "pro")!
        XCTAssertFalse(result.insight.isEmpty)
        XCTAssertTrue(result.insight.contains("Pro"), "Insight should mention current plan")
    }

    func testUnknownPlanReturnsNil() {
        let service = makeService()
        let snapshots = makeSnapshotsWithResets(windowCount: 5, peakFiveHour: 50, peakWeekly: 50)
        let result = service.analyzePlans(snapshots: snapshots, currentPlanId: "nonexistent")
        XCTAssertNil(result)
    }

    func testProjectionsHaveUniqueIds() {
        let service = makeService()
        let snapshots = makeSnapshotsWithResets(windowCount: 5, peakFiveHour: 50, peakWeekly: 50)
        let result = service.analyzePlans(snapshots: snapshots, currentPlanId: "pro")!
        let ids = result.projections.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Projection IDs should be unique")
    }

    func testAnalysisReportsCycleCounts() {
        let service = makeService()
        let snapshots = makeSnapshotsWithResets(windowCount: 5, peakFiveHour: 60, peakWeekly: 40)
        let result = service.analyzePlans(snapshots: snapshots, currentPlanId: "pro")!
        XCTAssertGreaterThan(result.fiveHourCycles, 0, "Should report detected 5h cycles")
    }

    // MARK: - Plan history

    func testPlanHistoryScalesPeaksCorrectly() {
        let service = makeService()
        let now = Date()
        let context = container.mainContext

        // 3 peaks recorded on Pro (before switch), each at 80%
        // Pro multiplier = 5, Max 20x multiplier = 100
        // With history:   80 * (5/100) = 4% projected onto Max 20x
        // Without history: 80 * (100/100) = 80% projected onto Max 20x
        let switchDate = now.addingTimeInterval(-18000) // switched 5h ago

        let history = [
            PlanChange(date: .distantPast, planId: "pro"),
            PlanChange(date: switchDate, planId: "max_20x")
        ]

        // Build 3 five-hour windows with resets, all BEFORE the switch date
        var snapshots: [UsageSnapshot] = []
        for cycle in 0..<3 {
            let baseTime = now.addingTimeInterval(Double(-(cycle + 2)) * 18000) // well before switchDate
            let resetTime = baseTime.addingTimeInterval(18000)
            let peak = UsageSnapshot(
                timestamp: baseTime,
                fiveHourPercent: 80,
                weeklyPercent: 60,
                fiveHourResetsAt: resetTime,
                weeklyResetsAt: now.addingTimeInterval(86400)
            )
            context.insert(peak)
            snapshots.append(peak)
        }
        // Add enough post-reset snapshots to meet the 10-sample minimum
        for i in 0..<8 {
            let s = UsageSnapshot(
                timestamp: now.addingTimeInterval(Double(-i) * 300),
                fiveHourPercent: 5,
                weeklyPercent: 10,
                fiveHourResetsAt: now.addingTimeInterval(18000),
                weeklyResetsAt: now.addingTimeInterval(604800)
            )
            context.insert(s)
            snapshots.append(s)
        }
        snapshots.sort(by: { $0.timestamp < $1.timestamp })

        let resultWithHistory = service.analyzePlans(snapshots: snapshots, currentPlanId: "max_20x", planHistory: history)!
        let resultWithoutHistory = service.analyzePlans(snapshots: snapshots, currentPlanId: "max_20x")!

        let max20xWithHistory = resultWithHistory.projections.first(where: { $0.plan.id == "max_20x" })!
        let max20xWithout = resultWithoutHistory.projections.first(where: { $0.plan.id == "max_20x" })!

        // With history: peaks at 80% on Pro → 80 * (5/100) = 4% on Max 20x
        // Without history: peaks at 80% assumed Max 20x → 80 * (100/100) = 80%
        XCTAssertLessThan(max20xWithHistory.avgPeak5h, 10,
            "Pro peaks projected onto Max 20x should be very low (~4%)")
        XCTAssertGreaterThan(max20xWithout.avgPeak5h, 70,
            "Without history, peaks are assumed to be Max 20x usage (~80%)")
    }

    func testEmptyPlanHistoryMatchesLegacyBehavior() {
        let service = makeService()
        let snapshots = makeSnapshotsWithResets(windowCount: 5, peakFiveHour: 60, peakWeekly: 40)

        let withEmpty = service.analyzePlans(snapshots: snapshots, currentPlanId: "pro", planHistory: [])!
        let withDefault = service.analyzePlans(snapshots: snapshots, currentPlanId: "pro")!

        let proEmpty = withEmpty.projections.first(where: { $0.plan.id == "pro" })!
        let proDefault = withDefault.projections.first(where: { $0.plan.id == "pro" })!

        XCTAssertEqual(proEmpty.avgPeak5h, proDefault.avgPeak5h, accuracy: 0.01,
            "Empty plan history should produce same results as no history")
    }

    // MARK: - Helpers

    private func makeService() -> PlanPricingService {
        let service = PlanPricingService()
        service.pricing = testPricingData
        return service
    }

    private var testPricingData: PricingData {
        PricingData(
            lastUpdated: "2026-03-18",
            plans: [
                PlanTier(id: "free", name: "Free", monthlyPrice: 0, description: "Basic", usageMultiplier: 1.0),
                PlanTier(id: "pro", name: "Pro", monthlyPrice: 20, description: "5x Free", usageMultiplier: 5.0),
                PlanTier(id: "max_5x", name: "Max (5x Pro)", monthlyPrice: 100, description: "5x Pro", usageMultiplier: 25.0),
                PlanTier(id: "max_20x", name: "Max (20x Pro)", monthlyPrice: 200, description: "20x Pro", usageMultiplier: 100.0)
            ],
            tokenPricing: [
                TokenPricing(model: "opus", displayName: "Opus", inputPerMillion: 5, outputPerMillion: 25)
            ],
            promo: nil
        )
    }

    private func loadBundledPricing() throws -> PricingData {
        guard let url = Bundle.module.url(forResource: "pricing", withExtension: "json") else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "pricing.json not found"])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PricingData.self, from: data)
    }

    /// Generate snapshots that simulate realistic window cycles with resets.
    /// Each "window" has a ramp-up phase followed by a reset.
    @MainActor
    private func makeSnapshotsWithResets(
        windowCount: Int,
        peakFiveHour: Double,
        peakWeekly: Double,
        snapshotsPerWindow: Int = 4
    ) -> [UsageSnapshot] {
        let context = container.mainContext
        var snapshots: [UsageSnapshot] = []
        let now = Date()
        let windowDuration: TimeInterval = 18000 // 5 hours

        for window in 0..<windowCount {
            let windowStart = now.addingTimeInterval(Double(-(windowCount - window)) * windowDuration)
            let resetTime = windowStart.addingTimeInterval(windowDuration)

            for step in 0..<snapshotsPerWindow {
                let progress = Double(step + 1) / Double(snapshotsPerWindow)
                let timestamp = windowStart.addingTimeInterval(windowDuration * progress * 0.9) // don't go past reset

                let fiveHour = peakFiveHour * progress + Double.random(in: -2...2)
                let weekly = peakWeekly * (Double(window) + progress) / Double(windowCount) + Double.random(in: -2...2)

                let snapshot = UsageSnapshot(
                    timestamp: timestamp,
                    fiveHourPercent: max(0, fiveHour),
                    weeklyPercent: max(0, min(100, weekly)),
                    fiveHourResetsAt: resetTime,
                    weeklyResetsAt: window == windowCount - 1 ? resetTime : nil
                )
                context.insert(snapshot)
                snapshots.append(snapshot)
            }
        }

        // Add one post-reset snapshot
        let postReset = UsageSnapshot(
            timestamp: now.addingTimeInterval(60),
            fiveHourPercent: 2,
            weeklyPercent: 3,
            fiveHourResetsAt: now.addingTimeInterval(18000),
            weeklyResetsAt: now.addingTimeInterval(604800)
        )
        context.insert(postReset)
        snapshots.append(postReset)

        return snapshots.sorted(by: { $0.timestamp < $1.timestamp })
    }
}
