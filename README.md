# Clausage 🌭

A native macOS app to track your [Claude](https://claude.ai) usage, visualize consumption over time, and get smart plan recommendations.

> *"Clausage"* — Claude + Usage. Also sounds like sausage 🌭 Hence the logo.

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
- **Interactive charts** powered by Swift Charts
- **Time range filters** — 24h, 7d, 30d, or all time
- **Statistics** — average usage, max peaks, limit hit frequency

### Plan Optimizer
- **Plan comparison table** with cost-per-unit analysis
- **Smart recommendations** — upgrade, downgrade, or stay put
- **Usage-based analysis** using your actual consumption patterns
- **Token pricing reference** for API cost comparison
- **Auto-updating pricing** — fetches latest pricing from GitHub, falls back to bundled data

### Quality of Life
- **One-time keychain prompt** — caches your Claude Code OAuth token so you're never prompted again
- **Auto-update** — checks for new releases hourly, one-click update
- **Dynamic dock icon** — shows in dock when the main window is open, hides when minimized to menu bar
- **Works in any timezone** — all schedules display in your local time
- **Zero dependencies** — pure Swift/SwiftUI, native macOS frameworks only

## Requirements

- **macOS 14.0** (Sonoma) or later
- **Claude Code** must be installed and logged in (for OAuth token)

## Installation

### Download

Grab the latest `Clausage.app.zip` from [Releases](https://github.com/mauribadnights/clausage/releases/latest).

1. Unzip `Clausage.app.zip`
2. Move `Clausage.app` to `/Applications`
3. Launch — it appears in your menu bar

### Build from Source

```bash
git clone https://github.com/mauribadnights/clausage.git
cd clausage
bash build.sh
open Clausage.app
```

Requires Xcode 15+ and Swift 5.9+.

## How It Works

### Usage Tracking

Clausage reads your Claude Code OAuth token from the macOS Keychain and calls the Anthropic usage API every 5 minutes (configurable). Each data point is persisted locally via SwiftData so you can visualize trends over time.

The first time the app reads your token, macOS will show a Keychain prompt — click **Allow** (or **Always Allow**). Clausage caches the token in its own Keychain entry so you're never prompted again.

### Plan Recommendations

The Plan Optimizer analyzes your usage history and compares it against your current plan:

- **Upgrade** — recommended when you're hitting usage limits frequently (>30% of samples at 95%+)
- **Downgrade** — recommended when your average usage is below 20% of your plan's capacity
- **Stay put** — when your plan matches your usage patterns well

Recommendations include specific stats: average 5-hour usage, average weekly usage, and how many times you've hit the limit.

### Pricing Data

Plan and token pricing is bundled with the app and also fetched from this repository's `pricing.json`. This means pricing stays current without requiring an app update. If the remote fetch fails, the bundled data is used as a fallback.

## Development

### Project Structure

```
Clausage/
├── App/                    # App entry point, shared state
├── Features/
│   ├── MenuBar/            # Menu bar popover
│   ├── Dashboard/          # Main window, usage cards
│   ├── History/            # Usage charts (Swift Charts)
│   ├── PlanOptimizer/      # Plan comparison & recommendations
│   └── Settings/           # Preferences + debug tools
├── Services/
│   ├── KeychainService     # OAuth token with caching
│   ├── UsageService        # Anthropic API client + persistence
│   ├── UpdateService       # GitHub release auto-updater
│   ├── PlanPricingService  # Pricing data + recommendation engine
│   └── MockDataSeeder      # Debug: seed test data
├── Models/
│   ├── PromoSchedule       # 2x promo timer logic
│   ├── UsageSnapshot       # SwiftData model
│   ├── PlanTier            # Plan & token pricing models
│   └── AppSettings         # User preferences
└── Resources/
    ├── pricing.json        # Bundled pricing data
    └── Assets.xcassets     # App icon
```

### Running Tests

```bash
swift test
```

Tests cover:
- Promo schedule logic (status transitions, boundary conditions, timezone display)
- Timer formatting (all formats, edge cases, day overflow)
- Version comparison (semver parsing, v-prefix handling)
- Plan pricing (JSON decoding, recommendation algorithm, edge cases)
- Usage data (reset time formatting, equality)
- SwiftData persistence (insert, fetch, sort)

### Debug Mode

In debug builds, the Settings view includes a **Debug** section where you can:
- **Seed 7 or 30 days** of realistic mock usage data
- **Clear history** to start fresh

This lets you test the History charts and Plan Optimizer recommendations without waiting for real data to accumulate.

### CI/CD

- **CI** — runs on every push to `main` and on PRs. Builds and runs the full test suite.
- **Release** — tag a version (`git tag v1.0.0 && git push --tags`) to automatically build, test, and publish a GitHub Release with `Clausage.app.zip`.

### Updating Pricing

Edit `Clausage/Resources/pricing.json` and push to `main`. The app fetches this file periodically, so users get updated pricing without an app update.

## Configuration

All settings are accessible from the main window's Settings tab or the menu bar popover:

| Setting | Default | Description |
|---------|---------|-------------|
| Timer format | `1:32:42` | Choose: full, compact, labeled, or minimal |
| Usage bars | On | Show mini usage bars in the menu bar |
| Text shadow | Off | Add shadow to menu bar text |
| Promo timer | On | Show 2x promo countdown (auto-hides when promo ends) |
| Refresh interval | 5 min | How often to poll the Anthropic API |
| Current plan | Pro | Your Claude subscription (for plan recommendations) |
| Timer colors | Green/Red | Customize off-peak and peak colors |

Settings persist across launches via UserDefaults.

## License

MIT
