using Clausage.Services;
using Xunit;

namespace Clausage.Tests;

public class UsageServiceTests
{
    [Fact]
    public void ParseResponse_Normal()
    {
        var json = """
        {
            "five_hour": { "utilization": 56.3, "resets_at": "2026-03-22T15:00:00.000Z" },
            "seven_day": { "utilization": 42.1, "resets_at": "2026-03-25T00:00:00.000Z" }
        }
        """;
        var result = UsageService.ParseResponse(json);
        Assert.Null(result.Error);
        Assert.NotNull(result.FiveHourPercent);
        Assert.Equal(56.3, result.FiveHourPercent!.Value, 1);
        Assert.NotNull(result.WeeklyPercent);
        Assert.Equal(42.1, result.WeeklyPercent!.Value, 1);
        Assert.NotNull(result.FiveHourResetsAt);
        Assert.NotNull(result.WeeklyResetsAt);
    }

    [Fact]
    public void ParseResponse_Integer_Utilization()
    {
        var json = """{ "five_hour": { "utilization": 100 }, "seven_day": { "utilization": 0 } }""";
        var result = UsageService.ParseResponse(json);
        Assert.Equal(100.0, result.FiveHourPercent);
        Assert.Equal(0.0, result.WeeklyPercent);
    }

    [Fact]
    public void ParseResponse_String_Utilization()
    {
        var json = """{ "five_hour": { "utilization": "75.5" }, "seven_day": { "utilization": "30" } }""";
        var result = UsageService.ParseResponse(json);
        Assert.Equal(75.5, result.FiveHourPercent!.Value, 1);
        Assert.Equal(30.0, result.WeeklyPercent!.Value, 1);
    }

    [Fact]
    public void ParseResponse_Error()
    {
        var json = """{ "error": { "message": "Unauthorized" } }""";
        var result = UsageService.ParseResponse(json);
        Assert.Equal("Unauthorized", result.Error);
    }

    [Fact]
    public void ParseResponse_Empty()
    {
        var result = UsageService.ParseResponse("{}");
        Assert.NotNull(result.Error);
        Assert.Contains("Unexpected", result.Error);
    }

    [Fact]
    public void ParseResponse_Partial()
    {
        var json = """{ "five_hour": { "utilization": 45.0 } }""";
        var result = UsageService.ParseResponse(json);
        Assert.Equal(45.0, result.FiveHourPercent!.Value, 1);
        Assert.Null(result.WeeklyPercent);
        Assert.Null(result.Error);
    }

    [Fact]
    public void ResetTimeString_Null() =>
        Assert.Equal("\u2014", UsageService.ResetTimeString(null));

    [Fact]
    public void ResetTimeString_Past() =>
        Assert.Equal("now", UsageService.ResetTimeString(DateTime.UtcNow.AddHours(-1)));

    [Fact]
    public void ResetTimeString_Minutes()
    {
        var result = UsageService.ResetTimeString(DateTime.UtcNow.AddMinutes(30).AddSeconds(30));
        Assert.StartsWith("in ", result);
        Assert.Contains("m", result);
    }

    [Fact]
    public void ResetTimeString_Hours()
    {
        var result = UsageService.ResetTimeString(DateTime.UtcNow.AddHours(2).AddMinutes(15).AddSeconds(30));
        Assert.Contains("2h", result);
    }

    [Fact]
    public void ResetTimeString_Days()
    {
        var result = UsageService.ResetTimeString(DateTime.UtcNow.AddDays(3).AddHours(5).AddSeconds(30));
        Assert.Contains("3d", result);
    }
}
