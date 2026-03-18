import XCTest
@testable import Clausage

final class PromoScheduleTests: XCTestCase {

    private var schedule: PromoSchedule!

    override func setUp() {
        super.setUp()
        schedule = PromoSchedule.shared
        // Load the test promo config
        let config = PromoConfig(
            enabled: true,
            startUTC: "2026-03-13T00:00:00Z",
            endUTC: "2026-03-28T06:59:59Z",
            peakStartHourUTC: 12,
            peakEndHourUTC: 18,
            description: "Test promo"
        )
        schedule.update(from: config)
    }

    private func utcDate(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        ))!
    }

    // MARK: - currentStatus

    func testBeforePromoIsNotStarted() {
        let date = utcDate(year: 2026, month: 3, day: 12, hour: 23, minute: 59)
        XCTAssertEqual(schedule.currentStatus(at: date), .notStarted)
    }

    func testAfterPromoIsEnded() {
        let date = utcDate(year: 2026, month: 3, day: 28, hour: 7, minute: 0)
        XCTAssertEqual(schedule.currentStatus(at: date), .ended)
    }

    func testWeekdayPeakHoursIsPeak1x() {
        let date = utcDate(year: 2026, month: 3, day: 18, hour: 14)
        XCTAssertEqual(schedule.currentStatus(at: date), .peak1x)
    }

    func testWeekdayOffPeakIsActive2x() {
        let date = utcDate(year: 2026, month: 3, day: 18, hour: 8)
        XCTAssertEqual(schedule.currentStatus(at: date), .active2x)
    }

    func testWeekdayAfterPeakIsActive2x() {
        let date = utcDate(year: 2026, month: 3, day: 18, hour: 19)
        XCTAssertEqual(schedule.currentStatus(at: date), .active2x)
    }

    func testWeekendIsAlways2x() {
        let date = utcDate(year: 2026, month: 3, day: 14, hour: 14)
        XCTAssertEqual(schedule.currentStatus(at: date), .active2x)
    }

    func testSundayIsAlways2x() {
        let date = utcDate(year: 2026, month: 3, day: 15, hour: 14)
        XCTAssertEqual(schedule.currentStatus(at: date), .active2x)
    }

    func testPeakBoundaryStart() {
        let date = utcDate(year: 2026, month: 3, day: 18, hour: 12, minute: 0, second: 0)
        XCTAssertEqual(schedule.currentStatus(at: date), .peak1x)
    }

    func testPeakBoundaryEnd() {
        let date = utcDate(year: 2026, month: 3, day: 18, hour: 18, minute: 0, second: 0)
        XCTAssertEqual(schedule.currentStatus(at: date), .active2x)
    }

    func testPromoStartBoundary() {
        let date = utcDate(year: 2026, month: 3, day: 13, hour: 0, minute: 0, second: 0)
        XCTAssertEqual(schedule.currentStatus(at: date), .active2x)
    }

    // MARK: - disabled state

    func testDisabledWhenConfigIsNil() {
        schedule.update(from: nil)
        XCTAssertEqual(schedule.currentStatus(), .disabled)
    }

    func testDisabledWhenEnabledIsFalse() {
        let config = PromoConfig(
            enabled: false,
            startUTC: "2026-03-13T00:00:00Z",
            endUTC: "2026-03-28T06:59:59Z",
            peakStartHourUTC: 12,
            peakEndHourUTC: 18,
            description: "Disabled"
        )
        schedule.update(from: config)
        XCTAssertEqual(schedule.currentStatus(), .disabled)
    }

    // MARK: - nextTransition

    func testNextTransitionFromNotStarted() {
        let date = utcDate(year: 2026, month: 3, day: 12, hour: 12)
        let transition = schedule.nextTransition(from: date)
        XCTAssertNotNil(transition)
        XCTAssertEqual(transition?.nextStatus, .active2x)
        XCTAssertEqual(transition?.date, schedule.promoStart)
    }

    func testNextTransitionFromEnded() {
        let date = utcDate(year: 2026, month: 3, day: 29, hour: 12)
        let transition = schedule.nextTransition(from: date)
        XCTAssertNil(transition)
    }

    func testNextTransitionFromDisabled() {
        schedule.update(from: nil)
        let transition = schedule.nextTransition()
        XCTAssertNil(transition)
    }

    func testNextTransitionFromPeakGoesTo2x() {
        let date = utcDate(year: 2026, month: 3, day: 18, hour: 14)
        let transition = schedule.nextTransition(from: date)
        XCTAssertNotNil(transition)
        XCTAssertEqual(transition?.nextStatus, .active2x)
    }

    func testNextTransitionFrom2xBeforePeakGoesToPeak() {
        let date = utcDate(year: 2026, month: 3, day: 18, hour: 8)
        let transition = schedule.nextTransition(from: date)
        XCTAssertNotNil(transition)
        XCTAssertEqual(transition?.nextStatus, .peak1x)
    }

    func testNextTransitionFromWeekendGoesToMondayPeak() {
        let date = utcDate(year: 2026, month: 3, day: 14, hour: 14)
        let transition = schedule.nextTransition(from: date)
        XCTAssertNotNil(transition)
        XCTAssertEqual(transition?.nextStatus, .peak1x)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let weekday = cal.component(.weekday, from: transition!.date)
        XCTAssertEqual(weekday, 2, "Should transition to Monday")
    }

    // MARK: - Display strings

    func testPeakHoursLocalStringNotEmpty() {
        let str = schedule.peakHoursLocalString()
        XCTAssertFalse(str.isEmpty)
        XCTAssertTrue(str.contains("-"), "Should contain a dash separator")
    }

    func testPromoEndLocalStringNotEmpty() {
        let str = schedule.promoEndLocalString()
        XCTAssertFalse(str.isEmpty)
    }
}
