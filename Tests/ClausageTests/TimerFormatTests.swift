import XCTest
@testable import Clausage

final class TimerFormatTests: XCTestCase {

    // MARK: - Full format

    func testFullFormatNormal() {
        let result = TimerFormat.full.format(5562) // 1h 32m 42s
        XCTAssertEqual(result, "1:32:42")
    }

    func testFullFormatZero() {
        XCTAssertEqual(TimerFormat.full.format(0), "0:00:00")
    }

    func testFullFormatNegative() {
        XCTAssertEqual(TimerFormat.full.format(-100), "0:00:00")
    }

    func testFullFormatExactHour() {
        XCTAssertEqual(TimerFormat.full.format(3600), "1:00:00")
    }

    // MARK: - Compact format

    func testCompactFormat() {
        XCTAssertEqual(TimerFormat.compact.format(5562), "1:32")
    }

    func testCompactFormatZero() {
        XCTAssertEqual(TimerFormat.compact.format(0), "0:00")
    }

    // MARK: - Labeled format

    func testLabeledFormat() {
        XCTAssertEqual(TimerFormat.labeled.format(5562), "1h 32m")
    }

    func testLabeledFormatZero() {
        XCTAssertEqual(TimerFormat.labeled.format(0), "0h 0m")
    }

    // MARK: - Minimal format

    func testMinimalFormat() {
        XCTAssertEqual(TimerFormat.minimal.format(5562), "1h32m")
    }

    func testMinimalFormatZero() {
        XCTAssertEqual(TimerFormat.minimal.format(0), "0h0m")
    }

    // MARK: - Days display

    func testDaysDisplayForAllFormats() {
        let interval: TimeInterval = 90000 // 25 hours
        for format in TimerFormat.allCases {
            let result = format.format(interval)
            XCTAssertTrue(result.contains("d"), "Format \(format.rawValue) should show days for >24h, got: \(result)")
            XCTAssertTrue(result.contains("1d 1h"), "Should be 1d 1h, got: \(result)")
        }
    }

    // MARK: - Edge cases

    func testJustUnder24Hours() {
        let interval: TimeInterval = 86399 // 23:59:59
        let result = TimerFormat.full.format(interval)
        XCTAssertEqual(result, "23:59:59")
    }

    func testExactly24Hours() {
        let interval: TimeInterval = 86400
        // 24 hours = still uses h:m:s (hours > 24 triggers days)
        let result = TimerFormat.full.format(interval)
        // 24 is not > 24, so should use normal format
        XCTAssertEqual(result, "24:00:00")
    }

    func testLargeInterval() {
        let interval: TimeInterval = 259200 // 3 days
        let result = TimerFormat.full.format(interval)
        XCTAssertEqual(result, "3d 0h")
    }

    // MARK: - CaseIterable

    func testAllCasesCount() {
        XCTAssertEqual(TimerFormat.allCases.count, 4)
    }

    func testDisplayNamesAreUnique() {
        let names = TimerFormat.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count, "Display names should be unique")
    }
}
