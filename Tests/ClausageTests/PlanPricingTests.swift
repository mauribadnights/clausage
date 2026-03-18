import XCTest
@testable import Clausage

final class PlanPricingTests: XCTestCase {

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

    // MARK: - Plan recommendation logic

    func testInsufficientDataRecommendation() {
        let service = makeService()
        let snapshots = makeSnapshots(count: 5, fiveHour: 50, weekly: 50)
        let result = service.analyzeUsage(snapshots: snapshots, currentPlanId: "pro")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.recommendation, .insufficientData)
    }

    func testUpgradeRecommendationWhenHittingLimits() {
        let service = makeService()
        // Snapshots where usage is consistently at the limit
        let snapshots = makeSnapshots(count: 20, fiveHour: 97, weekly: 85)
        let result = service.analyzeUsage(snapshots: snapshots, currentPlanId: "pro")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.recommendation, .upgrade)
    }

    func testDowngradeRecommendationWhenBarelyUsing() {
        let service = makeService()
        // Snapshots where usage is very low
        let snapshots = makeSnapshots(count: 20, fiveHour: 10, weekly: 8)
        let result = service.analyzeUsage(snapshots: snapshots, currentPlanId: "pro")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.recommendation, .downgrade)
    }

    func testStayPutRecommendation() {
        let service = makeService()
        // Moderate usage — fits well
        let snapshots = makeSnapshots(count: 20, fiveHour: 45, weekly: 40)
        let result = service.analyzeUsage(snapshots: snapshots, currentPlanId: "pro")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.recommendation, .stayPut)
    }

    func testNoUpgradeFromHighestPlan() {
        let service = makeService()
        let snapshots = makeSnapshots(count: 20, fiveHour: 97, weekly: 85)
        let result = service.analyzeUsage(snapshots: snapshots, currentPlanId: "max_20x")
        XCTAssertNotNil(result)
        // Highest plan can't upgrade — should stay put
        XCTAssertEqual(result?.recommendation, .stayPut)
    }

    func testNoDowngradeFromFreePlan() {
        let service = makeService()
        let snapshots = makeSnapshots(count: 20, fiveHour: 10, weekly: 8)
        let result = service.analyzeUsage(snapshots: snapshots, currentPlanId: "free")
        XCTAssertNotNil(result)
        // Free plan can't downgrade — should stay put
        XCTAssertEqual(result?.recommendation, .stayPut)
    }

    func testRecommendationIncludesStats() {
        let service = makeService()
        let snapshots = makeSnapshots(count: 20, fiveHour: 50, weekly: 50)
        let result = service.analyzeUsage(snapshots: snapshots, currentPlanId: "pro")
        XCTAssertNotNil(result?.avgFiveHourUsage)
        XCTAssertNotNil(result?.avgWeeklyUsage)
        XCTAssertFalse(result?.reasoning.isEmpty ?? true)
    }

    func testRecommendationWithUnknownPlanReturnsNil() {
        let service = makeService()
        let snapshots = makeSnapshots(count: 20, fiveHour: 50, weekly: 50)
        let result = service.analyzeUsage(snapshots: snapshots, currentPlanId: "nonexistent_plan")
        XCTAssertNil(result)
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
            ]
        )
    }

    private func loadBundledPricing() throws -> PricingData {
        guard let url = Bundle.module.url(forResource: "pricing", withExtension: "json") else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "pricing.json not found"])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PricingData.self, from: data)
    }

    private func makeSnapshots(count: Int, fiveHour: Double, weekly: Double) -> [UsageSnapshot] {
        (0..<count).map { i in
            UsageSnapshot(
                timestamp: Date().addingTimeInterval(Double(-i) * 300),
                fiveHourPercent: fiveHour + Double.random(in: -3...3),
                weeklyPercent: weekly + Double.random(in: -3...3)
            )
        }
    }
}
