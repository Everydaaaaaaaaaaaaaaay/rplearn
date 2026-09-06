import XCTest
@testable import HomeFeature

final class ActivityJourneyTests: XCTestCase {
    func testEverySceneHasDistinctCompleteActionsAndBundledMedia() throws {
        XCTAssertEqual(ActivitySceneID.allCases.count, 2)
        XCTAssertEqual(Set(SceneActivity.catalog.map(\.id)).count, 6)
        for scene in ActivitySceneID.allCases {
            XCTAssertEqual(scene.actions.count, 3)
            XCTAssertEqual(Set(scene.actions.map(\.anchor)).count, 3)
            for (name, ext) in [(scene.poster, "jpg"), (scene.table, "jpg"), ("activity-\(scene.rawValue)-loop", "mp4")] {
                XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: ext), name)
            }
            for activity in scene.actions {
                XCTAssertFalse(activity.introduction.isEmpty)
                XCTAssertFalse(activity.closing.isEmpty)
                XCTAssertEqual(activity.steps.count, 2)
                for step in activity.steps {
                    XCTAssertFalse(step.context.isEmpty)
                    XCTAssertFalse(step.question.isEmpty)
                    XCTAssertEqual(step.choices.count, 2)
                    XCTAssertEqual(Set(step.choices.map(\.response)).count, step.choices.count)
                    for choice in step.choices {
                        XCTAssertFalse(choice.chinese.isEmpty)
                        XCTAssertFalse(choice.response.isEmpty)
                        XCTAssertLessThanOrEqual(choice.english.count, 80)
                    }
                }
            }
        }
    }

    func testAllBranchesPreserveContextAndAreIdempotent() throws {
        let suite = "activity-test-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let journal = ActivityJournal(namespace: "guest", city: "london", defaults: defaults)
        var expectedCount = 0
        for activity in SceneActivity.catalog {
            for first in 0..<2 {
                for second in 0..<2 {
                    let run = UUID()
                    let indices = [first, second]
                    let saved = try journal.complete(activity, selections: indices, runID: run)
                    expectedCount += 1
                    XCTAssertEqual(saved.count, expectedCount)
                    let record = try XCTUnwrap(saved.last)
                    for (index, selected) in indices.enumerated() {
                        XCTAssertEqual(record.choices[index].context, activity.steps[index].context)
                        XCTAssertEqual(record.choices[index].response, activity.steps[index].choices[selected].response)
                    }
                    XCTAssertEqual(try journal.complete(activity, selections: indices, runID: run), saved)
                }
            }
        }
        XCTAssertEqual(try journal.records().count, 24)
        XCTAssertTrue(try ActivityJournal(namespace: "other", city: "london", defaults: defaults).records().isEmpty)
        XCTAssertTrue(try ActivityJournal(namespace: "guest", city: "auckland", defaults: defaults).records().isEmpty)
    }

    func testIncompleteOrCorruptDataNeverOverwritesHistory() throws {
        let suite = "activity-test-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let journal = ActivityJournal(namespace: "guest", city: "london", defaults: defaults)
        let activity = try XCTUnwrap(SceneActivity.catalog.first)
        for invalid in [[], [0], [0, 5], [0, 0, 0], [-1, 0]] {
            XCTAssertThrowsError(try journal.complete(activity, selections: invalid, runID: UUID()))
            XCTAssertNil(defaults.data(forKey: journal.key))
        }
        for damaged in [Data("broken".utf8), Data("{\"version\":99,\"records\":[]}".utf8)] {
            defaults.set(damaged, forKey: journal.key)
            XCTAssertThrowsError(try journal.records())
            XCTAssertThrowsError(try journal.complete(activity, selections: [0, 1], runID: UUID()))
            XCTAssertEqual(defaults.data(forKey: journal.key), damaged)
        }
    }
}
