import XCTest
@testable import Clausage

final class UpdateServiceTests: XCTestCase {

    // MARK: - Version comparison

    func testNewerMajor() {
        XCTAssertTrue(UpdateService.isNewer("2.0.0", than: "1.0.0"))
    }

    func testNewerMinor() {
        XCTAssertTrue(UpdateService.isNewer("1.1.0", than: "1.0.0"))
    }

    func testNewerPatch() {
        XCTAssertTrue(UpdateService.isNewer("1.0.1", than: "1.0.0"))
    }

    func testSameVersion() {
        XCTAssertFalse(UpdateService.isNewer("1.0.0", than: "1.0.0"))
    }

    func testOlderVersion() {
        XCTAssertFalse(UpdateService.isNewer("1.0.0", than: "2.0.0"))
    }

    func testVPrefixRemote() {
        XCTAssertTrue(UpdateService.isNewer("v2.0.0", than: "1.0.0"))
    }

    func testVPrefixLocal() {
        XCTAssertTrue(UpdateService.isNewer("2.0.0", than: "v1.0.0"))
    }

    func testVPrefixBoth() {
        XCTAssertTrue(UpdateService.isNewer("v2.0.0", than: "v1.0.0"))
    }

    func testDifferentLengthVersions() {
        XCTAssertTrue(UpdateService.isNewer("1.0.1", than: "1.0"))
        XCTAssertFalse(UpdateService.isNewer("1.0", than: "1.0.1"))
    }

    func testSingleDigitVersions() {
        XCTAssertTrue(UpdateService.isNewer("2", than: "1"))
        XCTAssertFalse(UpdateService.isNewer("1", than: "2"))
    }

    func testLargeVersionNumbers() {
        XCTAssertTrue(UpdateService.isNewer("10.0.0", than: "9.99.99"))
    }
}
