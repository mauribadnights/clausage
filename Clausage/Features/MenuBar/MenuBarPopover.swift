import SwiftUI

struct MenuBarPopover: View {
    let appState: AppState
    let usageService: UsageService
    let updateService: UpdateService
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Update banner
            if let newVersion = updateService.updateAvailable {
                UpdateBanner(version: newVersion, updateService: updateService)
                Divider()
            }

            // Status header
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(appState.statusDescription)
                    .font(.system(size: 14, weight: .semibold))
            }

            if !appState.countdownText.isEmpty {
                Text(appState.nextTransitionDescription)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Divider()

            // Usage section
            UsageSection(usageService: usageService)

            // Schedule info (only when promo is active)
            if AppSettings.shared.showPromoTimer && appState.status != .ended {
                Divider()
                ScheduleSection()
            }

            Divider()

            HStack {
                Button("Open Clausage") {
                    dismiss()
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.accentColor)

                Spacer()

                Button(action: {
                    dismiss()
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }) {
                    Image(systemName: "gear")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Text("Quit")
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Text("v\(UpdateService.currentVersion)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private var statusColor: Color {
        switch appState.status {
        case .active2x: return .green
        case .peak1x: return .orange
        case .notStarted: return .blue
        case .ended: return .gray
        }
    }

}

struct UsageSection: View {
    let usageService: UsageService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("USAGE")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                if usageService.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                } else {
                    Button(action: { usageService.fetch() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if usageService.usage.fiveHourPercent != nil || usageService.usage.weeklyPercent != nil {
                // Show usage data (even if stale from rate limiting)
                UsageRow(
                    label: "5-hour",
                    percent: usageService.usage.fiveHourPercent,
                    resetsAt: usageService.usage.fiveHourResetsAt
                )
                UsageRow(
                    label: "Weekly",
                    percent: usageService.usage.weeklyPercent,
                    resetsAt: usageService.usage.weeklyResetsAt
                )
            } else if let error = usageService.usage.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            if let lastUpdated = usageService.usage.lastUpdated {
                HStack(spacing: 4) {
                    Text("Updated \(timeAgo(lastUpdated))")
                    if usageService.usage.isStale {
                        Text("(refreshing...)")
                    }
                }
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.7))
            }
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes == 1 { return "1 min ago" }
        return "\(minutes) min ago"
    }
}

struct ScheduleSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SCHEDULE")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)

            HStack(alignment: .top) {
                Text("Peak (1x):")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 65, alignment: .leading)
                Text("Weekdays \(PromoSchedule.peakHoursLocalString())")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .top) {
                Text("2x active:")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 65, alignment: .leading)
                Text("Outside peak + all weekends")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Text("Promo ends: \(PromoSchedule.promoEndLocalString())")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.top, 2)
        }
    }
}

struct UsageRow: View {
    let label: String
    let percent: Double?
    let resetsAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                if let pct = percent {
                    Text("\(Int(pct))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(usageColor(pct))
                } else {
                    Text("\u{2014}")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            if let pct = percent {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(usageColor(pct))
                            .frame(width: geo.size.width * min(pct / 100.0, 1.0), height: 4)
                    }
                }
                .frame(height: 4)
            }

            if let resetsAt = resetsAt {
                Text("Resets \(UsageService.resetTimeString(resetsAt))")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
    }

    private func usageColor(_ pct: Double) -> Color {
        if pct < 50 { return .green }
        if pct < 80 { return .orange }
        return .red
    }
}

struct UpdateBanner: View {
    let version: String
    let updateService: UpdateService

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if updateService.isUpdating {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                    Text("Updating...")
                        .font(.system(size: 11, weight: .medium))
                }
            } else {
                HStack {
                    Text("Update available: \(version)")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Button("Update") {
                        updateService.performUpdate()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if let error = updateService.updateError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }
        }
    }
}

