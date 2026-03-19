import SwiftUI

struct DashboardView: View {
    let usageService: UsageService
    let appState: AppState

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
