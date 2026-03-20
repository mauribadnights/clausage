<p align="center">
  <img src="screenshots/repo_banner.png" alt="Clausage" width="600">
</p>

<p align="center">
  A native macOS app to track your <a href="https://claude.ai">Claude</a> usage, visualize consumption over time, and get smart plan recommendations.
</p>

<p align="center">
  <em>"Clausage" — Claude + Usage. Also sounds like sausage 🌭 Hence the logo.</em>
</p>

<p align="center">
  <img src="screenshots/menubar.png" width="320" alt="Menu Bar">
  &nbsp;&nbsp;
  <img src="screenshots/dashboard.png" width="480" alt="Dashboard">
</p>
<p align="center">
  <img src="screenshots/optimizer.png" width="480" alt="Plan Optimizer">
</p>

## Requirements

- **macOS 14.0** (Sonoma) or later
- **Claude Code** must be installed and logged in (for OAuth token)

## Installation

### Download

Grab the latest `Clausage.app.zip` from [Releases](https://github.com/mauribadnights/clausage/releases/latest).

1. Unzip `Clausage.app.zip`
2. Move `Clausage.app` to `/Applications`
3. Launch — it appears in your menu bar

> **macOS security warning:** Since Clausage isn't code-signed yet, macOS may show "app is damaged" or a Gatekeeper warning. To fix this, run once in Terminal:
> ```bash
> xattr -rd com.apple.quarantine /Applications/Clausage.app
> ```
> Then open it normally. Alternatively: right-click the app → **Open** → **Open** in the dialog.

### Build from Source

```bash
git clone https://github.com/mauribadnights/clausage.git
cd clausage
bash build.sh
open Clausage.app
```

Requires Xcode 15+ and Swift 5.9+.

## Features

### Menu Bar
- **Live usage display** in the menu bar with color-coded status
- **Usage bars** showing 5-hour and weekly consumption at a glance
- **Promo countdown timer** with peak/off-peak schedule awareness
- **Customizable** — timer format, colors, text shadow, toggle bars on/off

### Dashboard
- **Real-time usage cards** for 5-hour and weekly windows
- **Reset countdowns** showing when each usage window resets
- **Promo status** with countdown timer and schedule info

### Usage History
- **Automatic tracking** — usage is recorded every 5 minutes
- **Interactive charts** powered by Swift Charts with non-interpolated data points
- **Time range filters** — 24h, 7d, 30d, or all time
- **Statistics** — average usage, max peaks, % of time at limit

### Plan Optimizer
- **Peak-at-reset analysis** — measures your actual end-of-window consumption, not misleading instantaneous averages
- **Per-plan projection table** showing typical usage, peak usage, cycles over limit, and headroom for every plan
- **Natural language insights** analyzing your usage patterns and suggesting the cheapest plan that fits
- **Reset-aware** — detects window resets using API timestamps, works even when your laptop was closed during a reset
- **Token pricing reference** for comparing API supplementation costs
- **Auto-updating pricing** — fetches latest pricing from GitHub, falls back to bundled data

### Quality of Life
- **One-time keychain prompt** — caches your Claude Code OAuth token so you're never prompted again
- **Auto-update** — checks for new releases hourly, one-click update, plus manual "Check for Updates" button
- **Dynamic dock icon** — shows in dock when the main window is open, hides when minimized to menu bar
- **Works in any timezone** — all schedules display in your local time
- **Zero dependencies** — pure Swift/SwiftUI, native macOS frameworks only

## How It Works

### Usage Tracking

Clausage reads your Claude Code OAuth token from the macOS Keychain and calls the Anthropic usage API every 5 minutes (configurable). Each data point is persisted locally via SwiftData so you can visualize trends over time.

The first time the app reads your token, macOS will show a Keychain prompt — click **Allow** (or **Always Allow**). Clausage caches the token in its own Keychain entry so you're never prompted again.

### Plan Optimizer

The Plan Optimizer uses **peak-at-reset analysis** to measure how much capacity you actually consume per window. Instead of averaging instantaneous utilization readings (which would misleadingly show ~50% for a perfect-fit plan), it detects when usage windows reset and records your utilization just before each reset.

Reset detection uses the `resetsAt` timestamps from the API. When your laptop is closed during a reset, the last recorded value is used as the end-of-window estimate. For each plan it shows:

- **Typical usage** — average end-of-window consumption (5-hour and weekly)
- **Peak usage** — worst-case window consumption
- **Over limit** — how many windows would have exceeded 100% on that plan
- **Headroom** — remaining capacity based on typical peaks

It then generates a natural language insight suggesting the cheapest plan where you'd rarely exceed limits, and notes when API token supplementation might be worth considering.

### Pricing Data

Plan and token pricing is bundled with the app and also fetched from this repository's `pricing.json`. This means pricing stays current without requiring an app update. If the remote fetch fails, the bundled data is used as a fallback.

## Configuration

All settings are accessible from the main window's Settings tab:

| Setting | Default | Description |
|---------|---------|-------------|
| Timer format | `1:32:42` | Choose: full, compact, labeled, or minimal |
| Usage bars | On | Show mini usage bars in the menu bar |
| Text shadow | Off | Add shadow to menu bar text |
| Promo timer | On | Show 2x promo countdown (auto-hides when promo ends) |
| Refresh interval | 5 min | How often to poll the Anthropic API |
| Current plan | Pro | Your Claude subscription (for plan projections) |
| Timer colors | Any | Full color picker for off-peak and peak colors |

Settings persist across launches via UserDefaults.

## Development

### Project Structure

```
Clausage/
├── App/                    # App entry point, shared state
├── Features/
│   ├── MenuBar/            # Menu bar popover
│   ├── Dashboard/          # Main window, usage cards
│   ├── History/            # Usage charts (Swift Charts)
│   ├── PlanOptimizer/      # Per-plan projections & insights
│   └── Settings/           # Preferences + debug tools
├── Services/
│   ├── KeychainService     # OAuth token with caching
│   ├── UsageService        # Anthropic API client + persistence
│   ├── UpdateService       # GitHub release auto-updater
│   ├── PlanPricingService  # Pricing data + projection engine
│   └── MockDataSeeder      # Debug: seed test data
├── Models/
│   ├── PromoSchedule       # Promo timer (remote-configurable)
│   ├── UsageSnapshot       # SwiftData model
│   ├── PlanTier            # Plan & token pricing models
│   └── AppSettings         # User preferences
└── Resources/
    ├── pricing.json        # Bundled pricing + promo config
    └── Assets.xcassets     # App icon
```

### Running Tests

```bash
swift test
```

86 tests covering promo schedule, timer formatting, version comparison, plan projections, peak-at-reset detection, usage data, and SwiftData persistence.

### Debug Mode

Debug builds (`./run-debug.sh`) include a **Debug** section in Settings with usage pattern presets (Heavy User, Light User, Moderate, Limit Hitter) to test History charts and Plan Optimizer projections.

### CI/CD

- **CI** — runs on every push and PR to `dev` and `main`. Builds and runs the full test suite.
- **Release** — merge `dev` → `main` via PR, then tag `vX.Y.Z` on `main`. Pushing the tag triggers the release workflow which builds and publishes `Clausage.app.zip` as a GitHub Release.

### Updating Pricing

Edit `Clausage/Resources/pricing.json` and push to `main`. The app fetches this file periodically, so users get updated pricing without an app update. Set `promo.enabled` to `false` to disable the promo timer remotely.

## License

MIT
