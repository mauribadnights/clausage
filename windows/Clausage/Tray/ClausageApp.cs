using System.Drawing;
using System.Windows.Forms;
using Clausage.Models;
using Clausage.Services;
using Microsoft.Win32;

namespace Clausage.Tray;

public class ClausageApp : ApplicationContext
{
    public const string Version = "0.1.0";
    private const string StartupRegistryKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";
    private const string StartupValueName = "Clausage";

    private readonly AppSettings _settings;
    private readonly PricingService _pricingService;
    private readonly UsageService _usageService;
    private readonly AppState _appState;

    private readonly NotifyIcon _primaryIcon;
    private NotifyIcon? _secondaryIcon;
    private System.Threading.Timer? _updateTimer;
    private int? _lastPrimaryValue;
    private int? _lastSecondaryValue;
    private Color _lastPrimaryColor;
    private Color _lastSecondaryColor;

    public ClausageApp()
    {
        _settings = AppSettings.Shared;
        _pricingService = new PricingService();
        _usageService = new UsageService();
        _appState = new AppState();
        _appState.BindUsage(_usageService);

        var blank = IconRenderer.RenderNumberIcon(null, IconRenderer.ColorGray, _settings.IconSize);

        _primaryIcon = new NotifyIcon
        {
            Icon = blank,
            Text = "Clausage: loading...",
            Visible = true,
        };
        _primaryIcon.MouseClick += OnPrimaryClick;

        if (_settings.DisplayMode == "both")
            CreateSecondaryIcon();

        _updateTimer = new System.Threading.Timer(_ =>
        {
            try { UpdateIcons(); }
            catch { }
        }, null, TimeSpan.FromMilliseconds(500), TimeSpan.FromSeconds(2));
    }

    private void CreateSecondaryIcon()
    {
        if (_secondaryIcon != null) return;
        var blank = IconRenderer.RenderNumberIcon(null, IconRenderer.ColorGray, _settings.IconSize);
        _secondaryIcon = new NotifyIcon
        {
            Icon = blank,
            Text = "Clausage: loading...",
            Visible = true,
        };
    }

    private void RemoveSecondaryIcon()
    {
        if (_secondaryIcon == null) return;
        _secondaryIcon.Visible = false;
        _secondaryIcon.Dispose();
        _secondaryIcon = null;
        _lastSecondaryValue = -999; // force re-render next time
    }

