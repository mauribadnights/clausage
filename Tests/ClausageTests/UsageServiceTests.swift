import XCTest
@testable import Clausage

final class UsageServiceTests: XCTestCase {

    // MARK: - resetTimeString

    func testResetTimeStringNil() {
        XCTAssertEqual(UsageService.resetTimeString(nil), "\u{2014}")
    }

    func testResetTimeStringPast() {
        let past = Date().addingTimeInterval(-60)
        XCTAssertEqual(UsageService.resetTimeString(past), "now")
    }

    func testResetTimeStringMinutes() {
        let future = Date().addingTimeInterval(30 * 60) // 30 minutes
        let result = UsageService.resetTimeString(future)
        XCTAssertTrue(result.contains("m"), "Should contain minutes: \(result)")
        XCTAssertTrue(result.hasPrefix("in "), "Should start with 'in ': \(result)")
    }

    func testResetTimeStringHours() {
        let future = Date().addingTimeInterval(3 * 3600 + 15 * 60) // 3h 15m
        let result = UsageService.resetTimeString(future)
        XCTAssertTrue(result.contains("h"), "Should contain hours: \(result)")
        XCTAssertTrue(result.contains("m"), "Should contain minutes: \(result)")
    }

    func testResetTimeStringDays() {
        let future = Date().addingTimeInterval(48 * 3600 + 3 * 3600) // 2d 3h
        let result = UsageService.resetTimeString(future)
        XCTAssertTrue(result.contains("d"), "Should contain days: \(result)")
    }

    // MARK: - UsageData equality

    func testUsageDataEquality() {
        let now = Date()
        let a = UsageData(fiveHourPercent: 50, weeklyPercent: 30, lastUpdated: now)
        let b = UsageData(fiveHourPercent: 50, weeklyPercent: 30, lastUpdated: now)
        XCTAssertEqual(a, b)
    }

    func testUsageDataInequality() {
        let now = Date()
        let a = UsageData(fiveHourPercent: 50, weeklyPercent: 30, lastUpdated: now)
        let b = UsageData(fiveHourPercent: 60, weeklyPercent: 30, lastUpdated: now)
        XCTAssertNotEqual(a, b)
    }
}
