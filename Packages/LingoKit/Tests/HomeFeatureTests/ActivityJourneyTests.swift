import XCTest
import UIKit
import PersistenceKit
@testable import HomeFeature

final class ActivityJourneyTests: XCTestCase {
    func testCompleteSceneMastersKeepTheirNativePixelsAndCalibratedCanvas() throws {
        for scene in ActivitySceneID.allCases {
            let url = try XCTUnwrap(Bundle.main.url(forResource: scene.poster, withExtension: "png"))
            let image = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
            XCTAssertEqual(image.width, scene == .bookstall ? 852 : 851)
            XCTAssertEqual(image.height, scene == .bookstall ? 1846 : scene == .cafe ? 1847 : 1849)
            XCTAssertEqual(CGFloat(image.width) / CGFloat(image.height), 852.0 / 1847.0, accuracy: 0.002)
            // Full continuous photo, not a transparent foreground on old footage.
            var pixel = [UInt8](repeating: 0, count: 4)
            let patch = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)))
            pixel.withUnsafeMutableBytes { bytes in
                let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(patch, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            XCTAssertEqual(pixel[3], 255)
        }
    }
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
        XCTAssertGreaterThan(ActivityEncounterChance.personWeight(encounters: 1000, lastSeen: now, now: now), 0)

    }

    func testEverySceneHasDistinctCompleteActionsAndBundledMedia() throws {
        XCTAssertEqual(ActivitySceneID.allCases.count, 3)
        XCTAssertEqual(Set(SceneActivity.catalog.map(\.id)).count, 9)
        XCTAssertEqual(Set(ActivitySceneID.allCases.map { $0.media.seed }).count, 3)
        XCTAssertEqual(Set(ActivitySceneID.allCases.map(\.poster)).count, 3)
        for scene in ActivitySceneID.allCases {
            XCTAssertEqual(scene.actions.count, 3)
            XCTAssertEqual(Set(scene.actions.map(\.anchor)).count, 3)
            XCTAssertNotNil(Bundle.main.url(forResource: scene.poster, withExtension: "png"))
            XCTAssertFalse(scene.media.lightPlanes.isEmpty)
            for activity in scene.actions {
                XCTAssertEqual(activity.scene, scene)
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

    func testCafeActionsDoNotInventBookPropsAndRetiredActionHistorySurvives() throws {
        let cafe = ActivitySceneID.cafe.actions
        XCTAssertTrue(cafe.contains { $0.id == "cafe-taste" })
        XCTAssertFalse(cafe.contains { $0.id == "cafe-book" })
        for action in cafe {
            XCTAssertFalse((action.title + action.introduction).contains("书"))
            XCTAssertFalse(action.introduction.contains("菜单"))
        }
        let suite = "retired-cafe-action-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let journal = ActivityJournal(namespace: "guest", city: "london", defaults: defaults)
        let historical = "{\"version\":1,\"records\":[{\"id\":\"\(UUID())\",\"activityID\":\"cafe-book\",\"title\":\"借书开场\",\"date\":0,\"choices\":[]}]}"
        defaults.set(Data(historical.utf8), forKey: journal.key)
        let records = try journal.complete(try XCTUnwrap(cafe.first { $0.id == "cafe-taste" }), selections: [0, 1], runID: UUID())
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.first?.activityID, "cafe-book")
        XCTAssertEqual(records.first?.title, "借书开场")
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
        XCTAssertEqual(try journal.records().count, 36)
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

    func testRejectedCrowdCompositesAreNotBundled() {
        for scene in ActivitySceneID.allCases {
            XCTAssertNil(Bundle.main.url(forResource: "activity-\(scene.rawValue)-street-loop", withExtension: "mp4"))
            XCTAssertNil(Bundle.main.url(forResource: "activity-\(scene.rawValue)-window", withExtension: "jpg"))
        }
    }

    func testAmbientShadowCycleIsContinuousAndBounded() {
        let duration = ActivityAmbientLightLayer.cycle
        XCTAssertEqual(duration, 60)
        for phase in [0.0, 0.5, 2.0, 4.0] {
            let start = ActivityAmbientLightLayer.drift(at: 0, phase: phase)
            let end = ActivityAmbientLightLayer.drift(at: duration, phase: phase)
            XCTAssertEqual(start.x, end.x, accuracy: 0.000001)
            XCTAssertEqual(start.y, end.y, accuracy: 0.000001)
            let epsilon = 0.0001
            let before = ActivityAmbientLightLayer.drift(at: duration - epsilon, phase: phase)
            let after = ActivityAmbientLightLayer.drift(at: epsilon, phase: phase)
            XCTAssertEqual((end.x - before.x) / epsilon, (after.x - start.x) / epsilon, accuracy: 0.001)
            XCTAssertEqual((end.y - before.y) / epsilon, (after.y - start.y) / epsilon, accuracy: 0.001)
            for time in stride(from: 0.0, through: 120, by: 0.25) {
                let offset = ActivityAmbientLightLayer.drift(at: time, phase: phase)
                XCTAssertLessThanOrEqual(abs(offset.x), 10)
                XCTAssertLessThanOrEqual(abs(offset.y), 6)
            }
        }
    }

    func testAmbientMotionHonoursAccessibilityPowerAndTemperature() {
        for thermal in [ProcessInfo.ThermalState.nominal, .fair, .serious, .critical] {
            for requested in [false, true] {
                for reduced in [false, true] {
                    for lowPower in [false, true] {
                        XCTAssertEqual(ActivityAmbientLightLayer.permitsMotion(requested: requested,
                            reduceMotion: reduced, lowPower: lowPower, thermal: thermal),
                            requested && !reduced && !lowPower && (thermal == .nominal || thermal == .fair))
                    }
                }
            }
        }
    }

    @MainActor
    func testAmbientSurfacePausesResumesAndStopsWhenDetached() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let surface = ActivityAmbientLightLayer.Surface(scene: .cafe)
        window.addSubview(surface)
        surface.frame = window.bounds
        window.isHidden = false
        defer { surface.removeFromSuperview(); window.isHidden = true }
        surface.setPlaying(true)
        XCTAssertTrue(surface.running)
        try await Task.sleep(for: .milliseconds(100))
        surface.setPlaying(false)
        let paused = surface.elapsed
        XCTAssertGreaterThan(paused, 0.05)
        XCTAssertFalse(surface.running)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(surface.elapsed, paused, accuracy: 0.002)
        surface.setPlaying(true)
        XCTAssertEqual(surface.elapsed, paused, accuracy: 0.02)
        surface.removeFromSuperview()
        XCTAssertFalse(surface.running)
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
