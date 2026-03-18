import Foundation

enum PromoStatus: Equatable {
    case notStarted
    case active2x
    case peak1x
    case ended
}

struct PromoSchedule {
    // Promo period: March 13, 2026 00:00 UTC -> March 28, 2026 06:59 UTC
    static let promoStart: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 13
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar.current.date(from: components)!
    }()

    static let promoEnd: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 28
        components.hour = 6
        components.minute = 59
        components.second = 59
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar.current.date(from: components)!
    }()

    // Peak hours: Weekdays 12:00-18:00 UTC
    static let peakStartHour = 12
    static let peakEndHour = 18

    private static var utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    static func currentStatus(at date: Date = Date()) -> PromoStatus {
        if date < promoStart { return .notStarted }
        if date > promoEnd { return .ended }

        let weekday = utcCalendar.component(.weekday, from: date)
        let isWeekend = weekday == 1 || weekday == 7

        if isWeekend { return .active2x }

        let hour = utcCalendar.component(.hour, from: date)
        if hour >= peakStartHour && hour < peakEndHour {
            return .peak1x
        }
        return .active2x
    }

    static func nextTransition(from date: Date = Date()) -> (date: Date, nextStatus: PromoStatus)? {
        let status = currentStatus(at: date)

        switch status {
        case .notStarted:
            return (promoStart, .active2x)
        case .ended:
            return nil
        case .active2x:
            return nextTransitionFrom2x(at: date)
        case .peak1x:
            return nextTransitionFromPeak(at: date)
        }
    }

    private static func nextTransitionFrom2x(at date: Date) -> (date: Date, nextStatus: PromoStatus) {
        let weekday = utcCalendar.component(.weekday, from: date)
        let hour = utcCalendar.component(.hour, from: date)

        if weekday == 1 || weekday == 7 {
            var nextMonday = utcCalendar.nextDate(after: date, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)!
            nextMonday = utcCalendar.date(bySettingHour: peakStartHour, minute: 0, second: 0, of: nextMonday)!
            if nextMonday > promoEnd { return (promoEnd, .ended) }
            return (nextMonday, .peak1x)
        }

        if hour < peakStartHour {
            var peakToday = utcCalendar.date(bySettingHour: peakStartHour, minute: 0, second: 0, of: date)!
            if peakToday <= date {
                peakToday = peakToday.addingTimeInterval(1)
            }
            if peakToday > promoEnd { return (promoEnd, .ended) }
            return (peakToday, .peak1x)
        } else {
            let tomorrow = utcCalendar.date(byAdding: .day, value: 1, to: date)!
            let tomorrowWeekday = utcCalendar.component(.weekday, from: tomorrow)

            if tomorrowWeekday == 1 || tomorrowWeekday == 7 {
                let nextMonday = utcCalendar.nextDate(after: date, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)!
                let peakMonday = utcCalendar.date(bySettingHour: peakStartHour, minute: 0, second: 0, of: nextMonday)!
                if peakMonday > promoEnd { return (promoEnd, .ended) }
                return (peakMonday, .peak1x)
            } else {
                let peakTomorrow = utcCalendar.date(bySettingHour: peakStartHour, minute: 0, second: 0, of: tomorrow)!
                if peakTomorrow > promoEnd { return (promoEnd, .ended) }
                return (peakTomorrow, .peak1x)
            }
        }
    }

    private static func nextTransitionFromPeak(at date: Date) -> (date: Date, nextStatus: PromoStatus) {
        var peakEnd = utcCalendar.date(bySettingHour: peakEndHour, minute: 0, second: 0, of: date)!
        if peakEnd <= date {
            peakEnd = peakEnd.addingTimeInterval(1)
        }
        if peakEnd > promoEnd { return (promoEnd, .ended) }
        return (peakEnd, .active2x)
    }

    static func peakHoursLocalString() -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "h:mm a"

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = Date()
        let startDate = cal.date(bySettingHour: peakStartHour, minute: 0, second: 0, of: today)!
        let endDate = cal.date(bySettingHour: peakEndHour, minute: 0, second: 0, of: today)!

        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)
        let tz = TimeZone.current.abbreviation() ?? "local"
        return "\(start) - \(end) \(tz)"
    }

    static func promoEndLocalString() -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: promoEnd)
    }
}
