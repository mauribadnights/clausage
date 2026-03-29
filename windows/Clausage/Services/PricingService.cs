using System.Reflection;
using System.Text.Json;
using Clausage.Models;

namespace Clausage.Services;

public class PricingService
{
    private const string RemoteUrl = "https://raw.githubusercontent.com/mauribadnights/clausage/main/pricing.json";
    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(10) };

    public PricingData? Pricing { get; private set; }
    public string? LastFetchError { get; private set; }

    public PricingService()
    {
        LoadBundled();
        Task.Run(FetchRemote);
    }

    private void LoadBundled()
    {
        try
        {
            var assembly = Assembly.GetExecutingAssembly();
            var resourceName = assembly.GetManifestResourceNames()
                .FirstOrDefault(n => n.EndsWith("pricing.json"));
            if (resourceName == null) return;

            using var stream = assembly.GetManifestResourceStream(resourceName);
            if (stream == null) return;
            using var reader = new StreamReader(stream);
            var json = reader.ReadToEnd();

            var decoded = Decode(json);
            if (decoded != null)
            {
                Pricing = decoded;
                PromoSchedule.Shared.Update(decoded.Promo);
            }
        }
        catch { }
    }

    public void FetchRemote()
    {
        try
        {
            var resp = _http.GetAsync(RemoteUrl).GetAwaiter().GetResult();
            if (!resp.IsSuccessStatusCode) return;

            var json = resp.Content.ReadAsStringAsync().GetAwaiter().GetResult();
            var decoded = Decode(json);
            if (decoded != null)
            {
                Pricing = decoded;
                LastFetchError = null;
                PromoSchedule.Shared.Update(decoded.Promo);
            }
        }
        catch (Exception ex)
        {
            LastFetchError = ex.Message;
        }
    }

    internal static PricingData? Decode(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            var plans = new List<PlanTier>();
            if (root.TryGetProperty("plans", out var plansArr))
            {
                foreach (var p in plansArr.EnumerateArray())
                {
                    plans.Add(new PlanTier(
                        p.GetProperty("id").GetString()!,
                        p.GetProperty("name").GetString()!,
                        p.GetProperty("monthlyPrice").GetDouble(),
                        p.GetProperty("description").GetString()!,
                        p.GetProperty("usageMultiplier").GetDouble()
                    ));
                }
            }

            var tokenPricing = new List<TokenPricing>();
            if (root.TryGetProperty("tokenPricing", out var tpArr))
            {
                foreach (var t in tpArr.EnumerateArray())
                {
                    tokenPricing.Add(new TokenPricing(
                        t.GetProperty("model").GetString()!,
                        t.GetProperty("displayName").GetString()!,
                        t.GetProperty("inputPerMillion").GetDouble(),
                        t.GetProperty("outputPerMillion").GetDouble()
                    ));
                }
            }

            PromoConfig? promo = null;
            if (root.TryGetProperty("promo", out var promoEl) && promoEl.ValueKind == JsonValueKind.Object)
            {
                promo = new PromoConfig(
                    promoEl.GetProperty("enabled").GetBoolean(),
                    promoEl.GetProperty("startUTC").GetString()!,
                    promoEl.GetProperty("endUTC").GetString()!,
                    promoEl.GetProperty("peakStartHourUTC").GetInt32(),
                    promoEl.GetProperty("peakEndHourUTC").GetInt32(),
                    promoEl.GetProperty("description").GetString()!
                );
            }

            return new PricingData(
                root.TryGetProperty("lastUpdated", out var lu) ? lu.GetString()! : "",
                plans,
                tokenPricing,
                promo
            );
        }
        catch { return null; }
    }
}
