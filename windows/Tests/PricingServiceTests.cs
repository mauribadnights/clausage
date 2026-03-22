using Clausage.Services;
using Xunit;

namespace Clausage.Tests;

public class PricingServiceTests
{
    [Fact]
    public void Decode_Valid()
    {
        var json = """
        {
            "lastUpdated": "2026-03-18",
            "plans": [{ "id": "pro", "name": "Pro", "monthlyPrice": 20, "description": "desc", "usageMultiplier": 5.0 }],
            "tokenPricing": [{ "model": "sonnet", "displayName": "Sonnet", "inputPerMillion": 3.0, "outputPerMillion": 15.0 }],
            "promo": { "enabled": true, "startUTC": "2026-03-13T00:00:00Z", "endUTC": "2026-03-28T06:59:59Z", "peakStartHourUTC": 12, "peakEndHourUTC": 18, "description": "2x" }
        }
        """;
        var result = PricingService.Decode(json);
        Assert.NotNull(result);
        Assert.Single(result!.Plans);
        Assert.Equal("pro", result.Plans[0].Id);
        Assert.Equal(20, result.Plans[0].MonthlyPrice);
        Assert.Single(result.TokenPricing);
        Assert.NotNull(result.Promo);
        Assert.True(result.Promo!.Enabled);
    }

    [Fact]
    public void Decode_NoPromo()
    {
        var json = """{ "lastUpdated": "2026-03-18", "plans": [], "tokenPricing": [] }""";
        var result = PricingService.Decode(json);
        Assert.NotNull(result);
        Assert.Null(result!.Promo);
    }

    [Fact]
    public void Decode_Invalid() =>
        Assert.Null(PricingService.Decode("not json"));

    [Fact]
    public void Decode_MissingKeys()
    {
        var json = """{ "plans": [{ "id": "x" }], "tokenPricing": [] }""";
        Assert.Null(PricingService.Decode(json));
    }
}
