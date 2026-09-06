import AVFoundation
import XCTest
import PersistenceKit
@testable import HomeFeature

final class ActivityJourneyTests: XCTestCase {
    func testReunionEligibilityPreservesIdentityBoundariesWithoutDemographicFiltering() {
        let now = Date()
        var person = CharacterDTO(id: UUID(), card: CharacterCard(name: "Sam", age: 72,
            gender: .female, nationality: "British", regionID: "london", occupation: "retired mechanic",
            hobbies: ["heavy metal"], appearance: "", personality: "reserved", languages: ["English"]),
            difficultyLevel: .junior3, isMainCharacter: false, isFriend: true, metAt: now)
        XCTAssertTrue(CafeEncounterPolicy.eligible(person, regionID: "london"))
        XCTAssertFalse(CafeEncounterPolicy.eligible(person, regionID: "auckland"))
        person.contactStatus = .removed
        XCTAssertFalse(CafeEncounterPolicy.eligible(person, regionID: "london"))
        person.contactStatus = .friend
        person.isMainCharacter = true
        XCTAssertFalse(CafeEncounterPolicy.eligible(person, regionID: "london"))
        person.isMainCharacter = false
        person.card.languages = ["French"]
        XCTAssertFalse(CafeEncounterPolicy.eligible(person, regionID: "london"))
        person.card.languages = nil
        XCTAssertTrue(CafeEncounterPolicy.eligible(person, regionID: "london"))
        XCTAssertTrue(CafeEncounterPolicy.allowsReunion(lastSpokenAt: nil, now: now))
        XCTAssertTrue(CafeEncounterPolicy.allowsReunion(lastSpokenAt: now.addingTimeInterval(-86_400), now: now))
        XCTAssertFalse(CafeEncounterPolicy.allowsReunion(lastSpokenAt: now.addingTimeInterval(-100), now: now))
        XCTAssertFalse(CafeEncounterPolicy.allowsReunion(lastSpokenAt: now.addingTimeInterval(100), now: now))
    }

    func testEverySceneHasDistinctCompleteActionsAndBundledMedia() throws {
        XCTAssertEqual(ActivitySceneID.allCases.count, 1)
        XCTAssertEqual(Set(SceneActivity.catalog.map(\.id)).count, 3)
        for scene in ActivitySceneID.allCases {
            XCTAssertEqual(scene.actions.count, 3)
            XCTAssertEqual(Set(scene.actions.map(\.anchor)).count, 3)
            for (name, ext) in [(scene.poster, "jpg"), ("activity-cafe-window", "jpg"),
                                ("activity-cafe-street-loop", "mp4")] {
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
        XCTAssertEqual(try journal.records().count, 12)
        XCTAssertTrue(try ActivityJournal(namespace: "other", city: "london", defaults: defaults).records().isEmpty)
        XCTAssertTrue(try ActivityJournal(namespace: "guest", city: "auckland", defaults: defaults).records().isEmpty)
    }

    func testSocialRecordRetainsIdentityAndActualReplyWithoutBreakingLegacyRecords() throws {
        let suite = "social-journal-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let journal = ActivityJournal(namespace: "guest", city: "london", defaults: defaults)
        let person = UUID()
        let record = try XCTUnwrap(journal.complete(SceneActivity.catalog[0], selections: [0, 1], runID: UUID(),
            characterID: person, characterName: "Alex", responses: ["你可以坐这里。", "祝你今天愉快！"]).last)
        XCTAssertEqual(record.characterID, person)
        XCTAssertTrue(record.choices[0].response.contains("你可以坐这里。"))
        XCTAssertTrue(record.choices[1].response.contains("祝你今天愉快！"))
        XCTAssertEqual(record.characterName, "Alex")
        let legacy = "{\"version\":1,\"records\":[{\"id\":\"\(UUID())\",\"activityID\":\"walk\",\"title\":\"旧足迹\",\"date\":0,\"choices\":[]}]}"
        defaults.set(Data(legacy.utf8), forKey: journal.key)
        XCTAssertEqual(try journal.records().first?.title, "旧足迹")
        XCTAssertNil(try journal.records().first?.characterID)
    }

    func testCafeMediaIsALongSilentTakeMatchingTheWindow() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "activity-cafe-street-loop", withExtension: "mp4"))
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 46.5, accuracy: 0.05)
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(video.count, 1)
        XCTAssertTrue(audio.isEmpty)
        let track = try XCTUnwrap(video.first)
        let size = try await track.load(.naturalSize)
        let fps = try await track.load(.nominalFrameRate)
        XCTAssertEqual(size, CGSize(width: 650, height: 520))
        XCTAssertEqual(fps, 24, accuracy: 0.01)
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
