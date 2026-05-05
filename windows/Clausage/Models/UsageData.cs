namespace Clausage.Models;

public class UsageData
{
    public double? FiveHourPercent { get; set; }
    public DateTime? FiveHourResetsAt { get; set; }
    public double? WeeklyPercent { get; set; }
    public DateTime? WeeklyResetsAt { get; set; }
    public DateTime? LastUpdated { get; set; }
    public string? Error { get; set; }
    public bool IsStale { get; set; }
}
