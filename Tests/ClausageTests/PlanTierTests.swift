import XCTest
@testable import Clausage

final class PlanTierTests: XCTestCase {

    func testPlanTierCodable() throws {
        let plan = PlanTier(
            id: "test",
            name: "Test Plan",
            monthlyPrice: 42,
            description: "A test plan",
            usageMultiplier: 10.0
        )

        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(PlanTier.self, from: data)

        XCTAssertEqual(plan, decoded)
    }

    func testTokenPricingCodable() throws {
        let pricing = TokenPricing(
            model: "claude-test",
            displayName: "Claude Test",
            inputPerMillion: 5.0,
            outputPerMillion: 25.0
        )

        let data = try JSONEncoder().encode(pricing)
        let decoded = try JSONDecoder().decode(TokenPricing.self, from: data)

        XCTAssertEqual(pricing, decoded)
    }

    func testPricingDataCodable() throws {
        let pricing = PricingData(
            lastUpdated: "2026-03-18",
            plans: [
                PlanTier(id: "free", name: "Free", monthlyPrice: 0, description: "Free", usageMultiplier: 1.0),
                PlanTier(id: "pro", name: "Pro", monthlyPrice: 20, description: "Pro", usageMultiplier: 5.0)
            ],
            tokenPricing: [
                TokenPricing(model: "opus", displayName: "Opus", inputPerMillion: 5, outputPerMillion: 25)
            ]
        )

        let data = try JSONEncoder().encode(pricing)
        let decoded = try JSONDecoder().decode(PricingData.self, from: data)

        XCTAssertEqual(decoded.plans.count, 2)
        XCTAssertEqual(decoded.tokenPricing.count, 1)
        XCTAssertEqual(decoded.lastUpdated, "2026-03-18")
    }

    func testPlanTierIdentifiable() {
        let plan = PlanTier(id: "test", name: "Test", monthlyPrice: 0, description: "", usageMultiplier: 1)
        XCTAssertEqual(plan.id, "test")
    }

    func testTokenPricingIdentifiable() {
        let pricing = TokenPricing(model: "opus", displayName: "Opus", inputPerMillion: 5, outputPerMillion: 25)
        XCTAssertEqual(pricing.id, "opus")
    }
}
