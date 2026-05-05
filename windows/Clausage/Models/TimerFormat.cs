namespace Clausage.Models;

public enum TimerFormat
{
    Full,     // 1:32:42
    Compact,  // 1:32
    Labeled,  // 1h 32m
    Minimal   // 1h32m
}

public static class TimerFormatExtensions
{
    public static string DisplayName(this TimerFormat fmt) => fmt switch
    {
        TimerFormat.Full => "1:32:42",
        TimerFormat.Compact => "1:32",
        TimerFormat.Labeled => "1h 32m",
        TimerFormat.Minimal => "1h32m",
        _ => "1:32:42"
    };

    public static string Format(this TimerFormat fmt, double interval)
    {
        if (interval <= 0)
            return fmt switch
            {
                TimerFormat.Full => "0:00:00",
                TimerFormat.Compact => "0:00",
                TimerFormat.Labeled => "0h 0m",
                TimerFormat.Minimal => "0h0m",
                _ => "0:00:00"
            };

        int totalSeconds = (int)interval;
        int hours = totalSeconds / 3600;
        int minutes = (totalSeconds % 3600) / 60;
        int seconds = totalSeconds % 60;

        if (hours > 24)
        {
            int days = hours / 24;
            int remainingHours = hours % 24;
            return $"{days}d {remainingHours}h";
        }

        return fmt switch
        {
            TimerFormat.Full => $"{hours}:{minutes:D2}:{seconds:D2}",
            TimerFormat.Compact => $"{hours}:{minutes:D2}",
            TimerFormat.Labeled => $"{hours}h {minutes}m",
            TimerFormat.Minimal => $"{hours}h{minutes:D2}m",
            _ => $"{hours}:{minutes:D2}:{seconds:D2}"
        };
    }

    public static string ToSettingsString(this TimerFormat fmt) => fmt switch
    {
        TimerFormat.Full => "full",
        TimerFormat.Compact => "compact",
        TimerFormat.Labeled => "labeled",
        TimerFormat.Minimal => "minimal",
        _ => "full"
    };

    public static TimerFormat FromSettingsString(string s) => s switch
    {
        "full" => TimerFormat.Full,
        "compact" => TimerFormat.Compact,
        "labeled" => TimerFormat.Labeled,
        "minimal" => TimerFormat.Minimal,
        _ => TimerFormat.Full
    };
}
