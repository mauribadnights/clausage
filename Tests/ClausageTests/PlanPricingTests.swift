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

    // MARK: - Plan analysis

    func testInsufficientDataReturnsEmptyProjections() {
        let service = makeService()
        let snapshots = makeSnapshots(count: 5, fiveHour: 50, weekly: 50)
        let result = service.analyzePlans(snapshots: snapshots, currentPlanId: "pro")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.projections.isEmpty)
        XCTAssertTrue(result!.insight.contains("Need more"))
    }

    func testAnalysisReturnsProjectionPerPlan() {
        let service = makeService()
        let snapshots = makeSnapshots(count: 20, fiveHour: 50, weekly: 40)
        let result = service.analyzePlans(snapshots: snapshots, currentPlanId: "pro")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.projections.count, 4, "Should have one projection per plan")
    }

    func testHigherPlanReducesProjectedUtilization() {
        let service = makeService()
        let snapshots = makeSnapshots(count: 20, fiveHour: 80, weekly: 60)
        let result = service.analyzePlans(snapshots: snapshots, currentPlanId: "pro")!

        let proProjAvg = result.projections.first(where: { $0.plan.id == "pro" })!.projectedAvg5h
        let maxProjAvg = result.projections.first(where: { $0.plan.id == "max_5x" })!.projectedAvg5h

        XCTAssertGreaterThan(proProjAvg, maxProjAvg, "Higher plan should have lower projected utilization")
    }

    func testLowerPlanIncreasesProjectedUtilization() {
        let service = makeService()
        let snapshots = makeSnapshots(count: 20, fiveHour: 50, weekly: 30)
        let result = service.analyzePlans(snapshots: snapshots, currentPlanId: "pro")!

        let proProjAvg = result.projections.first(where: { $0.plan.id == "pro" })!.projectedAvg5h
        let freeProjAvg = result.projections.first(where: { $0.plan.id == "free" })!.projectedAvg5h

        XCTAssertLessThan(proProjAvg, freeProjAvg, "Lower plan should have higher projected utilization")
    }

    func testHeavyUserShowsLimitHits() {
        let service = makeService()
        let snapshots = makeSnapshots(count: 20, fiveHour: 97, weekly: 85)
        let result = service.analyzePlans(snapshots: snapshots, currentPlanId: "pro")!

        let proProj = result.projections.first(where: { $0.plan.id == "pro" })!
        XCTAssertGreaterThan(proProj.pctTimeAt5hLimit, 0, "Heavy user should show time at limit")
    }

    func testLightUserHasHeadroom() {
        let service = makeService()
        let snapshots = makeSnapshots(count: 20, fiveHour: 10, weekly: 8)
        let result = service.analyzePlans(snapshots: snapshots, currentPlanId: "pro")!

        let proProj = result.projections.first(where: { $0.plan.id == "pro" })!
        XCTAssertGreaterThan(proProj.headroom, 50, "Light user should have plenty of headroom")
        XCTAssertEqual(proProj.pctTimeAt5hLimit, 0, "Light user should never hit limit")
    }

    func testInsightContainsUsageInfo() {
        let service = makeService()
        let snapshots = makeSnapshots(count: 20, fiveHour: 60, weekly: 40)
        let result = service.analyzePlans(snapshots: snapshots, currentPlanId: "pro")!
        XCTAssertFalse(result.insight.isEmpty)
        XCTAssertTrue(result.insight.contains("Pro"), "Insight should mention current plan")
    }

    func testUnknownPlanReturnsNil() {
        let service = makeService()
        let snapshots = makeSnapshots(count: 20, fiveHour: 50, weekly: 50)
        let result = service.analyzePlans(snapshots: snapshots, currentPlanId: "nonexistent")
        XCTAssertNil(result)
    }

    func testProjectionsHaveUniqueIds() {
        let service = makeService()
        let snapshots = makeSnapshots(count: 20, fiveHour: 50, weekly: 50)
        let result = service.analyzePlans(snapshots: snapshots, currentPlanId: "pro")!
        let ids = result.projections.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Projection IDs should be unique")
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

    @MainActor
    private func makeSnapshots(count: Int, fiveHour: Double, weekly: Double) -> [UsageSnapshot] {
        let context = container.mainContext
        return (0..<count).map { i in
            let snapshot = UsageSnapshot(
                timestamp: Date().addingTimeInterval(Double(-i) * 300),
                fiveHourPercent: fiveHour + Double.random(in: -3...3),
                weeklyPercent: weekly + Double.random(in: -3...3)
            )
            context.insert(snapshot)
            return snapshot
        }
    }
}
