import XCTest
import SwiftData
@testable import Clausage

final class UsageSnapshotTests: XCTestCase {

    func testSnapshotCreation() {
        let now = Date()
        let snapshot = UsageSnapshot(
            timestamp: now,
            fiveHourPercent: 42.5,
            weeklyPercent: 67.8,
            fiveHourResetsAt: now.addingTimeInterval(3600),
            weeklyResetsAt: now.addingTimeInterval(86400)
        )

        XCTAssertEqual(snapshot.timestamp, now)
        XCTAssertEqual(snapshot.fiveHourPercent, 42.5)
        XCTAssertEqual(snapshot.weeklyPercent, 67.8)
        XCTAssertNotNil(snapshot.fiveHourResetsAt)
        XCTAssertNotNil(snapshot.weeklyResetsAt)
    }

    func testSnapshotDefaultTimestamp() {
        let before = Date()
        let snapshot = UsageSnapshot(fiveHourPercent: 50, weeklyPercent: 50)
        let after = Date()

        XCTAssertGreaterThanOrEqual(snapshot.timestamp, before)
        XCTAssertLessThanOrEqual(snapshot.timestamp, after)
    }

    func testSnapshotOptionalFieldsDefault() {
        let snapshot = UsageSnapshot(fiveHourPercent: 50, weeklyPercent: 50)
        XCTAssertNil(snapshot.fiveHourResetsAt)
        XCTAssertNil(snapshot.weeklyResetsAt)
    }

    func testSwiftDataModelContainer() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: UsageSnapshot.self, configurations: config)
        let context = ModelContext(container)

        let snapshot = UsageSnapshot(fiveHourPercent: 75, weeklyPercent: 30)
        context.insert(snapshot)
        try context.save()

        let descriptor = FetchDescriptor<UsageSnapshot>()
        let results = try context.fetch(descriptor)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.fiveHourPercent, 75)
        XCTAssertEqual(results.first?.weeklyPercent, 30)
    }

    func testSwiftDataMultipleSnapshots() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: UsageSnapshot.self, configurations: config)
        let context = ModelContext(container)

        for i in 0..<100 {
            let snapshot = UsageSnapshot(
                timestamp: Date().addingTimeInterval(Double(-i) * 300),
                fiveHourPercent: Double.random(in: 0...100),
                weeklyPercent: Double.random(in: 0...100)
            )
            context.insert(snapshot)
        }
        try context.save()

        let descriptor = FetchDescriptor<UsageSnapshot>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        let results = try context.fetch(descriptor)

        XCTAssertEqual(results.count, 100)
        // Verify sorted
        for i in 1..<results.count {
            XCTAssertLessThanOrEqual(results[i-1].timestamp, results[i].timestamp)
        }
    }
}
