import Foundation
import SwiftData

@Model
final class UsageSnapshot {
    var timestamp: Date
    var fiveHourPercent: Double
    var weeklyPercent: Double
    var fiveHourResetsAt: Date?
    var weeklyResetsAt: Date?

    init(
        timestamp: Date = Date(),
        fiveHourPercent: Double,
        weeklyPercent: Double,
        fiveHourResetsAt: Date? = nil,
        weeklyResetsAt: Date? = nil
    ) {
        self.timestamp = timestamp
        self.fiveHourPercent = fiveHourPercent
        self.weeklyPercent = weeklyPercent
        self.fiveHourResetsAt = fiveHourResetsAt
        self.weeklyResetsAt = weeklyResetsAt
    }
}
