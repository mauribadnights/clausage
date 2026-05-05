namespace Clausage.Models;

public enum PromoStatus
{
    NotStarted,
    Active2x,
    Peak1x,
    Ended,
    Disabled
}

public class PromoSchedule
{
    private static PromoSchedule? _instance;
    private static readonly object _lock = new();

    public DateTime PromoStart { get; private set; } = DateTime.MinValue;
    public DateTime PromoEnd { get; private set; } = DateTime.MinValue;
    public int PeakStartHour { get; private set; } = 12;
    public int PeakEndHour { get; private set; } = 18;
    public bool Enabled { get; private set; }

    public static PromoSchedule Shared
    {
        get
        {
            if (_instance == null)
            {
                lock (_lock)
                {
                    _instance ??= new PromoSchedule();
                }
            }
            return _instance;
        }
    }

    // For testing — allow creating non-singleton instances
    public PromoSchedule() { }

    public void Update(PromoConfig? config)
    {
        if (config == null || !config.Enabled)
        {
            Enabled = false;
            return;
        }

        if (!DateTime.TryParse(config.StartUtc, null, System.Globalization.DateTimeStyles.RoundtripKind, out var start) ||
            !DateTime.TryParse(config.EndUtc, null, System.Globalization.DateTimeStyles.RoundtripKind, out var end))
        {
            Enabled = false;
            return;
        }

        PromoStart = start.ToUniversalTime();
        PromoEnd = end.ToUniversalTime();
        PeakStartHour = config.PeakStartHourUtc;
        PeakEndHour = config.PeakEndHourUtc;
        Enabled = true;
    }

    public PromoStatus CurrentStatus(DateTime? at = null)
    {
        if (!Enabled) return PromoStatus.Disabled;

        var now = at?.ToUniversalTime() ?? DateTime.UtcNow;
        if (now < PromoStart) return PromoStatus.NotStarted;
        if (now > PromoEnd) return PromoStatus.Ended;

        var weekday = now.DayOfWeek;
        if (weekday == DayOfWeek.Saturday || weekday == DayOfWeek.Sunday)
            return PromoStatus.Active2x;

        if (now.Hour >= PeakStartHour && now.Hour < PeakEndHour)
            return PromoStatus.Peak1x;

        return PromoStatus.Active2x;
    }

    public (DateTime Date, PromoStatus NextStatus)? NextTransition(DateTime? from = null)
    {
        var now = from?.ToUniversalTime() ?? DateTime.UtcNow;
        var status = CurrentStatus(now);

        return status switch
        {
            PromoStatus.Disabled => null,
            PromoStatus.NotStarted => (PromoStart, PromoStatus.Active2x),
            PromoStatus.Ended => null,
            PromoStatus.Active2x => NextFrom2x(now),
            PromoStatus.Peak1x => NextFromPeak(now),
            _ => null
        };
    }

    private (DateTime, PromoStatus) NextFrom2x(DateTime now)
    {
        var weekday = now.DayOfWeek;

        if (weekday == DayOfWeek.Saturday || weekday == DayOfWeek.Sunday)
        {
            int daysUntilMonday = weekday == DayOfWeek.Saturday ? 2 : 1;
            var nextMonday = now.Date.AddDays(daysUntilMonday).AddHours(PeakStartHour);
            return nextMonday > PromoEnd ? (PromoEnd, PromoStatus.Ended) : (nextMonday, PromoStatus.Peak1x);
        }

        if (now.Hour < PeakStartHour)
        {
            var peakToday = now.Date.AddHours(PeakStartHour);
            if (peakToday <= now) peakToday = peakToday.AddSeconds(1);
            return peakToday > PromoEnd ? (PromoEnd, PromoStatus.Ended) : (peakToday, PromoStatus.Peak1x);
        }

        // After peak on weekday (evening 2x)
        var tomorrow = now.Date.AddDays(1);
        var tomorrowWeekday = tomorrow.DayOfWeek;

        if (tomorrowWeekday == DayOfWeek.Saturday || tomorrowWeekday == DayOfWeek.Sunday)
        {
            int daysToMonday = tomorrowWeekday == DayOfWeek.Saturday ? 2 : 1;
            var nextMonday = tomorrow.AddDays(daysToMonday).AddHours(PeakStartHour);
            return nextMonday > PromoEnd ? (PromoEnd, PromoStatus.Ended) : (nextMonday, PromoStatus.Peak1x);
        }

        var peakTomorrow = tomorrow.AddHours(PeakStartHour);
        return peakTomorrow > PromoEnd ? (PromoEnd, PromoStatus.Ended) : (peakTomorrow, PromoStatus.Peak1x);
    }

    private (DateTime, PromoStatus) NextFromPeak(DateTime now)
    {
        var peakEnd = now.Date.AddHours(PeakEndHour);
        if (peakEnd <= now) peakEnd = peakEnd.AddSeconds(1);
        return peakEnd > PromoEnd ? (PromoEnd, PromoStatus.Ended) : (peakEnd, PromoStatus.Active2x);
    }

    public string PeakHoursLocalString()
    {
        var today = DateTime.UtcNow.Date;
        var startUtc = today.AddHours(PeakStartHour);
        var endUtc = today.AddHours(PeakEndHour);
        var startLocal = startUtc.ToLocalTime();
        var endLocal = endUtc.ToLocalTime();
        var tz = TimeZoneInfo.Local.StandardName;
        return $"{startLocal:h:mm tt} - {endLocal:h:mm tt} {tz}";
    }

    public string PromoEndLocalString()
    {
        return PromoEnd.ToLocalTime().ToString("MMM dd, yyyy h:mm tt");
    }
}
