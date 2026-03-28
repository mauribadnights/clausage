import Foundation
import AppKit

enum TimerFormat: String, CaseIterable, Identifiable {
    case full       // 1:32:42
    case compact    // 1:32
    case labeled    // 1h 32m
    case minimal    // 1h32m

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .full: return "1:32:42"
        case .compact: return "1:32"
        case .labeled: return "1h 32m"
        case .minimal: return "1h32m"
        }
    }

    func format(_ interval: TimeInterval) -> String {
        guard interval > 0 else {
            switch self {
            case .full: return "0:00:00"
            case .compact: return "0:00"
            case .labeled: return "0h 0m"
            case .minimal: return "0h0m"
            }
        }

        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days)d \(remainingHours)h"
        }

        switch self {
        case .full:
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        case .compact:
            return String(format: "%d:%02d", hours, minutes)
        case .labeled:
            return "\(hours)h \(minutes)m"
        case .minimal:
            return "\(hours)h\(String(format: "%02d", minutes))m"
        }
    }
}

struct TimerColor: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: 1.0)
    }

    func save(prefix: String) {
        UserDefaults.standard.set(red, forKey: "\(prefix)_r")
        UserDefaults.standard.set(green, forKey: "\(prefix)_g")
        UserDefaults.standard.set(blue, forKey: "\(prefix)_b")
    }

    static func load(prefix: String, fallback: TimerColor) -> TimerColor {
        guard UserDefaults.standard.object(forKey: "\(prefix)_r") != nil else { return fallback }
        return TimerColor(
            red: UserDefaults.standard.double(forKey: "\(prefix)_r"),
            green: UserDefaults.standard.double(forKey: "\(prefix)_g"),
            blue: UserDefaults.standard.double(forKey: "\(prefix)_b")
        )
    }

    static let defaultGreen = TimerColor(red: 0.0, green: 0.60, blue: 0.15)
    static let defaultRed = TimerColor(red: 0.85, green: 0.15, blue: 0.10)
}

struct PlanChange: Codable, Equatable {
    let date: Date
    let planId: String
}

@Observable
final class AppSettings {
    static let shared = AppSettings()

    var timerFormat: TimerFormat {
        didSet { UserDefaults.standard.set(timerFormat.rawValue, forKey: "timerFormat") }
    }

    var showUsageBars: Bool {
        didSet { UserDefaults.standard.set(showUsageBars, forKey: "showUsageBars") }
    }

    var showTextShadow: Bool {
        didSet { UserDefaults.standard.set(showTextShadow, forKey: "showTextShadow") }
    }

    var activeColor: TimerColor {
        didSet { activeColor.save(prefix: "activeColor") }
    }

    var peakColor: TimerColor {
        didSet { peakColor.save(prefix: "peakColor") }
    }

    var showPromoTimer: Bool {
        didSet {
            UserDefaults.standard.set(showPromoTimer, forKey: "showPromoTimer")
            if showPromoTimer { showMenuBarPercent = false }
        }
    }

    var currentPlanId: String {
        didSet { UserDefaults.standard.set(currentPlanId, forKey: "currentPlanId") }
    }

    var planHistory: [PlanChange] {
        didSet { savePlanHistory() }
    }

    func activePlanId(at date: Date) -> String {
        return planHistory
            .filter { $0.date <= date }
            .max(by: { $0.date < $1.date })?
            .planId ?? currentPlanId
    }

    private func savePlanHistory() {
        if let data = try? JSONEncoder().encode(planHistory) {
            UserDefaults.standard.set(data, forKey: "planHistory")
        }
    }

    private static func loadPlanHistory() -> [PlanChange] {
        guard let data = UserDefaults.standard.data(forKey: "planHistory"),
              let history = try? JSONDecoder().decode([PlanChange].self, from: data) else {
            return []
        }
        return history.sorted(by: { $0.date < $1.date })
    }

    var showMenuBarPercent: Bool {
        didSet {
            UserDefaults.standard.set(showMenuBarPercent, forKey: "showMenuBarPercent")
            if showMenuBarPercent { showPromoTimer = false }
        }
    }

