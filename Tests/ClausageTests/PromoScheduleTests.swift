import XCTest
@testable import Clausage

final class PromoScheduleTests: XCTestCase {

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
        XCTAssertEqual(PromoSchedule.currentStatus(at: date), .notStarted)
    }

    func testAfterPromoIsEnded() {
        let date = utcDate(year: 2026, month: 3, day: 28, hour: 7, minute: 0)
        XCTAssertEqual(PromoSchedule.currentStatus(at: date), .ended)
    }

    func testWeekdayPeakHoursIsPeak1x() {
        // Wednesday March 18, 2026 at 14:00 UTC (weekday, within 12-18 UTC)
        let date = utcDate(year: 2026, month: 3, day: 18, hour: 14)
        XCTAssertEqual(PromoSchedule.currentStatus(at: date), .peak1x)
    }

    func testWeekdayOffPeakIsActive2x() {
        // Wednesday March 18, 2026 at 08:00 UTC (weekday, before peak)
        let date = utcDate(year: 2026, month: 3, day: 18, hour: 8)
        XCTAssertEqual(PromoSchedule.currentStatus(at: date), .active2x)
    }

    func testWeekdayAfterPeakIsActive2x() {
        // Wednesday March 18, 2026 at 19:00 UTC (weekday, after peak)
        let date = utcDate(year: 2026, month: 3, day: 18, hour: 19)
        XCTAssertEqual(PromoSchedule.currentStatus(at: date), .active2x)
    }

    func testWeekendIsAlways2x() {
        // Saturday March 14, 2026 at 14:00 UTC (weekend, during what would be peak)
        let date = utcDate(year: 2026, month: 3, day: 14, hour: 14)
        XCTAssertEqual(PromoSchedule.currentStatus(at: date), .active2x)
    }

    func testSundayIsAlways2x() {
        let date = utcDate(year: 2026, month: 3, day: 15, hour: 14)
        XCTAssertEqual(PromoSchedule.currentStatus(at: date), .active2x)
    }

    func testPeakBoundaryStart() {
        // Exactly at 12:00 UTC on a weekday = peak
        let date = utcDate(year: 2026, month: 3, day: 18, hour: 12, minute: 0, second: 0)
        XCTAssertEqual(PromoSchedule.currentStatus(at: date), .peak1x)
    }

    func testPeakBoundaryEnd() {
        // Exactly at 18:00 UTC on a weekday = off-peak (>= 18 is off)
        let date = utcDate(year: 2026, month: 3, day: 18, hour: 18, minute: 0, second: 0)
        XCTAssertEqual(PromoSchedule.currentStatus(at: date), .active2x)
    }

    func testPromoStartBoundary() {
        let date = utcDate(year: 2026, month: 3, day: 13, hour: 0, minute: 0, second: 0)
        // March 13 is a Friday, 00:00 UTC = off-peak
        XCTAssertEqual(PromoSchedule.currentStatus(at: date), .active2x)
    }

    // MARK: - nextTransition

    func testNextTransitionFromNotStarted() {
        let date = utcDate(year: 2026, month: 3, day: 12, hour: 12)
        let transition = PromoSchedule.nextTransition(from: date)
        XCTAssertNotNil(transition)
        XCTAssertEqual(transition?.nextStatus, .active2x)
        XCTAssertEqual(transition?.date, PromoSchedule.promoStart)
    }

    func testNextTransitionFromEnded() {
        let date = utcDate(year: 2026, month: 3, day: 29, hour: 12)
        let transition = PromoSchedule.nextTransition(from: date)
        XCTAssertNil(transition)
    }

    func testNextTransitionFromPeakGoesTo2x() {
        // During peak, next transition is end of peak (18:00 UTC)
        let date = utcDate(year: 2026, month: 3, day: 18, hour: 14)
        let transition = PromoSchedule.nextTransition(from: date)
        XCTAssertNotNil(transition)
        XCTAssertEqual(transition?.nextStatus, .active2x)
    }

    func testNextTransitionFrom2xBeforePeakGoesToPeak() {
        // Before peak on a weekday, next transition is peak start
        let date = utcDate(year: 2026, month: 3, day: 18, hour: 8)
        let transition = PromoSchedule.nextTransition(from: date)
        XCTAssertNotNil(transition)
        XCTAssertEqual(transition?.nextStatus, .peak1x)
    }

    func testNextTransitionFromWeekendGoesToMondayPeak() {
        // Saturday, next transition is Monday 12:00 UTC
        let date = utcDate(year: 2026, month: 3, day: 14, hour: 14)
        let transition = PromoSchedule.nextTransition(from: date)
        XCTAssertNotNil(transition)
        XCTAssertEqual(transition?.nextStatus, .peak1x)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let weekday = cal.component(.weekday, from: transition!.date)
        XCTAssertEqual(weekday, 2, "Should transition to Monday")
    }

    // MARK: - Display strings

    func testPeakHoursLocalStringNotEmpty() {
        let str = PromoSchedule.peakHoursLocalString()
        XCTAssertFalse(str.isEmpty)
        XCTAssertTrue(str.contains("-"), "Should contain a dash separator")
    }

    func testPromoEndLocalStringNotEmpty() {
        let str = PromoSchedule.promoEndLocalString()
        XCTAssertFalse(str.isEmpty)
    }
}
