import SwiftUI
import SwiftData

struct SettingsView: View {
    let usageService: UsageService
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                MenuBarSettingsSection(settings: settings)
                ColorSettingsSection(settings: settings)
                DataSettingsSection(settings: settings, usageService: usageService)
                DebugSection()
                AboutSection()
            }
            .padding(24)
        }
        .navigationTitle("Settings")
    }
}

private struct DebugSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var seedStatus: String?

    var body: some View {
        GroupBox("Debug") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Seed mock data to test History and Plan Optimizer views.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Button("Seed 7 Days") { seed(days: 7) }
                        .buttonStyle(.bordered)
                    Button("Seed 30 Days") { seed(days: 30) }
                        .buttonStyle(.bordered)
                    Button("Clear History") { clearData() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                }

                if let status = seedStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
        }
    }

    private func seed(days: Int) {
        do {
            try MockDataSeeder.seedHistory(context: modelContext, days: days)
            seedStatus = "Seeded \(days) days of mock data."
        } catch {
            seedStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func clearData() {
        do {
            try MockDataSeeder.clearHistory(context: modelContext)
            seedStatus = "History cleared."
        } catch {
            seedStatus = "Error: \(error.localizedDescription)"
        }
    }
}

private struct MenuBarSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        GroupBox("Menu Bar") {
            VStack(alignment: .leading, spacing: 12) {
                TimerFormatPicker(settings: settings)

                Toggle("Show usage bars in menu bar", isOn: $settings.showUsageBars)
                    .toggleStyle(.switch)

                Toggle("Text shadow", isOn: $settings.showTextShadow)
                    .toggleStyle(.switch)

                Toggle("Show promo timer", isOn: $settings.showPromoTimer)
                    .toggleStyle(.switch)
            }
            .padding(8)
        }
    }
}

private struct TimerFormatPicker: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Timer format")
                .font(.subheadline.bold())

            HStack(spacing: 8) {
                ForEach(TimerFormat.allCases) { format in
                    FormatButton(format: format, isSelected: settings.timerFormat == format) {
                        settings.timerFormat = format
                    }
                }
            }
        }
    }
}

private struct FormatButton: View {
    let format: TimerFormat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(format.displayName)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ColorSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        GroupBox("Timer Colors") {
            VStack(alignment: .leading, spacing: 10) {
                ColorSwatchPicker(label: "Off-peak (2x)", selection: $settings.activeColor, defaultColor: .defaultGreen)
                ColorSwatchPicker(label: "Peak (1x)", selection: $settings.peakColor, defaultColor: .defaultRed)
            }
            .padding(8)
        }
    }
}

private struct DataSettingsSection: View {
    @Bindable var settings: AppSettings
    let usageService: UsageService

    var body: some View {
        GroupBox("Data & Refresh") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Refresh interval")
                        .font(.subheadline.bold())
                    Spacer()
                    Picker("", selection: $settings.refreshInterval) {
                        Text("1 min").tag(TimeInterval(60))
                        Text("2 min").tag(TimeInterval(120))
                        Text("5 min").tag(TimeInterval(300))
                        Text("10 min").tag(TimeInterval(600))
                        Text("15 min").tag(TimeInterval(900))
                    }
                    .frame(width: 120)
                    .onChange(of: settings.refreshInterval) { _, _ in
                        usageService.updateRefreshInterval()
                    }
                }
            }
            .padding(8)
        }
    }
}

private struct AboutSection: View {
    var body: some View {
        GroupBox("About") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Clausage")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("v\(UpdateService.currentVersion)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Text("Track your Claude usage, get plan recommendations, and never miss a promo.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
        }
    }
}

struct ColorSwatchPicker: View {
    let label: String
    @Binding var selection: TimerColor
    let defaultColor: TimerColor

    private static let presets: [TimerColor] = [
        TimerColor(red: 0.0, green: 0.60, blue: 0.15),
        TimerColor(red: 0.18, green: 0.80, blue: 0.35),
        TimerColor(red: 0.0, green: 0.55, blue: 0.85),
        TimerColor(red: 0.35, green: 0.35, blue: 0.95),
        TimerColor(red: 0.60, green: 0.20, blue: 0.85),
        TimerColor(red: 0.85, green: 0.15, blue: 0.10),
        TimerColor(red: 1.0, green: 0.40, blue: 0.0),
        TimerColor(red: 1.0, green: 0.65, blue: 0.0),
        TimerColor(red: 0.85, green: 0.85, blue: 0.85),
        TimerColor(red: 1.0, green: 1.0, blue: 1.0),
    ]

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.subheadline)
                .frame(width: 90, alignment: .leading)

            HStack(spacing: 5) {
                ForEach(Self.presets.indices, id: \.self) { i in
                    let preset = Self.presets[i]
                    Circle()
                        .fill(Color(nsColor: preset.nsColor))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .stroke(selection == preset ? Color.white : Color.clear, lineWidth: 2)
                        )
                        .overlay(
                            Circle()
                                .stroke(selection == preset ? Color.accentColor : Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                        .onTapGesture { selection = preset }
                }
            }
        }
    }
}
