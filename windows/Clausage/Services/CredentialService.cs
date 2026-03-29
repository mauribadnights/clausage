using System.Diagnostics;
using System.Text.Json;
using Clausage.Models;

namespace Clausage.Services;

public record OAuthTokenData(string AccessToken, string RefreshToken, DateTime ExpiresAt);

public static class CredentialService
{
    private const string TokenEndpoint = "https://platform.claude.com/v1/oauth/token";
    private const string ClientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
    private const int RefreshMarginSeconds = 300;

    private static OAuthTokenData? _cached;
    private static readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(10) };

    public static string? GetAccessToken()
    {
        if (_cached != null && !IsExpiringSoon(_cached))
            return _cached.AccessToken;

        if (_cached != null && IsExpiringSoon(_cached))
        {
            var refreshed = PerformRefresh(_cached.RefreshToken);
            if (refreshed != null) { _cached = refreshed; return refreshed.AccessToken; }
            if (!IsExpired(_cached)) return _cached.AccessToken;
        }

        var tokenData = ReadCredentials();
        if (tokenData != null)
        {
            if (!IsExpiringSoon(tokenData)) { _cached = tokenData; return tokenData.AccessToken; }
            var refreshed = PerformRefresh(tokenData.RefreshToken);
            if (refreshed != null) { _cached = refreshed; return refreshed.AccessToken; }
            _cached = tokenData;
            return tokenData.AccessToken;
        }

        return null;
    }

    public static string? RefreshToken()
    {
        if (_cached != null)
        {
            var refreshed = PerformRefresh(_cached.RefreshToken);
            if (refreshed != null) { _cached = refreshed; return refreshed.AccessToken; }
        }

        _cached = null;
        var tokenData = ReadCredentials();
        if (tokenData != null)
        {
            var refreshed = PerformRefresh(tokenData.RefreshToken);
            if (refreshed != null) { _cached = refreshed; return refreshed.AccessToken; }
            _cached = tokenData;
            return tokenData.AccessToken;
        }

        return null;
    }

    private static string? FindCredentialsPath()
    {
        // 1. User-configured path
        var custom = AppSettings.Shared.CredentialsPath;
        if (!string.IsNullOrEmpty(custom) && File.Exists(custom))
            return custom;

        // 2. Native Windows path: %USERPROFILE%\.claude\.credentials.json
        var native = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".claude", ".credentials.json");
        if (File.Exists(native))
            return native;

        // 3. WSL paths via \\wsl.localhost\ or \\wsl$\
        try
        {
            var psi = new ProcessStartInfo("wsl.exe", "-l -q")
            {
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using var proc = Process.Start(psi);
            if (proc != null)
            {
                // wsl.exe outputs UTF-16LE
                using var reader = new StreamReader(proc.StandardOutput.BaseStream, System.Text.Encoding.Unicode);
                var output = reader.ReadToEnd();
                proc.WaitForExit(5000);

                var distros = output.Split('\n', StringSplitOptions.RemoveEmptyEntries)
                    .Select(d => d.Trim().Trim('\0'))
                    .Where(d => !string.IsNullOrEmpty(d));

                foreach (var distro in distros)
                {
                    try
                    {
                        var userPsi = new ProcessStartInfo("wsl.exe", $"-d {distro} whoami")
                        {
                            RedirectStandardOutput = true,
                            UseShellExecute = false,
                            CreateNoWindow = true
                        };
                        using var userProc = Process.Start(userPsi);
                        var username = userProc?.StandardOutput.ReadToEnd().Trim();
                        userProc?.WaitForExit(5000);

                        if (!string.IsNullOrEmpty(username))
                        {
                            foreach (var prefix in new[] { @"\\wsl.localhost", @"\\wsl$" })
                            {
                                var wslPath = Path.Combine(prefix, distro, "home", username, ".claude", ".credentials.json");
                                if (File.Exists(wslPath))
                                    return wslPath;
                            }
                        }
                    }
                    catch { }
                }
            }
        }
        catch { }

        return null;
    }

    private static OAuthTokenData? ReadCredentials()
    {
        var path = FindCredentialsPath();
        if (path == null) return null;

        try
        {
            var json = File.ReadAllText(path);
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            if (!root.TryGetProperty("claudeAiOauth", out var oauth)) return null;
            if (!oauth.TryGetProperty("accessToken", out var at)) return null;
            if (!oauth.TryGetProperty("refreshToken", out var rt)) return null;

            DateTime expiresAt;
            if (oauth.TryGetProperty("expiresAt", out var ea))
            {
                var ms = ea.GetDouble();
                expiresAt = DateTimeOffset.FromUnixTimeMilliseconds((long)ms).UtcDateTime;
            }
            else
            {
                expiresAt = DateTime.UtcNow.AddHours(1);
            }

            return new OAuthTokenData(at.GetString()!, rt.GetString()!, expiresAt);
        }
        catch { return null; }
    }

    private static OAuthTokenData? PerformRefresh(string refreshToken)
    {
        try
        {
            var content = new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["grant_type"] = "refresh_token",
                ["refresh_token"] = refreshToken,
                ["client_id"] = ClientId
            });

            var resp = _http.PostAsync(TokenEndpoint, content).GetAwaiter().GetResult();
            if (!resp.IsSuccessStatusCode) return null;

            var body = resp.Content.ReadAsStringAsync().GetAwaiter().GetResult();
            using var doc = JsonDocument.Parse(body);
            var root = doc.RootElement;

            if (!root.TryGetProperty("access_token", out var newAt)) return null;

            var newRt = root.TryGetProperty("refresh_token", out var rt) ? rt.GetString()! : refreshToken;
            var expiresIn = root.TryGetProperty("expires_in", out var ei) ? ei.GetInt32() : 86400;

            return new OAuthTokenData(newAt.GetString()!, newRt, DateTime.UtcNow.AddSeconds(expiresIn));
        }
        catch { return null; }
    }

    private static bool IsExpiringSoon(OAuthTokenData token) =>
        (token.ExpiresAt - DateTime.UtcNow).TotalSeconds < RefreshMarginSeconds;

    private static bool IsExpired(OAuthTokenData token) =>
        token.ExpiresAt <= DateTime.UtcNow;
}
