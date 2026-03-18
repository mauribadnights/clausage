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

    /// Appropriate x-axis date format for this range
    var dateFormat: Date.FormatStyle {
        switch self {
        case .day:
            return .dateTime.hour(.defaultDigits(amPM: .abbreviated))
        case .week:
            return .dateTime.weekday(.abbreviated).hour(.defaultDigits(amPM: .abbreviated))
        case .month:
            return .dateTime.month(.abbreviated).day()
        case .all:
            return .dateTime.month(.abbreviated).day()
        }
    }

    var desiredTickCount: Int {
        switch self {
        case .day: return 6
        case .week: return 7
        case .month: return 6
        case .all: return 8
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
                    ChartCard(
                        title: "5-Hour Usage",
                        snapshots: filteredSnapshots,
                        keyPath: \.fiveHourPercent,
                        color: .blue,
                        range: selectedRange
                    )

                    ChartCard(
                        title: "Weekly Usage",
                        snapshots: filteredSnapshots,
                        keyPath: \.weeklyPercent,
                        color: .purple,
                        range: selectedRange
                    )

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
    let range: HistoryRange

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
                AxisMarks(values: .automatic(desiredCount: range.desiredTickCount)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: range.dateFormat)
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 200)

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

    private var pctAtFiveHourLimit: Double {
        guard !snapshots.isEmpty else { return 0 }
        let hits = snapshots.filter { $0.fiveHourPercent >= 95 }.count
        return Double(hits) / Double(snapshots.count) * 100
    }

    private var pctAtWeeklyLimit: Double {
        guard !snapshots.isEmpty else { return 0 }
        let hits = snapshots.filter { $0.weeklyPercent >= 95 }.count
        return Double(hits) / Double(snapshots.count) * 100
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
            StatBox(title: "At 5h Limit", value: "\(Int(pctAtFiveHourLimit))%", icon: "exclamationmark.triangle")
            StatBox(title: "At Weekly Limit", value: "\(Int(pctAtWeeklyLimit))%", icon: "exclamationmark.triangle")
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
