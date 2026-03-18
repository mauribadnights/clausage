import Foundation
import SwiftData

enum MockDataSeeder {
    /// Seeds realistic usage history data for testing.
    /// Simulates 7 days of usage data with realistic patterns:
    /// - Higher usage during work hours
    /// - Lower usage at night and weekends
    /// - Occasional limit hits
    /// - Natural variance
    static func seedHistory(context: ModelContext, days: Int = 7) throws {
        // Clear existing mock data first
        try clearHistory(context: context)

        let now = Date()
        let intervalBetweenSamples: TimeInterval = 300 // 5 minutes
        let totalSamples = (days * 24 * 3600) / Int(intervalBetweenSamples)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current

        for i in 0..<totalSamples {
            let timestamp = now.addingTimeInterval(-Double(totalSamples - i) * intervalBetweenSamples)
            let hour = cal.component(.hour, from: timestamp)
            let weekday = cal.component(.weekday, from: timestamp)
            let isWeekend = weekday == 1 || weekday == 7

            // Base usage varies by time of day and day of week
            let baseFiveHour = fiveHourUsage(hour: hour, isWeekend: isWeekend)
            let baseWeekly = weeklyUsage(dayOffset: i / (24 * 12), totalDays: days)

            // Add realistic noise
            let noise1 = Double.random(in: -8...8)
            let noise2 = Double.random(in: -5...5)

            let fiveHour = max(0, min(100, baseFiveHour + noise1))
            let weekly = max(0, min(100, baseWeekly + noise2))

            let snapshot = UsageSnapshot(
                timestamp: timestamp,
                fiveHourPercent: fiveHour,
                weeklyPercent: weekly,
                fiveHourResetsAt: timestamp.addingTimeInterval(Double.random(in: 1800...18000)),
                weeklyResetsAt: nextWeeklyReset(from: timestamp)
            )
            context.insert(snapshot)
        }

        try context.save()
    }

    static func clearHistory(context: ModelContext) throws {
        try context.delete(model: UsageSnapshot.self)
        try context.save()
    }

    /// 5-hour usage pattern: spikes during work hours, low at night
    private static func fiveHourUsage(hour: Int, isWeekend: Bool) -> Double {
        if isWeekend {
            // Weekend: moderate, sporadic usage
            switch hour {
            case 0...8: return Double.random(in: 5...15)
            case 9...12: return Double.random(in: 20...50)
            case 13...18: return Double.random(in: 30...65)
            case 19...22: return Double.random(in: 15...40)
            default: return Double.random(in: 5...10)
            }
        } else {
            // Weekday: heavy usage during work hours
            switch hour {
            case 0...6: return Double.random(in: 2...10)
            case 7...8: return Double.random(in: 15...35)
            case 9...12: return Double.random(in: 45...85) // Peak coding hours
            case 13...14: return Double.random(in: 30...55) // Lunch dip
            case 15...18: return Double.random(in: 50...92) // Afternoon push
            case 19...21: return Double.random(in: 20...45) // Evening wind-down
            default: return Double.random(in: 5...15)
            }
        }
    }

    /// Weekly usage pattern: gradually increases through the week
    private static func weeklyUsage(dayOffset: Int, totalDays: Int) -> Double {
        let progress = Double(dayOffset) / Double(max(totalDays, 1))
        let base = 15 + progress * 55 // Ramps from ~15% to ~70% over the period
        return base
    }

    private static func nextWeeklyReset(from date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        // Next Monday at midnight
        var next = cal.nextDate(after: date, matching: DateComponents(hour: 0, weekday: 2), matchingPolicy: .nextTime)!
        if next <= date {
            next = cal.date(byAdding: .weekOfYear, value: 1, to: next)!
        }
        return next
    }
}
