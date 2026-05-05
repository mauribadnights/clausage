using Clausage.Models;
using Clausage.Services;

namespace Clausage.Tray;

public class AppState
{
    public PromoStatus Status { get; private set; } = PromoStatus.Disabled;
    public string CountdownText { get; private set; } = "";
    public string StatusDescription { get; private set; } = "";
    public string NextTransitionDescription { get; private set; } = "";
    public double? UsageFiveHour { get; private set; }
    public double? UsageWeekly { get; private set; }

    private System.Threading.Timer? _timer;
    private System.Threading.Timer? _usageTimer;

    public AppState()
    {
        Update();
        _timer = new System.Threading.Timer(_ => Update(), null,
            TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(1));
    }

    public void BindUsage(UsageService service)
    {
        _usageTimer = new System.Threading.Timer(_ =>
        {
            UsageFiveHour = service.Usage.FiveHourPercent;
            UsageWeekly = service.Usage.WeeklyPercent;
        }, null, TimeSpan.FromSeconds(2), TimeSpan.FromSeconds(2));
    }

    public void Update()
    {
        var settings = AppSettings.Shared;
        var fmt = settings.GetTimerFormat();
        Status = PromoSchedule.Shared.CurrentStatus();

        bool showTimer = settings.ShowPromoTimer &&
            Status != PromoStatus.Ended && Status != PromoStatus.Disabled;

        if (showTimer)
            UpdatePromoState(fmt);
        else
        {
            StatusDescription = "Claude Usage";
            CountdownText = "";
            NextTransitionDescription = "";
        }
    }

    private void UpdatePromoState(TimerFormat fmt)
    {
        var schedule = PromoSchedule.Shared;
        var now = DateTime.UtcNow;

        switch (Status)
        {
            case PromoStatus.NotStarted:
                var interval = (schedule.PromoStart - now).TotalSeconds;
                var formatted = fmt.Format(interval);
                StatusDescription = "Promo hasn't started yet";
                CountdownText = $"Starts in {formatted}";
                NextTransitionDescription = "2x usage begins when promo starts";
                break;

            case PromoStatus.Active2x:
                var transition = schedule.NextTransition(now);
                if (transition.HasValue)
                {
                    var secs = (transition.Value.Date - now).TotalSeconds;
                    formatted = fmt.Format(secs);
                    CountdownText = formatted;
                    NextTransitionDescription = transition.Value.NextStatus == PromoStatus.Peak1x
                        ? $"Peak hours (1x) in {formatted}"
                        : $"Promo ends in {formatted}";
                }
                else CountdownText = "";
                StatusDescription = "2x Usage Active";
                break;

            case PromoStatus.Peak1x:
                transition = schedule.NextTransition(now);
                if (transition.HasValue)
                {
                    var secs = (transition.Value.Date - now).TotalSeconds;
                    formatted = fmt.Format(secs);
                    CountdownText = formatted;
                    NextTransitionDescription = $"2x returns in {formatted}";
                }
                else CountdownText = "";
                StatusDescription = "Peak Hours (1x)";
                break;

            case PromoStatus.Ended:
                StatusDescription = "Promo has ended";
                CountdownText = "";
                NextTransitionDescription = "";
                break;
        }
    }

    public void Stop()
    {
        _timer?.Dispose();
        _usageTimer?.Dispose();
    }
}
