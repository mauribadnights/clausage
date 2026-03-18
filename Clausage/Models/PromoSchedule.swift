import Foundation

enum PromoStatus: Equatable {
    case notStarted
    case active2x
    case peak1x
    case ended
    case disabled
}

/// Promo schedule loaded from remote/bundled config.
/// Dates and peak hours are configurable — no hardcoded values.
final class PromoSchedule {
    static let shared = PromoSchedule()

    private(set) var promoStart: Date = .distantPast
    private(set) var promoEnd: Date = .distantPast
    private(set) var peakStartHour: Int = 12
    private(set) var peakEndHour: Int = 18
    private(set) var enabled: Bool = false

    private var utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return cal
    }()

    private init() {}

    func update(from config: PromoConfig?) {
        guard let config, config.enabled else {
            enabled = false
            return
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        guard let start = iso.date(from: config.startUTC),
              let end = iso.date(from: config.endUTC) else {
            enabled = false
            return
        }

        promoStart = start
        promoEnd = end
        peakStartHour = config.peakStartHourUTC
        peakEndHour = config.peakEndHourUTC
        enabled = true
    }

    func currentStatus(at date: Date = Date()) -> PromoStatus {
        guard enabled else { return .disabled }
        if date < promoStart { return .notStarted }
        if date > promoEnd { return .ended }

        let weekday = utcCalendar.component(.weekday, from: date) // 1=Sun, 7=Sat
        let isWeekend = weekday == 1 || weekday == 7

        if isWeekend { return .active2x }

        let hour = utcCalendar.component(.hour, from: date)
        if hour >= peakStartHour && hour < peakEndHour {
            return .peak1x
        }
        return .active2x
    }

    func nextTransition(from date: Date = Date()) -> (date: Date, nextStatus: PromoStatus)? {
        let status = currentStatus(at: date)

        switch status {
        case .disabled:
            return nil
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

    private func nextTransitionFrom2x(at date: Date) -> (date: Date, nextStatus: PromoStatus) {
        let weekday = utcCalendar.component(.weekday, from: date)
        let hour = utcCalendar.component(.hour, from: date)

        if weekday == 1 || weekday == 7 {
            guard let nextMonday = utcCalendar.nextDate(after: date, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime),
                  let peakMonday = utcCalendar.date(bySettingHour: peakStartHour, minute: 0, second: 0, of: nextMonday) else {
                return (promoEnd, .ended)
            }
            if peakMonday > promoEnd { return (promoEnd, .ended) }
            return (peakMonday, .peak1x)
        }

        if hour < peakStartHour {
            guard var peakToday = utcCalendar.date(bySettingHour: peakStartHour, minute: 0, second: 0, of: date) else {
                return (promoEnd, .ended)
            }
            if peakToday <= date { peakToday = peakToday.addingTimeInterval(1) }
            if peakToday > promoEnd { return (promoEnd, .ended) }
            return (peakToday, .peak1x)
        } else {
            guard let tomorrow = utcCalendar.date(byAdding: .day, value: 1, to: date) else {
                return (promoEnd, .ended)
            }
            let tomorrowWeekday = utcCalendar.component(.weekday, from: tomorrow)

            if tomorrowWeekday == 1 || tomorrowWeekday == 7 {
                guard let nextMonday = utcCalendar.nextDate(after: date, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime),
                      let peakMonday = utcCalendar.date(bySettingHour: peakStartHour, minute: 0, second: 0, of: nextMonday) else {
                    return (promoEnd, .ended)
                }
                if peakMonday > promoEnd { return (promoEnd, .ended) }
                return (peakMonday, .peak1x)
            } else {
                guard let peakTomorrow = utcCalendar.date(bySettingHour: peakStartHour, minute: 0, second: 0, of: tomorrow) else {
                    return (promoEnd, .ended)
                }
                if peakTomorrow > promoEnd { return (promoEnd, .ended) }
                return (peakTomorrow, .peak1x)
            }
        }
    }

    private func nextTransitionFromPeak(at date: Date) -> (date: Date, nextStatus: PromoStatus) {
        guard var peakEnd = utcCalendar.date(bySettingHour: peakEndHour, minute: 0, second: 0, of: date) else {
            return (promoEnd, .ended)
        }
        if peakEnd <= date { peakEnd = peakEnd.addingTimeInterval(1) }
        if peakEnd > promoEnd { return (promoEnd, .ended) }
        return (peakEnd, .active2x)
    }

    func peakHoursLocalString() -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "h:mm a"

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let today = Date()
        guard let startDate = cal.date(bySettingHour: peakStartHour, minute: 0, second: 0, of: today),
              let endDate = cal.date(bySettingHour: peakEndHour, minute: 0, second: 0, of: today) else {
            return "Unknown"
        }

        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)
        let tz = TimeZone.current.abbreviation() ?? "local"
        return "\(start) - \(end) \(tz)"
    }

    func promoEndLocalString() -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: promoEnd)
    }
}
