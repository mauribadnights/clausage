import SwiftUI
import SwiftData
import Charts

enum HistoryRange: String, CaseIterable {
    case day = "24h"
    case week = "7d"
    case month = "30d"
    case all = "All"

    var interval: TimeInterval? {
        switch self {
        case .day: return 24 * 3600
        case .week: return 7 * 24 * 3600
        case .month: return 30 * 24 * 3600
        case .all: return nil
        }
    }
}

struct HistoryView: View {
    @Query(sort: \UsageSnapshot.timestamp, order: .forward) private var allSnapshots: [UsageSnapshot]
    @State private var selectedRange: HistoryRange = .week

    private var filteredSnapshots: [UsageSnapshot] {
        guard let interval = selectedRange.interval else { return allSnapshots }
        let cutoff = Date().addingTimeInterval(-interval)
        return allSnapshots.filter { $0.timestamp > cutoff }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Range picker
                Picker("Time Range", selection: $selectedRange) {
                    ForEach(HistoryRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                if filteredSnapshots.isEmpty {
                    ContentUnavailableView(
                        "No Usage Data Yet",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Usage data is recorded every 5 minutes. Check back later.")
                    )
                    .frame(minHeight: 300)
                } else {
                    // 5-hour usage chart
                    ChartCard(
                        title: "5-Hour Usage",
                        snapshots: filteredSnapshots,
                        keyPath: \.fiveHourPercent,
                        color: .blue
                    )

                    // Weekly usage chart
                    ChartCard(
                        title: "Weekly Usage",
                        snapshots: filteredSnapshots,
                        keyPath: \.weeklyPercent,
                        color: .purple
                    )

                    // Stats summary
                    StatsSummary(snapshots: filteredSnapshots)
                }
            }
            .padding(24)
        }
        .navigationTitle("History")
    }
}

struct ChartCard: View {
    let title: String
    let snapshots: [UsageSnapshot]
    let keyPath: KeyPath<UsageSnapshot, Double>
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Chart(snapshots, id: \.timestamp) { snapshot in
                LineMark(
                    x: .value("Time", snapshot.timestamp),
                    y: .value("Usage %", snapshot[keyPath: keyPath])
                )
                .foregroundStyle(color.gradient)
                .interpolationMethod(.monotone)

                AreaMark(
                    x: .value("Time", snapshot.timestamp),
                    y: .value("Usage %", snapshot[keyPath: keyPath])
                )
                .foregroundStyle(color.opacity(0.1).gradient)
                .interpolationMethod(.monotone)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)%")
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day().hour())
                }
            }
            .frame(height: 200)

            // Threshold lines annotation
            HStack(spacing: 16) {
                let values = snapshots.map { $0[keyPath: keyPath] }
                let avg = values.reduce(0, +) / Double(max(values.count, 1))
                let maxVal = values.max() ?? 0

                Label("Avg: \(Int(avg))%", systemImage: "minus")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Label("Max: \(Int(maxVal))%", systemImage: "arrow.up")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Label("\(snapshots.count) samples", systemImage: "number")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct StatsSummary: View {
    let snapshots: [UsageSnapshot]

    private var timesHitFiveHourLimit: Int {
        snapshots.filter { $0.fiveHourPercent >= 95 }.count
    }

    private var timesHitWeeklyLimit: Int {
        snapshots.filter { $0.weeklyPercent >= 95 }.count
    }

    private var avgFiveHour: Double {
        let values = snapshots.map(\.fiveHourPercent)
        return values.reduce(0, +) / Double(max(values.count, 1))
    }

    private var avgWeekly: Double {
        let values = snapshots.map(\.weeklyPercent)
        return values.reduce(0, +) / Double(max(values.count, 1))
    }

    var body: some View {
        HStack(spacing: 16) {
            StatBox(title: "Avg 5-Hour", value: "\(Int(avgFiveHour))%", icon: "clock")
            StatBox(title: "Avg Weekly", value: "\(Int(avgWeekly))%", icon: "calendar")
            StatBox(title: "Hit 5h Limit", value: "\(timesHitFiveHourLimit)x", icon: "exclamationmark.triangle")
            StatBox(title: "Hit Weekly Limit", value: "\(timesHitWeeklyLimit)x", icon: "exclamationmark.triangle")
        }
    }
}

struct StatBox: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
