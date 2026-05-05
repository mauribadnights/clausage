using System.Text.Json;
using Clausage.Models;

namespace Clausage.Services;

public class UsageService
{
    private const string ApiUrl = "https://api.anthropic.com/api/oauth/usage";

    public UsageData Usage { get; private set; } = new();
    public bool IsLoading { get; private set; }

    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(10) };
    private System.Threading.Timer? _refreshTimer;
    private System.Threading.Timer? _retryTimer;
    private int _consecutiveFailures;
    private UsageData? _lastSuccessful;
    private readonly object _lock = new();
    private readonly string _cachePath;

    public UsageService()
    {
        var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".clausage");
        Directory.CreateDirectory(dir);
        _cachePath = Path.Combine(dir, "usage_cache.json");

        var cached = LoadCached();
        if (cached != null)
        {
            cached.IsStale = true;
            Usage = cached;
            _lastSuccessful = new UsageData
            {
                FiveHourPercent = cached.FiveHourPercent,
                FiveHourResetsAt = cached.FiveHourResetsAt,
                WeeklyPercent = cached.WeeklyPercent,
                WeeklyResetsAt = cached.WeeklyResetsAt,
                LastUpdated = cached.LastUpdated,
            };
        }

        StartRefreshTimer();
        Task.Run(() => Fetch());
    }

    private void StartRefreshTimer()
    {
        _refreshTimer?.Dispose();
        var interval = TimeSpan.FromSeconds(AppSettings.Shared.RefreshInterval);
        _refreshTimer = new System.Threading.Timer(_ => Fetch(), null, interval, interval);
    }

    public void UpdateRefreshInterval() => StartRefreshTimer();

    public void Fetch()
    {
        lock (_lock)
        {
            IsLoading = true;
            _retryTimer?.Dispose();
            _retryTimer = null;
        }

        var result = FetchUsage();
        var isRateLimited = result.Error == "Rate limited";

        lock (_lock)
        {
            if (result.Error != null)
            {
                _consecutiveFailures++;
                if (_lastSuccessful != null)
                {
                    Usage = new UsageData
                    {
                        FiveHourPercent = _lastSuccessful.FiveHourPercent,
                        FiveHourResetsAt = _lastSuccessful.FiveHourResetsAt,
                        WeeklyPercent = _lastSuccessful.WeeklyPercent,
                        WeeklyResetsAt = _lastSuccessful.WeeklyResetsAt,
                        LastUpdated = _lastSuccessful.LastUpdated,
                        IsStale = true,
                    };
                }
                else if (isRateLimited)
                {
                    Usage = new UsageData { Error = "Waiting for API... (rate limited)" };
                }
                else
                {
                    Usage = result;
                }

                if (!isRateLimited)
                {
                    var delay = Math.Min(15.0 * Math.Pow(2, _consecutiveFailures - 1), 120.0);
                    _retryTimer = new System.Threading.Timer(_ => Fetch(), null,
                        TimeSpan.FromSeconds(delay), Timeout.InfiniteTimeSpan);
                }
            }
            else
            {
                _consecutiveFailures = 0;
                _lastSuccessful = result;
                Usage = result;
                SaveCached(result);
            }

            IsLoading = false;
        }
    }

    private UsageData FetchUsage()
    {
        var token = CredentialService.GetAccessToken();
        if (token == null)
            return new UsageData { Error = "No Claude Code credentials found. Open Claude Code and log in first." };

        try
        {
            var request = CreateRequest(token);
            var resp = _http.Send(request);

            if ((int)resp.StatusCode == 401)
            {
                var fresh = CredentialService.RefreshToken();
                if (fresh == null)
                    return new UsageData { Error = "Authentication failed. Re-login to Claude Code." };
                request = CreateRequest(fresh);
                resp = _http.Send(request);
            }

            if ((int)resp.StatusCode == 429)
            {
                var fresh = CredentialService.RefreshToken();
                if (fresh != null)
                {
                    try
                    {
                        request = CreateRequest(fresh);
                        var retryResp = _http.Send(request);
                        if (retryResp.IsSuccessStatusCode)
                        {
                            var retryBody = retryResp.Content.ReadAsStringAsync().GetAwaiter().GetResult();
                            return ParseResponse(retryBody);
                        }
                    }
                    catch { }
                }
                return new UsageData { Error = "Rate limited" };
            }

            if (!resp.IsSuccessStatusCode)
                return new UsageData { Error = $"API error ({(int)resp.StatusCode})" };

            var body = resp.Content.ReadAsStringAsync().GetAwaiter().GetResult();
            return ParseResponse(body);
        }
        catch (Exception ex)
        {
            return new UsageData { Error = ex.Message };
        }
    }

    private static HttpRequestMessage CreateRequest(string token)
    {
        var req = new HttpRequestMessage(HttpMethod.Get, ApiUrl);
        req.Headers.Add("Authorization", $"Bearer {token}");
        req.Headers.Add("anthropic-beta", "oauth-2025-04-20");
        req.Headers.Add("User-Agent", "claude-code/2.1.77");
        return req;
    }

    internal static UsageData ParseResponse(string body)
    {
        try
        {
            using var doc = JsonDocument.Parse(body);
            var root = doc.RootElement;

            if (root.TryGetProperty("error", out var err))
            {
                var msg = err.ValueKind == JsonValueKind.Object && err.TryGetProperty("message", out var m)
                    ? m.GetString() : err.ToString();
                return new UsageData { Error = msg ?? "Unknown error" };
            }

            var usage = new UsageData { LastUpdated = DateTime.UtcNow };

            if (root.TryGetProperty("five_hour", out var fh))
            {
                usage.FiveHourPercent = ParseNumber(fh, "utilization");
                if (fh.TryGetProperty("resets_at", out var ra))
                {
                    if (DateTime.TryParse(ra.GetString(), null,
                        System.Globalization.DateTimeStyles.RoundtripKind, out var dt))
                        usage.FiveHourResetsAt = dt.ToUniversalTime();
                }
            }

            if (root.TryGetProperty("seven_day", out var sd))
            {
                usage.WeeklyPercent = ParseNumber(sd, "utilization");
                if (sd.TryGetProperty("resets_at", out var ra))
                {
                    if (DateTime.TryParse(ra.GetString(), null,
                        System.Globalization.DateTimeStyles.RoundtripKind, out var dt))
                        usage.WeeklyResetsAt = dt.ToUniversalTime();
                }
            }

            if (usage.FiveHourPercent == null && usage.WeeklyPercent == null)
                usage.Error = $"Unexpected response: {body[..Math.Min(body.Length, 200)]}";

            return usage;
        }
        catch
        {
            return new UsageData { Error = "Failed to parse response" };
        }
    }

    private static double? ParseNumber(JsonElement parent, string property)
    {
        if (!parent.TryGetProperty(property, out var val)) return null;
        return val.ValueKind switch
        {
            JsonValueKind.Number => val.GetDouble(),
            JsonValueKind.String => double.TryParse(val.GetString(), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var d) ? d : null,
            _ => null
        };
    }

    public static string ResetTimeString(DateTime? date)
    {
        if (date == null) return "\u2014";
        var interval = (date.Value.ToUniversalTime() - DateTime.UtcNow).TotalSeconds;
        if (interval <= 0) return "now";

        int hours = (int)interval / 3600;
        int minutes = ((int)interval % 3600) / 60;

        if (hours > 24)
        {
            int days = hours / 24;
            return $"in {days}d {hours % 24}h";
        }
        if (hours > 0) return $"in {hours}h {minutes}m";
        return $"in {minutes}m";
    }

    private void SaveCached(UsageData data)
    {
        try
        {
            var cache = new Dictionary<string, object?>
            {
                ["five_hour_percent"] = data.FiveHourPercent,
                ["weekly_percent"] = data.WeeklyPercent,
                ["five_hour_resets_at"] = data.FiveHourResetsAt?.ToString("O"),
                ["weekly_resets_at"] = data.WeeklyResetsAt?.ToString("O"),
                ["last_updated"] = data.LastUpdated?.ToString("O"),
            };
            File.WriteAllText(_cachePath, JsonSerializer.Serialize(cache));
        }
        catch { }
    }

    private UsageData? LoadCached()
    {
        try
        {
            if (!File.Exists(_cachePath)) return null;
            var json = File.ReadAllText(_cachePath);
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            var data = new UsageData();
            if (root.TryGetProperty("five_hour_percent", out var fh) && fh.ValueKind == JsonValueKind.Number)
                data.FiveHourPercent = fh.GetDouble();
            if (root.TryGetProperty("weekly_percent", out var wk) && wk.ValueKind == JsonValueKind.Number)
                data.WeeklyPercent = wk.GetDouble();
            if (root.TryGetProperty("five_hour_resets_at", out var fhr) && fhr.GetString() is string fhrStr)
                data.FiveHourResetsAt = DateTime.Parse(fhrStr, null, System.Globalization.DateTimeStyles.RoundtripKind);
            if (root.TryGetProperty("weekly_resets_at", out var wkr) && wkr.GetString() is string wkrStr)
                data.WeeklyResetsAt = DateTime.Parse(wkrStr, null, System.Globalization.DateTimeStyles.RoundtripKind);
            if (root.TryGetProperty("last_updated", out var lu) && lu.GetString() is string luStr)
                data.LastUpdated = DateTime.Parse(luStr, null, System.Globalization.DateTimeStyles.RoundtripKind);

            if (data.FiveHourPercent == null && data.WeeklyPercent == null) return null;
            return data;
        }
        catch { return null; }
    }
}
