import SwiftUI
import SwiftData

struct DashboardView: View {
    let usageService: UsageService
    let appState: AppState
    @Query(sort: \UsageSnapshot.timestamp, order: .forward) private var snapshots: [UsageSnapshot]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    Text("Clausage")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Spacer()
                }

                // Current usage cards
                HStack(spacing: 16) {
                    UsageCard(
                        title: "5-Hour Usage",
                        percent: usageService.usage.fiveHourPercent,
                        resetsAt: usageService.usage.fiveHourResetsAt,
                        icon: "clock"
                    )
                    UsageCard(
                        title: "Weekly Usage",
                        percent: usageService.usage.weeklyPercent,
                        resetsAt: usageService.usage.weeklyResetsAt,
                        icon: "calendar"
                    )
                }

                // Burn window card
                if let weekly = usageService.usage.weeklyPercent,
                   let resetsAt = usageService.usage.weeklyResetsAt {
                    if let burn = UsageService.computeBurnWindow(weeklyPercent: weekly, weeklyResetsAt: resetsAt, snapshots: snapshots) {
                        BurnWindowCard(burn: burn, weeklyPercent: weekly)
                    } else if weekly < 99 {
                        BurnWindowNoDataCard()
                    }
                }

                // Promo status card
                if AppSettings.shared.showPromoTimer && appState.status != .ended && appState.status != .disabled {
                    PromoCard(appState: appState)
                }

                // Error or status
                if let error = usageService.usage.error {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Stale data warning
                if usageService.usage.isStale, let lastUpdated = usageService.usage.lastUpdated {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                        Text("Unable to refresh — showing data from \(lastUpdated.formatted(.relative(presentation: .named)))")
                            .font(.callout)
                    }
                    .foregroundColor(.orange)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Last updated + refresh
                HStack {
                    if let lastUpdated = usageService.usage.lastUpdated, !usageService.usage.isStale {
                        Text("Last updated: \(lastUpdated.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { usageService.fetch() }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(usageService.isLoading)
                }
            }
            .padding(24)
        }
        .navigationTitle("Dashboard")
    }
}

struct UsageCard: View {
    let title: String
    let percent: Double?
    let resetsAt: Date?
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.headline)
                Spacer()
            }

            if let pct = percent {
                // Large percentage display
                Text("\(Int(pct))%")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(usageColor(pct))

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(usageColor(pct))
                            .frame(width: geo.size.width * min(pct / 100.0, 1.0))
                    }
                }
                .frame(height: 8)

                if let resetsAt = resetsAt {
                    Text("Resets \(UsageService.resetTimeString(resetsAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("\u{2014}")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func usageColor(_ pct: Double) -> Color {
        if pct < 50 { return .green }
        if pct < 80 { return .orange }
        return .red
    }
}

struct BurnWindowCard: View {
    let burn: UsageService.BurnWindow
    let weeklyPercent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "flame")
                    .font(.title3)
                    .foregroundColor(burn.shouldStartNow ? .red : .orange)
                Text("Burn Window")
                    .font(.headline)
                Spacer()
                if weeklyPercent >= 99 {
                    Text("Maxed out")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if weeklyPercent >= 99 {
                Text("Weekly usage is already at capacity.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else if burn.shouldStartNow {
                // Should be burning right now
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Start burning now!")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.red)
                    }

                    if burn.maxReachablePercent < 99 {
                        Text("Not enough time to reach 100%. Max reachable: \(Int(burn.maxReachablePercent))%")
                            .font(.callout)
                            .foregroundColor(.orange)
                    } else {
                        Text("You have enough time to reach 100% if you start now.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 16) {
                        Label("\(formatHours(burn.hoursUntilReset)) until reset", systemImage: "clock")
                        Label("\(formatHours(burn.hoursNeeded)) of heavy use needed", systemImage: "bolt.fill")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            } else {
                // Future start time
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Start burning")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        Text(burnStartString)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                    }

                    Text(burn.startBurningAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 16) {
                        Label("\(Int(100 - weeklyPercent))% remaining", systemImage: "chart.bar.fill")
                        Label("\(formatHours(burn.hoursNeeded)) of heavy use", systemImage: "bolt.fill")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            // Burn rate info
            Text("Estimated burn rate: \(String(format: "%.1f", burn.burnRatePerHour))%/hr (from your usage history)")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (burn.shouldStartNow ? Color.red : Color.orange).opacity(0.08)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var burnStartString: String {
        let interval = burn.startBurningAt.timeIntervalSince(Date())
        guard interval > 0 else { return "now" }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 24 {
            let days = hours / 24
            return "in \(days)d \(hours % 24)h"
        } else if hours > 0 {
            return "in \(hours)h \(minutes)m"
        } else {
            return "in \(minutes)m"
        }
    }

    private func formatHours(_ h: Double) -> String {
        if h >= 24 {
            let days = Int(h) / 24
            let hrs = Int(h) % 24
            return "\(days)d \(hrs)h"
        } else if h >= 1 {
            return "\(Int(h))h \(Int(h.truncatingRemainder(dividingBy: 1) * 60))m"
        } else {
            return "\(Int(h * 60))m"
        }
    }
}

struct BurnWindowNoDataCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "flame")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Text("Burn Window")
                    .font(.headline)
                Spacer()
            }
            Text("Not enough usage data yet to estimate your burn rate. Keep using Claude \u{2014} the burn window will appear once enough high-usage periods are recorded.")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct PromoCard: View {
    let appState: AppState

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)
                    Text(appState.statusDescription)
                        .font(.headline)
                }

                if !appState.countdownText.isEmpty {
                    Text(appState.nextTransitionDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Text("Peak: Weekdays \(PromoSchedule.shared.peakHoursLocalString())")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !appState.countdownText.isEmpty {
                Text(appState.countdownText)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(statusColor)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(statusColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var statusColor: Color {
        switch appState.status {
        case .active2x: return .green
        case .peak1x: return .orange
        case .notStarted: return .blue
        case .ended, .disabled: return .gray
        }
    }
}
