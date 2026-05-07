import XCTest
@testable import Clausage

final class CodexUsageServiceTests: XCTestCase {

    func testParseHappyPath() throws {
        let json = """
        {
          "plan_type": "pro",
          "rate_limit": {
            "allowed": true,
            "limit_reached": false,
            "primary_window": {
              "used_percent": 42,
              "limit_window_seconds": 18000,
              "reset_at": 1735689720
            },
            "secondary_window": {
              "used_percent": 5.5,
              "limit_window_seconds": 604800,
              "reset_at": 1735711200
            }
          }
        }
        """.data(using: .utf8)!

        let parsed = CodexUsageService.parseResponse(json, now: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(parsed.planType, "pro")
        XCTAssertEqual(parsed.primaryUsedPercent, 42.0)
        XCTAssertEqual(parsed.primaryWindowSeconds, 18000)
        XCTAssertEqual(parsed.primaryResetsAt, Date(timeIntervalSince1970: 1735689720))
        XCTAssertEqual(parsed.secondaryUsedPercent, 5.5)
        XCTAssertEqual(parsed.secondaryWindowSeconds, 604800)
        XCTAssertEqual(parsed.secondaryResetsAt, Date(timeIntervalSince1970: 1735711200))
        XCTAssertEqual(parsed.lastUpdated, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNil(parsed.error)
        XCTAssertFalse(parsed.isStale)
    }

    func testParsePartialMissingSecondary() throws {
        let json = """
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": {
              "used_percent": 99
            }
          }
        }
        """.data(using: .utf8)!

        let parsed = CodexUsageService.parseResponse(json)
        XCTAssertEqual(parsed.planType, "plus")
        XCTAssertEqual(parsed.primaryUsedPercent, 99.0)
        XCTAssertNil(parsed.secondaryUsedPercent)
        XCTAssertNil(parsed.primaryResetsAt)
    }

    func testParseFallsBackToProvidedPlanType() throws {
        // The endpoint may omit plan_type; we should fall back to whatever the caller
        // gleaned from the id_token.
        let json = """
        {
          "rate_limit": {
            "primary_window": {"used_percent": 10}
          }
        }
        """.data(using: .utf8)!

        let parsed = CodexUsageService.parseResponse(json, planType: "prolite")
        XCTAssertEqual(parsed.planType, "prolite")
        XCTAssertEqual(parsed.primaryUsedPercent, 10.0)
    }

    func testParseGarbageReturnsError() {
        let parsed = CodexUsageService.parseResponse(Data("not json".utf8))
        XCTAssertNotNil(parsed.error)
        XCTAssertNil(parsed.primaryUsedPercent)
    }

    func testParseEmptyRateLimitObject() throws {
        let json = """
        { "plan_type": "free", "rate_limit": {} }
        """.data(using: .utf8)!
        let parsed = CodexUsageService.parseResponse(json)
        XCTAssertEqual(parsed.planType, "free")
        XCTAssertNil(parsed.primaryUsedPercent)
        XCTAssertNil(parsed.secondaryUsedPercent)
        XCTAssertNil(parsed.error)
    }
}
