import Foundation

struct PlanTier: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let monthlyPrice: Double
    let description: String
    let usageMultiplier: Double
}

struct TokenPricing: Codable, Identifiable, Equatable {
    var id: String { model }
    let model: String
    let displayName: String
    let inputPerMillion: Double
    let outputPerMillion: Double
}

struct PromoConfig: Codable, Equatable {
    let enabled: Bool
    let startUTC: String
    let endUTC: String
    let peakStartHourUTC: Int
    let peakEndHourUTC: Int
    let description: String
}

struct PricingData: Codable {
    let lastUpdated: String
    let plans: [PlanTier]
    let tokenPricing: [TokenPricing]
    let promo: PromoConfig?
}
