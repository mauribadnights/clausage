import Foundation
import AppKit
import Combine

@Observable
final class AppState {
    var menuBarText: String = "..."
    var menuBarImage: NSImage = AppState.makeMenuBarImage(text: "...", color: .labelColor)
    var status: PromoStatus = .notStarted
    var countdownText: String = ""
    var statusDescription: String = ""
    var nextTransitionDescription: String = ""

    // Usage percentages for menu bar bars
    var usageFiveHour: Double?
    var usageWeekly: Double?

    private var timer: Timer?

    init() {
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            let s = self
            Task { @MainActor in s?.update() }
        }
    }

    func bindUsage(_ service: UsageService) {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self, weak service] _ in
            let s = self
            let svc = service
            Task { @MainActor in
                guard let s, let svc else { return }
                s.usageFiveHour = svc.usage.fiveHourPercent
                s.usageWeekly = svc.usage.weeklyPercent
            }
        }
    }

    private func update() {
        let now = Date()
        let settings = AppSettings.shared
        let fmt = settings.timerFormat
        status = PromoSchedule.shared.currentStatus(at: now)

        let showTimer = settings.showPromoTimer && status != .ended && status != .disabled
        if showTimer {
            updatePromoState(now: now, fmt: fmt)
        } else {
            let percentValue: Double? = settings.menuBarPercentSource == "weekly" ? usageWeekly : usageFiveHour
            if settings.showMenuBarPercent, let pct = percentValue {
                menuBarText = "\(Int(pct))%"
            } else if !settings.showUsageBars {
                // No bars and no percent — show something
                if let pct = percentValue ?? usageFiveHour {
                    menuBarText = "\(Int(pct))%"
                } else {
                    menuBarText = "..."
                }
            } else {
                menuBarText = "" // Bars-only mode
            }
            statusDescription = "Claude Usage"
            countdownText = ""
            nextTransitionDescription = ""
        }

        let showBars = settings.showUsageBars
        let showText = !menuBarText.isEmpty
        menuBarImage = AppState.makeMenuBarImage(
            text: showText ? menuBarText : nil,
            color: menuBarColor,
            fiveHourPct: showBars ? usageFiveHour : nil,
            weeklyPct: showBars ? usageWeekly : nil
        )
    }

    private func updatePromoState(now: Date, fmt: TimerFormat) {
        switch status {
        case .disabled:
            return // Should not be called when disabled
        case .notStarted:
            let interval = PromoSchedule.shared.promoStart.timeIntervalSince(now)
            let formatted = fmt.format(interval)
            menuBarText = formatted
            statusDescription = "Promo hasn't started yet"
            countdownText = "Starts in \(formatted)"
            nextTransitionDescription = "2x usage begins when promo starts"

        case .active2x:
            if let transition = PromoSchedule.shared.nextTransition(from: now) {
                let interval = transition.date.timeIntervalSince(now)
                let formatted = fmt.format(interval)
                menuBarText = formatted
                countdownText = formatted
                if transition.nextStatus == .peak1x {
                    nextTransitionDescription = "Peak hours (1x) in \(formatted)"
                } else if transition.nextStatus == .ended {
                    nextTransitionDescription = "Promo ends in \(formatted)"
                }
            } else {
                menuBarText = "2x"
                countdownText = ""
            }
            statusDescription = "2x Usage Active"

        case .peak1x:
            if let transition = PromoSchedule.shared.nextTransition(from: now) {
                let interval = transition.date.timeIntervalSince(now)
                let formatted = fmt.format(interval)
                menuBarText = formatted
                countdownText = formatted
                nextTransitionDescription = "2x returns in \(formatted)"
            } else {
                menuBarText = "1x"
                countdownText = ""
            }
            statusDescription = "Peak Hours (1x)"

        case .ended:
            if let fiveHour = usageFiveHour {
                menuBarText = "\(Int(fiveHour))%"
            } else {
                menuBarText = "Done"
            }
            statusDescription = "Promo has ended"
            countdownText = ""
            nextTransitionDescription = ""
        }
    }

    private var menuBarColor: NSColor {
        let settings = AppSettings.shared
        switch status {
        case .active2x: return settings.activeColor.nsColor
        case .peak1x: return settings.peakColor.nsColor
        case .notStarted, .ended, .disabled: return .labelColor
        }
    }

    static func makeMenuBarImage(
        text: String?,
        color: NSColor,
        fiveHourPct: Double? = nil,
        weeklyPct: Double? = nil
    ) -> NSImage {
        let settings = AppSettings.shared
        let hasBars = fiveHourPct != nil || weeklyPct != nil
        let hasText = text != nil && !text!.isEmpty
        let barHeight: CGFloat = settings.menuBarBarHeight
        let barSpacing: CGFloat = max(1, barHeight * 0.6)
        let padding: CGFloat = 2

        if hasText {
            // Text + optional bars mode
            let font = NSFont.monospacedDigitSystemFont(ofSize: settings.menuBarFontSize, weight: .bold)
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
            ]

            if AppSettings.shared.showTextShadow {
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
                shadow.shadowOffset = NSSize(width: 0, height: -0.5)
                shadow.shadowBlurRadius = 1.5
                attributes[.shadow] = shadow
            }

            let attributedString = NSAttributedString(string: text!, attributes: attributes)
            let textSize = attributedString.size()

            let bottomMargin: CGFloat = 1
            let textToBarGap: CGFloat = 0.5
            let barsArea: CGFloat = hasBars ? (barHeight * 2 + barSpacing + textToBarGap + bottomMargin) : 0

            let imageWidth = ceil(textSize.width) + padding * 2
            let imageHeight = ceil(textSize.height) + padding + barsArea

            let image = NSImage(size: NSSize(width: imageWidth, height: imageHeight))
            image.lockFocus()

            attributedString.draw(at: NSPoint(x: padding, y: barsArea))

            if hasBars {
                let barWidth = imageWidth - padding * 2
                let barX = padding
                drawUsageBar(x: barX, y: bottomMargin + barHeight + barSpacing, width: barWidth, height: barHeight, pct: fiveHourPct)
                drawUsageBar(x: barX, y: bottomMargin, width: barWidth, height: barHeight, pct: weeklyPct)
            }

            image.unlockFocus()
            image.isTemplate = false
            return image
        } else {
            // Bars-only mode — compact, no text
            let barWidth: CGFloat = settings.menuBarBarWidth
            let totalHeight = barHeight * 2 + barSpacing
            let imageWidth = barWidth + padding * 2
            let imageHeight = totalHeight + padding * 2

            let image = NSImage(size: NSSize(width: imageWidth, height: imageHeight))
            image.lockFocus()

            let barX = padding
            drawUsageBar(x: barX, y: padding + barHeight + barSpacing, width: barWidth, height: barHeight, pct: fiveHourPct)
            drawUsageBar(x: barX, y: padding, width: barWidth, height: barHeight, pct: weeklyPct)

            image.unlockFocus()
            image.isTemplate = false
            return image
        }
    }

    private static func drawUsageBar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, pct: Double?) {
        let radius = height / 2
        let trackRect = NSRect(x: x, y: y, width: width, height: height)
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius)

        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        trackPath.fill()

        NSColor.labelColor.withAlphaComponent(0.35).setStroke()
        trackPath.lineWidth = 0.5
        trackPath.stroke()

        guard let pct = pct, pct > 0 else { return }

        let fraction = min(pct / 100.0, 1.0)
        let fillWidth = max(width * fraction, height)
        let fillColor = usageBarColor(pct)
        fillColor.setFill()
        let fillRect = NSRect(x: x, y: y, width: fillWidth, height: height)
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
    }

    private static func usageBarColor(_ pct: Double) -> NSColor {
        if pct < 50 { return NSColor(red: 0.18, green: 0.80, blue: 0.35, alpha: 1.0) }
        if pct < 80 { return NSColor(red: 1.0, green: 0.65, blue: 0.0, alpha: 1.0) }
        return NSColor(red: 0.95, green: 0.30, blue: 0.25, alpha: 1.0)
    }
}
