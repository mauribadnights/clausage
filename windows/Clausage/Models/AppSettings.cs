using System.Text.Json;

namespace Clausage.Models;

public class AppSettings
{
    private static AppSettings? _instance;
    private static readonly object _lock = new();
    private readonly string _path;

    public string TimerFormatStr { get; set; } = "full";
    public bool ShowPromoTimer { get; set; } = true;
    public string CurrentPlanId { get; set; } = "pro";
    public double RefreshInterval { get; set; } = 300;
    public int IconSize { get; set; } = 16;
    public string CredentialsPath { get; set; } = "";
    public string DisplayMode { get; set; } = "5hour"; // "5hour", "weekly", "both"

    public TimerFormat GetTimerFormat() => TimerFormatExtensions.FromSettingsString(TimerFormatStr);

    public static AppSettings Shared
    {
        get
        {
            if (_instance == null)
            {
                lock (_lock)
                {
                    _instance ??= new AppSettings();
                }
            }
            return _instance;
        }
    }

    private AppSettings()
    {
        var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".clausage");
        Directory.CreateDirectory(dir);
        _path = Path.Combine(dir, "settings.json");
        Load();
    }

    private void Load()
    {
        try
        {
            if (!File.Exists(_path)) return;
            var json = File.ReadAllText(_path);
            var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            if (root.TryGetProperty("timer_format", out var tf)) TimerFormatStr = tf.GetString() ?? "full";
            if (root.TryGetProperty("show_promo_timer", out var sp)) ShowPromoTimer = sp.GetBoolean();
            if (root.TryGetProperty("current_plan_id", out var cp)) CurrentPlanId = cp.GetString() ?? "pro";
            if (root.TryGetProperty("refresh_interval", out var ri)) RefreshInterval = ri.GetDouble();
            if (root.TryGetProperty("icon_size", out var isz)) IconSize = isz.GetInt32();
            if (root.TryGetProperty("credentials_path", out var cr)) CredentialsPath = cr.GetString() ?? "";
            if (root.TryGetProperty("display_mode", out var dm)) DisplayMode = dm.GetString() ?? "5hour";
        }
        catch { }
    }

    public void Save()
    {
        try
        {
            var data = new Dictionary<string, object>
            {
                ["timer_format"] = TimerFormatStr,
                ["show_promo_timer"] = ShowPromoTimer,
                ["current_plan_id"] = CurrentPlanId,
                ["refresh_interval"] = RefreshInterval,
                ["icon_size"] = IconSize,
                ["credentials_path"] = CredentialsPath,
                ["display_mode"] = DisplayMode,
            };
            var json = JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(_path, json);
        }
        catch { }
    }
}