    private void OnPrimaryClick(object? sender, MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Left || e.Button == MouseButtons.Right)
        {
            var menu = BuildContextMenu();
            // Use reflection to show context menu at cursor position
            var mi = typeof(NotifyIcon).GetMethod("ShowContextMenu",
                System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic);
            _primaryIcon.ContextMenuStrip = menu;
            mi?.Invoke(_primaryIcon, null);
        }
    }

    private void UpdateIcons()
    {
        var usage = _usageService.Usage;
        int size = _settings.IconSize;
        string mode = _settings.DisplayMode;

        // Primary icon
        double? pct = mode == "weekly" ? usage.WeeklyPercent : usage.FiveHourPercent;
        int? val = pct.HasValue ? (int)pct.Value : null;
        var color = IconRenderer.UsageColor(pct);

        if (val != _lastPrimaryValue || color != _lastPrimaryColor)
        {
            var oldIcon = _primaryIcon.Icon;
            _primaryIcon.Icon = IconRenderer.RenderNumberIcon(val, color, size);
            _lastPrimaryValue = val;
            _lastPrimaryColor = color;
            if (oldIcon != null) DestroyIcon(oldIcon);
        }
        _primaryIcon.Text = BuildTooltip(usage);

        // Secondary icon (only in "both" mode)
        if (_secondaryIcon != null)
        {
            double? pctWk = usage.WeeklyPercent;
            int? valWk = pctWk.HasValue ? (int)pctWk.Value : null;
            var colorWk = IconRenderer.UsageColor(pctWk);

            if (valWk != _lastSecondaryValue || colorWk != _lastSecondaryColor)
            {
                var oldIcon = _secondaryIcon.Icon;
                _secondaryIcon.Icon = IconRenderer.RenderNumberIcon(valWk, colorWk, size);
                _lastSecondaryValue = valWk;
                _lastSecondaryColor = colorWk;
                if (oldIcon != null) DestroyIcon(oldIcon);
            }

            var wkPct = pctWk.HasValue ? $"{(int)pctWk}%" : "--";
            var wkReset = UsageService.ResetTimeString(usage.WeeklyResetsAt);
            _secondaryIcon.Text = $"Weekly: {wkPct} (resets {wkReset})";
        }
    }

    private static void DestroyIcon(Icon icon)
    {
        try { NativeMethods.DestroyIcon(icon.Handle); }
        catch { }
    }

    private string BuildTooltip(UsageData usage)
    {
        string mode = _settings.DisplayMode;
        string line1, other = "";

        if (mode == "weekly")
        {
            var pct = usage.WeeklyPercent.HasValue ? $"{(int)usage.WeeklyPercent}%" : "--";
            var reset = UsageService.ResetTimeString(usage.WeeklyResetsAt);
            line1 = $"Weekly: {pct} (resets {reset})";

            if (usage.FiveHourPercent.HasValue)
            {
                var fhReset = UsageService.ResetTimeString(usage.FiveHourResetsAt);
                other = $"\n5h: {(int)usage.FiveHourPercent}% (resets {fhReset})";
            }
        }
        else
        {
            var pct = usage.FiveHourPercent.HasValue ? $"{(int)usage.FiveHourPercent}%" : "--";
            var reset = UsageService.ResetTimeString(usage.FiveHourResetsAt);
            line1 = $"5h: {pct} (resets {reset})";

            if (mode == "5hour" && usage.WeeklyPercent.HasValue)
            {
                var wkReset = UsageService.ResetTimeString(usage.WeeklyResetsAt);
                other = $"\nWeekly: {(int)usage.WeeklyPercent}% (resets {wkReset})";
            }
        }

        var promo = "";
        if (!string.IsNullOrEmpty(_appState.CountdownText))
            promo = $"\n{_appState.StatusDescription}: {_appState.CountdownText}";

        // Windows tooltip max is 128 chars
        var full = $"{line1}{other}{promo}";
        return full.Length > 127 ? full[..127] : full;
    }

    private ContextMenuStrip BuildContextMenu()
    {
        var menu = new ContextMenuStrip();
        var usage = _usageService.Usage;
        var schedule = PromoSchedule.Shared;

        // Header
        menu.Items.Add(new ToolStripMenuItem($"Clausage v{Version}") { Enabled = false });
        menu.Items.Add(new ToolStripSeparator());

        // Usage
        var pct5h = usage.FiveHourPercent.HasValue ? $"{(int)usage.FiveHourPercent}%" : "--";
        var pctWk = usage.WeeklyPercent.HasValue ? $"{(int)usage.WeeklyPercent}%" : "--";
        var reset5h = UsageService.ResetTimeString(usage.FiveHourResetsAt);
        var resetWk = UsageService.ResetTimeString(usage.WeeklyResetsAt);

        menu.Items.Add(new ToolStripMenuItem($"5-hour:  {pct5h}  (resets {reset5h})") { Enabled = false });
        menu.Items.Add(new ToolStripMenuItem($"Weekly:  {pctWk}  (resets {resetWk})") { Enabled = false });

        if (usage.Error != null)
            menu.Items.Add(new ToolStripMenuItem($"Error: {usage.Error}") { Enabled = false });

        if (usage.LastUpdated.HasValue)
        {
            var ago = TimeAgo(usage.LastUpdated.Value);
            var label = usage.IsStale ? $"Last updated {ago} (cached)" : $"Updated {ago}";
            menu.Items.Add(new ToolStripMenuItem(label) { Enabled = false });
        }

        menu.Items.Add(new ToolStripSeparator());

        // Promo status
        if (schedule.Enabled)
        {
            var statusLabel = _appState.Status switch
            {
                PromoStatus.NotStarted => "Promo: Not started",
                PromoStatus.Active2x => "Promo: 2x Active",
                PromoStatus.Peak1x => "Promo: Peak (1x)",
                PromoStatus.Ended => "Promo: Ended",
                _ => "Promo"
            };
            menu.Items.Add(new ToolStripMenuItem(statusLabel) { Enabled = false });

            if (!string.IsNullOrEmpty(_appState.NextTransitionDescription))
                menu.Items.Add(new ToolStripMenuItem($"  {_appState.NextTransitionDescription}") { Enabled = false });

            var peakStr = schedule.PeakHoursLocalString();
            menu.Items.Add(new ToolStripMenuItem($"  Peak: Weekdays {peakStr}") { Enabled = false });
            menu.Items.Add(new ToolStripSeparator());
        }

        // Actions
        menu.Items.Add(new ToolStripMenuItem("Refresh Now", null, (_, _) =>
            Task.Run(() => _usageService.Fetch())));

        menu.Items.Add(new ToolStripSeparator());

        // Display mode
        var displayMenu = new ToolStripMenuItem("Show in Tray");
        AddCheckedItem(displayMenu, "5-hour only", _settings.DisplayMode == "5hour",
            () => SetDisplayMode("5hour"));
        AddCheckedItem(displayMenu, "Weekly only", _settings.DisplayMode == "weekly",
            () => SetDisplayMode("weekly"));
        AddCheckedItem(displayMenu, "Both (two icons)", _settings.DisplayMode == "both",
            () => SetDisplayMode("both"));
        menu.Items.Add(displayMenu);

        // Refresh interval
        var intervalMenu = new ToolStripMenuItem("Refresh Interval");
        foreach (var (label, secs) in new[] { ("1 min", 60), ("2 min", 120), ("5 min", 300), ("10 min", 600), ("15 min", 900) })
        {
            var s = secs;
            AddCheckedItem(intervalMenu, label, (int)_settings.RefreshInterval == s, () =>
            {
                _settings.RefreshInterval = s;
                _settings.Save();
                _usageService.UpdateRefreshInterval();
            });
        }
        menu.Items.Add(intervalMenu);

        // Timer format
        var formatMenu = new ToolStripMenuItem("Timer Format");
        foreach (TimerFormat fmt in Enum.GetValues<TimerFormat>())
        {
            var f = fmt;
            AddCheckedItem(formatMenu, f.DisplayName(), _settings.TimerFormatStr == f.ToSettingsString(), () =>
            {
                _settings.TimerFormatStr = f.ToSettingsString();
                _settings.Save();
            });
        }
        menu.Items.Add(formatMenu);

        // Promo timer toggle
        var promoItem = new ToolStripMenuItem("Show Promo Timer")
        {
            Checked = _settings.ShowPromoTimer,
            CheckOnClick = true
        };
        promoItem.Click += (_, _) =>
        {
            _settings.ShowPromoTimer = promoItem.Checked;
            _settings.Save();
        };
        menu.Items.Add(promoItem);

        // Auto-start
        var autoStart = new ToolStripMenuItem("Start with Windows")
        {
            Checked = IsAutoStartEnabled(),
            CheckOnClick = true
        };
        autoStart.Click += (_, _) => SetAutoStart(autoStart.Checked);
        menu.Items.Add(autoStart);

        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Quit", null, (_, _) => Quit()));

        return menu;
    }

    private static void AddCheckedItem(ToolStripMenuItem parent, string text, bool isChecked, Action onClick)
    {
        var item = new ToolStripMenuItem(text) { Checked = isChecked };
        item.Click += (_, _) => onClick();
        parent.DropDownItems.Add(item);
    }

    private void SetDisplayMode(string mode)
    {
        var oldMode = _settings.DisplayMode;
        _settings.DisplayMode = mode;
        _settings.Save();

        if (mode == "both" && _secondaryIcon == null)
            CreateSecondaryIcon();
        else if (mode != "both" && _secondaryIcon != null)
            RemoveSecondaryIcon();

        // Force icon re-render
        _lastPrimaryValue = -999;
    }

    private static bool IsAutoStartEnabled()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(StartupRegistryKey, false);
            return key?.GetValue(StartupValueName) != null;
        }
        catch { return false; }
    }

    private static void SetAutoStart(bool enable)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(StartupRegistryKey, true);
            if (key == null) return;

            if (enable)
            {
                var exePath = Application.ExecutablePath;
                key.SetValue(StartupValueName, $"\"{exePath}\"");
            }
            else
            {
                key.DeleteValue(StartupValueName, false);
            }
        }
        catch { }
    }

    private static string TimeAgo(DateTime dt)
    {
        var seconds = (int)(DateTime.UtcNow - dt).TotalSeconds;
        if (seconds < 60) return "just now";
        var minutes = seconds / 60;
        return minutes == 1 ? "1 min ago" : $"{minutes} min ago";
    }

    private void Quit()
    {
        _updateTimer?.Dispose();
        _appState.Stop();
        _primaryIcon.Visible = false;
        _primaryIcon.Dispose();
        RemoveSecondaryIcon();
        Application.Exit();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _updateTimer?.Dispose();
            _appState.Stop();
            _primaryIcon.Dispose();
            _secondaryIcon?.Dispose();
        }
        base.Dispose(disposing);
    }
}

internal static class NativeMethods
{
    [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Auto)]
    internal static extern bool DestroyIcon(IntPtr handle);
}
