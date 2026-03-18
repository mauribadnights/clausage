import Foundation
import SwiftData

#if DEBUG
enum MockDataSeeder {

    enum UsagePattern {
        case heavyUser      // Consistently high usage, frequently hits limits
        case lightUser      // Barely uses the plan
        case moderate       // Normal usage, rarely hits limits
        case limitHitter    // Extreme — hits 100% constantly

        var description: String {
            switch self {
            case .heavyUser: return "heavy user"
            case .lightUser: return "light user"
            case .moderate: return "moderate"
            case .limitHitter: return "limit hitter"
            }
        }
    }

    static func seedHistory(context: ModelContext, days: Int = 7, pattern: UsagePattern = .moderate) throws {
        try clearHistory(context: context)

        let now = Date()
        let sampleInterval: TimeInterval = 300 // 5 minutes
        let totalSamples = (days * 24 * 3600) / Int(sampleInterval)

        let fiveHourResetInterval: TimeInterval = 5 * 3600 // 5 hours in seconds
        let weeklyResetInterval: TimeInterval = 7 * 24 * 3600

        // Track accumulation within each reset window
        var fiveHourWindowStart = now.addingTimeInterval(-Double(totalSamples) * sampleInterval)
        var weeklyWindowStart = fiveHourWindowStart
        var fiveHourAccum: Double = 0
        var weeklyAccum: Double = 0

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current

        for i in 0..<totalSamples {
            let timestamp = now.addingTimeInterval(-Double(totalSamples - i) * sampleInterval)
            let hour = cal.component(.hour, from: timestamp)
            let weekday = cal.component(.weekday, from: timestamp)
            let isWeekend = weekday == 1 || weekday == 7

            // Reset 5-hour window
            if timestamp.timeIntervalSince(fiveHourWindowStart) >= fiveHourResetInterval {
                fiveHourWindowStart = timestamp
                fiveHourAccum = 0
            }

            // Reset weekly window
            if timestamp.timeIntervalSince(weeklyWindowStart) >= weeklyResetInterval {
                weeklyWindowStart = timestamp
                weeklyAccum = 0
            }

            // How much usage to add this sample (based on pattern + time of day)
            let usageRate = sampleUsageRate(pattern: pattern, hour: hour, isWeekend: isWeekend)
            fiveHourAccum = min(100, fiveHourAccum + usageRate)
            weeklyAccum = min(100, weeklyAccum + usageRate * 0.15) // Weekly accumulates slower

            let fiveHourResetsAt = fiveHourWindowStart.addingTimeInterval(fiveHourResetInterval)
            let weeklyResetsAt = weeklyWindowStart.addingTimeInterval(weeklyResetInterval)

            let snapshot = UsageSnapshot(
                timestamp: timestamp,
                fiveHourPercent: fiveHourAccum,
                weeklyPercent: weeklyAccum,
                fiveHourResetsAt: fiveHourResetsAt,
                weeklyResetsAt: weeklyResetsAt
            )
            context.insert(snapshot)
        }

        try context.save()
    }

    static func clearHistory(context: ModelContext) throws {
        try context.delete(model: UsageSnapshot.self)
        try context.save()
    }

    /// Returns how much usage % to add per 5-minute sample
    private static func sampleUsageRate(pattern: UsagePattern, hour: Int, isWeekend: Bool) -> Double {
        let isActiveHour = !isWeekend && (hour >= 9 && hour <= 18)
        let isEveningHour = hour >= 19 && hour <= 22
        let isSleepHour = hour >= 23 || hour <= 6

        switch pattern {
        case .heavyUser:
            if isSleepHour { return Double.random(in: 0...0.2) }
            if isActiveHour { return Double.random(in: 1.5...3.5) }
            if isEveningHour { return Double.random(in: 0.8...2.0) }
            return Double.random(in: 0.3...1.2) // weekend daytime

        case .lightUser:
            if isSleepHour { return 0 }
            if isActiveHour { return Double.random(in: 0.1...0.5) }
            return Double.random(in: 0...0.2)

        case .moderate:
            if isSleepHour { return Double.random(in: 0...0.1) }
            if isActiveHour { return Double.random(in: 0.6...1.8) }
            if isEveningHour { return Double.random(in: 0.3...0.8) }
            return Double.random(in: 0.1...0.5)

        case .limitHitter:
            if isSleepHour { return Double.random(in: 0.2...0.8) }
            if isActiveHour { return Double.random(in: 3.0...6.0) }
            if isEveningHour { return Double.random(in: 1.5...3.5) }
            return Double.random(in: 0.8...2.5)
        }
    }
}
#endif