    /// Which usage to show as % in menu bar: "5hour" or "weekly"
    var menuBarPercentSource: String {
        didSet { UserDefaults.standard.set(menuBarPercentSource, forKey: "menuBarPercentSource") }
    }

    /// Font size for timer/percent text in menu bar (8-14)
    var menuBarFontSize: Double {
        didSet { UserDefaults.standard.set(menuBarFontSize, forKey: "menuBarFontSize") }
    }

    /// Bar width in bars-only mode (20-60)
    var menuBarBarWidth: Double {
        didSet { UserDefaults.standard.set(menuBarBarWidth, forKey: "menuBarBarWidth") }
    }

    /// Bar height (1-5)
    var menuBarBarHeight: Double {
        didSet { UserDefaults.standard.set(menuBarBarHeight, forKey: "menuBarBarHeight") }
    }

    var refreshInterval: TimeInterval {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval") }
    }

    /// Base URL of the remote history API (e.g. "http://100.76.199.15:8199")
    var remoteHistoryURL: String {
        didSet { UserDefaults.standard.set(remoteHistoryURL, forKey: "remoteHistoryURL") }
    }

    /// When true, clausage syncs missing history from the remote source on launch and wake.
    var remoteHistoryEnabled: Bool {
        didSet { UserDefaults.standard.set(remoteHistoryEnabled, forKey: "remoteHistoryEnabled") }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "timerFormat") ?? TimerFormat.full.rawValue
        self.timerFormat = TimerFormat(rawValue: saved) ?? .full

        if UserDefaults.standard.object(forKey: "showUsageBars") == nil {
            self.showUsageBars = true
        } else {
            self.showUsageBars = UserDefaults.standard.bool(forKey: "showUsageBars")
        }

        if UserDefaults.standard.object(forKey: "showTextShadow") == nil {
            self.showTextShadow = false
        } else {
            self.showTextShadow = UserDefaults.standard.bool(forKey: "showTextShadow")
        }

        self.activeColor = TimerColor.load(prefix: "activeColor", fallback: .defaultGreen)
        self.peakColor = TimerColor.load(prefix: "peakColor", fallback: .defaultRed)

        if UserDefaults.standard.object(forKey: "showPromoTimer") == nil {
            self.showPromoTimer = true
        } else {
            self.showPromoTimer = UserDefaults.standard.bool(forKey: "showPromoTimer")
        }

        self.currentPlanId = UserDefaults.standard.string(forKey: "currentPlanId") ?? "pro"
        self.planHistory = Self.loadPlanHistory()

        if UserDefaults.standard.object(forKey: "showMenuBarPercent") == nil {
            self.showMenuBarPercent = false
        } else {
            self.showMenuBarPercent = UserDefaults.standard.bool(forKey: "showMenuBarPercent")
        }

        self.menuBarPercentSource = UserDefaults.standard.string(forKey: "menuBarPercentSource") ?? "5hour"

        if UserDefaults.standard.object(forKey: "menuBarFontSize") == nil {
            self.menuBarFontSize = 10
        } else {
            self.menuBarFontSize = UserDefaults.standard.double(forKey: "menuBarFontSize")
        }

        if UserDefaults.standard.object(forKey: "menuBarBarWidth") == nil {
            self.menuBarBarWidth = 36
        } else {
            self.menuBarBarWidth = UserDefaults.standard.double(forKey: "menuBarBarWidth")
        }

        if UserDefaults.standard.object(forKey: "menuBarBarHeight") == nil {
            self.menuBarBarHeight = 2.5
        } else {
            self.menuBarBarHeight = UserDefaults.standard.double(forKey: "menuBarBarHeight")
        }

        if UserDefaults.standard.object(forKey: "refreshInterval") == nil {
            self.refreshInterval = 300
        } else {
            self.refreshInterval = UserDefaults.standard.double(forKey: "refreshInterval")
        }

        self.remoteHistoryURL = UserDefaults.standard.string(forKey: "remoteHistoryURL") ?? ""
        self.remoteHistoryEnabled = UserDefaults.standard.bool(forKey: "remoteHistoryEnabled")
    }
}
