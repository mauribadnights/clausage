using Clausage.Models;
using Xunit;

namespace Clausage.Tests;

public class TimerFormatTests
{
    [Fact]
    public void Full_Format()
    {
        var fmt = TimerFormat.Full;
        Assert.Equal("1:32:42", fmt.Format(5562));
        Assert.Equal("0:00:00", fmt.Format(0));
        Assert.Equal("0:00:00", fmt.Format(-5));
        Assert.Equal("1:01:01", fmt.Format(3661));
    }

    [Fact]
    public void Compact_Format()
    {
        var fmt = TimerFormat.Compact;
        Assert.Equal("1:32", fmt.Format(5562));
        Assert.Equal("0:00", fmt.Format(0));
        Assert.Equal("2:00", fmt.Format(7200));
    }

    [Fact]
    public void Labeled_Format()
    {
        var fmt = TimerFormat.Labeled;
        Assert.Equal("1h 32m", fmt.Format(5562));
        Assert.Equal("0h 0m", fmt.Format(0));
        Assert.Equal("2h 0m", fmt.Format(7200));
    }

    [Fact]
    public void Minimal_Format()
    {
        var fmt = TimerFormat.Minimal;
        Assert.Equal("1h32m", fmt.Format(5562));
        Assert.Equal("0h0m", fmt.Format(0));
        Assert.Equal("1h01m", fmt.Format(3660));
    }

    [Fact]
    public void Days_Overflow()
    {
        double interval = 25 * 3600 + 1800;
        foreach (TimerFormat fmt in Enum.GetValues<TimerFormat>())
        {
            var result = fmt.Format(interval);
            Assert.StartsWith("1d ", result);
        }
    }

    [Fact]
    public void DisplayNames()
    {
        Assert.Equal("1:32:42", TimerFormat.Full.DisplayName());
        Assert.Equal("1:32", TimerFormat.Compact.DisplayName());
        Assert.Equal("1h 32m", TimerFormat.Labeled.DisplayName());
        Assert.Equal("1h32m", TimerFormat.Minimal.DisplayName());
    }

    [Fact]
    public void RoundTrip_SettingsString()
    {
        foreach (TimerFormat fmt in Enum.GetValues<TimerFormat>())
        {
            var str = fmt.ToSettingsString();
            var back = TimerFormatExtensions.FromSettingsString(str);
            Assert.Equal(fmt, back);
        }
    }
}
