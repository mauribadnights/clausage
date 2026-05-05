namespace Clausage.Models;

public record PlanTier(
    string Id,
    string Name,
    double MonthlyPrice,
    string Description,
    double UsageMultiplier
);

public record TokenPricing(
    string Model,
    string DisplayName,
    double InputPerMillion,
    double OutputPerMillion
);

public record PromoConfig(
    bool Enabled,
    string StartUtc,
    string EndUtc,
    int PeakStartHourUtc,
    int PeakEndHourUtc,
    string Description
);

public record PricingData(
    string LastUpdated,
    List<PlanTier> Plans,
    List<TokenPricing> TokenPricing,
    PromoConfig? Promo
);
