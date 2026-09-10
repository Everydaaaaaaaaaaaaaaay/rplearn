import XCTest
@testable import HomeFeature

final class ActivityEncounterChanceTests: XCTestCase {
    func testMissProbabilityRisesButNeverForcesEitherOutcome() {
        XCTAssertEqual(ActivityEncounterChance.encounterProbability(misses: 0), 0.65, accuracy: 0.000001)
        var previous = 0.0
        for misses in 0...1000 {
            let p = ActivityEncounterChance.encounterProbability(misses: misses)
            XCTAssertGreaterThanOrEqual(p, previous)
            XCTAssertGreaterThan(p, 0)
            XCTAssertLessThan(p, 1)
            previous = p
        }
    }
    func testRepeatedPeopleRemainSelectableAndRecoverWithTime() {
        let now = Date()
        let once = ActivityEncounterChance.personWeight(encounters: 1, lastSeen: now, now: now)
        let repeated = ActivityEncounterChance.personWeight(encounters: 5, lastSeen: now, now: now)
        XCTAssertLessThan(repeated, once)
        XCTAssertGreaterThan(ActivityEncounterChance.personWeight(encounters: 5,
            lastSeen: now.addingTimeInterval(-86400 * 14), now: now), repeated)
        let weights = [1.0, repeated, 0.02]
        var hits = [0, 0, 0]
        for i in 0..<10000 {
            hits[ActivityEncounterChance.chooseIndex(weights: weights, roll: Double(i) / 10000)!] += 1
        }
        XCTAssertGreaterThan(hits[0], hits[1])
        XCTAssertGreaterThan(hits[1], hits[2])
        XCTAssertGreaterThan(hits[2], 0)
        XCTAssertNil(ActivityEncounterChance.chooseIndex(weights: [], roll: 0))
    }
    func testRetryPreservesRollAndFailedRequestsDoNotCountAsMisses() throws {
        let suite = "journey-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = ActivityEncounterHistory(namespace: "guest", city: "london", defaults: defaults)
        let run = UUID()
        XCTAssertTrue(try history.reserve(runID: run, roll: 0).encountersPerson)
        XCTAssertTrue(try history.reserve(runID: run, roll: 0.999).encountersPerson)
        XCTAssertNil(try history.receipts().first?.completedAt)
        let solitude = UUID()
        XCTAssertFalse(try history.reserve(runID: solitude, roll: 0.7).encountersPerson)
        try history.complete(runID: solitude, characterID: nil)
        try history.complete(runID: solitude, characterID: nil)
        XCTAssertEqual(try history.receipts().filter { $0.completedAt != nil }.count, 1)
        XCTAssertTrue(try history.reserve(runID: UUID(), roll: 0.7).encountersPerson)
        XCTAssertEqual(try ActivityEncounterHistory(namespace: "other", city: "london", defaults: defaults).receipts(), [])
        XCTAssertEqual(try ActivityEncounterHistory(namespace: "guest", city: "sydney", defaults: defaults).receipts(), [])
    }
    func testCorruptHistoryIsPreservedAndSolitudeJournalIsIdempotent() throws {
        let suite = "journey-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = ActivityEncounterHistory(namespace: "guest", city: "london", defaults: defaults)
        let broken = Data("broken".utf8)
        defaults.set(broken, forKey: history.key)
        XCTAssertThrowsError(try history.reserve(runID: UUID(), roll: 0))
        XCTAssertEqual(defaults.data(forKey: history.key), broken)
        let journal = ActivityJournal(namespace: "guest", city: "london", defaults: defaults)
        let run = UUID()
        let record = try journal.completeSolitude(SceneActivity.catalog[0], runID: run)
        XCTAssertNotNil(record.first?.solitudeStory)
        XCTAssertNil(record.first?.characterID)
        XCTAssertEqual(record, try journal.completeSolitude(SceneActivity.catalog[0], runID: run))
    }
}
