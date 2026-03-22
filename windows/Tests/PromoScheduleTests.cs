using Clausage.Models;
using Xunit;

namespace Clausage.Tests;

public class PromoScheduleTests
{
    private static DateTime Utc(int year, int month, int day, int hour = 0, int minute = 0) =>
        new(year, month, day, hour, minute, 0, DateTimeKind.Utc);

    private static PromoSchedule MakeSchedule(
        string start = "2026-03-13T00:00:00Z",
        string end = "2026-03-28T06:59:59Z",
        int peakStart = 12, int peakEnd = 18)
    {
        var schedule = new PromoSchedule();
        schedule.Update(new PromoConfig(true, start, end, peakStart, peakEnd, "test"));
        return schedule;
    }

    [Fact]
    public void Disabled_When_No_Config()
    {
        var schedule = new PromoSchedule();
        Assert.Equal(PromoStatus.Disabled, schedule.CurrentStatus());
    }

    [Fact]
    public void Disabled_When_Config_Disabled()
    {
        var schedule = new PromoSchedule();
        schedule.Update(new PromoConfig(false, "", "", 12, 18, ""));
        Assert.Equal(PromoStatus.Disabled, schedule.CurrentStatus());
    }

    [Fact]
    public void Not_Started()
    {
        var schedule = MakeSchedule();
        Assert.Equal(PromoStatus.NotStarted, schedule.CurrentStatus(Utc(2026, 3, 12, 23)));
    }

    [Fact]
    public void Ended()
    {
        var schedule = MakeSchedule();
        Assert.Equal(PromoStatus.Ended, schedule.CurrentStatus(Utc(2026, 3, 29)));
    }

    [Fact]
    public void Active2x_OffPeak_Weekday()
    {
        var schedule = MakeSchedule();
        // Monday 2026-03-16, 8 AM UTC
        Assert.Equal(PromoStatus.Active2x, schedule.CurrentStatus(Utc(2026, 3, 16, 8)));
    }

    [Fact]
    public void Peak1x_Weekday()
    {
        var schedule = MakeSchedule();
        // Monday 2026-03-16, 14:00 UTC
        Assert.Equal(PromoStatus.Peak1x, schedule.CurrentStatus(Utc(2026, 3, 16, 14)));
    }

    [Fact]
    public void Active2x_Evening_Weekday()
    {
        var schedule = MakeSchedule();
        // Monday 2026-03-16, 20:00 UTC
        Assert.Equal(PromoStatus.Active2x, schedule.CurrentStatus(Utc(2026, 3, 16, 20)));
    }

    [Fact]
    public void Active2x_Weekend()
    {
        var schedule = MakeSchedule();
        // Saturday 2026-03-14, 14:00 UTC (peak hour but weekend)
        Assert.Equal(PromoStatus.Active2x, schedule.CurrentStatus(Utc(2026, 3, 14, 14)));
        // Sunday 2026-03-15, 10:00 UTC
        Assert.Equal(PromoStatus.Active2x, schedule.CurrentStatus(Utc(2026, 3, 15, 10)));
    }

    [Fact]
    public void NextTransition_From_NotStarted()
    {
        var schedule = MakeSchedule();
        var t = schedule.NextTransition(Utc(2026, 3, 12, 23));
        Assert.NotNull(t);
        Assert.Equal(PromoStatus.Active2x, t!.Value.NextStatus);
    }

    [Fact]
    public void NextTransition_From_2x_To_Peak()
    {
        var schedule = MakeSchedule();
        // Monday morning -> peak at 12:00
        var t = schedule.NextTransition(Utc(2026, 3, 16, 8));
        Assert.NotNull(t);
        Assert.Equal(PromoStatus.Peak1x, t!.Value.NextStatus);
        Assert.Equal(12, t.Value.Date.Hour);
    }

    [Fact]
    public void NextTransition_From_Peak_To_2x()
    {
        var schedule = MakeSchedule();
        // During peak -> 2x at 18:00
        var t = schedule.NextTransition(Utc(2026, 3, 16, 14));
        Assert.NotNull(t);
        Assert.Equal(PromoStatus.Active2x, t!.Value.NextStatus);
        Assert.Equal(18, t.Value.Date.Hour);
    }

    [Fact]
    public void NextTransition_From_Weekend_To_Monday_Peak()
    {
        var schedule = MakeSchedule();
        var t = schedule.NextTransition(Utc(2026, 3, 14, 10));
        Assert.NotNull(t);
        Assert.Equal(PromoStatus.Peak1x, t!.Value.NextStatus);
        Assert.Equal(DayOfWeek.Monday, t.Value.Date.DayOfWeek);
    }

    [Fact]
    public void NextTransition_Ended()
    {
        var schedule = MakeSchedule();
        Assert.Null(schedule.NextTransition(Utc(2026, 3, 29)));
    }

    [Fact]
    public void PeakHoursLocalString_Contains_Dash()
    {
        var schedule = MakeSchedule();
        Assert.Contains("-", schedule.PeakHoursLocalString());
    }

    [Fact]
    public void PromoEndLocalString_Contains_Year()
    {
        var schedule = MakeSchedule();
        Assert.Contains("2026", schedule.PromoEndLocalString());
    }
}
