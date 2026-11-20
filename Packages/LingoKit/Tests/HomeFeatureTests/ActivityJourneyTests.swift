import Foundation
import XCTest
@testable import HomeFeature

final class ActivityJourneyTests: XCTestCase {
    func testRetiredActivityHistoryStillReadsAndMerges() throws {
        let suite = "retired-activity-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let journal = ActivityJournal(namespace: "guest", city: "london", defaults: defaults)
        let runID = UUID()
        let historical = """
        {"version":1,"records":[{"id":"\(runID)","activityID":"cafe-book","title":"借书开场","date":0,"choices":[]}]}
        """
        defaults.set(Data(historical.utf8), forKey: journal.key)

        let records = try journal.records()
        XCTAssertEqual(records.first?.id, runID)
        XCTAssertEqual(records.first?.activityID, "cafe-book")
        XCTAssertEqual(records.first?.title, "借书开场")

        try ActivityJournal.merge(namespace: "guest", into: "account", defaults: defaults)
        try ActivityJournal.merge(namespace: "guest", into: "account", defaults: defaults)
        let account = ActivityJournal(namespace: "account", city: "london", defaults: defaults)
        XCTAssertEqual(try account.records(), records)
        XCTAssertEqual(defaults.data(forKey: journal.key), Data(historical.utf8))
    }

    func testRetiredActivityMediaIsOutsideTheBundle() {
        for name in ["activity-park-loop", "activity-pond-loop", "activity-raincafe-loop", "encounter-journey"] {
            XCTAssertNil(Bundle.main.url(forResource: name, withExtension: "mp4"))
        }
        XCTAssertNil(Bundle.main.url(forResource: "encounter-journey", withExtension: "json"))
    }
}
