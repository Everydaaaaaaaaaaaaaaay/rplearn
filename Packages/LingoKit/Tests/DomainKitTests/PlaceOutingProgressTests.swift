import BackendKit
import Foundation
import Testing
@testable import DomainKit

func makePlaceOutingFixture() throws -> BackendOuting {
    let url = try #require(Bundle.main.url(forResource: "npc-library-v3", withExtension: "json"))
    let library = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let entries = try #require(library["entries"] as? [[String: Any]])
    let person = try #require(entries.first)
    var story = try #require(person["story"] as? [String: Any])
    story["id"] = "fixture-story"
    story["reunion"] = person["reunion"]
    let place = "london-bloomsbury-cafe"
    let value: [String: Any] = [
        "runId": UUID().uuidString, "releaseId": "test-world", "cityId": "london", "placeId": place,
        "placeTitleZh": "街区咖啡馆", "createdAt": "2026-10-31T08:00:00.000Z",
        "status": "reserved", "revision": 0, "mode": "first_meeting", "reason": "encounter",
        "npc": ["id": person["id"] as Any, "travelerId": person["travelerId"] as Any,
                "card": person["card"] as Any, "createdAt": "2026-09-12T08:00:00Z",
                "avatar": ["id": person["avatarId"] as Any, "url": "https://example.com/avatar.jpg"]],
        "story": story,
        "photo": ["id": "fixture-photo", "cityId": "london", "placeId": place,
                  "assetName": "fixture-photo.jpg", "sourceUrl": "https://example.com/source",
                  "author": "Test fixture", "license": "Test fixture", "licenseUrl": "https://example.com/license",
                  "outputSHA256": String(repeating: "a", count: 64), "width": 1200, "height": 800],
        "solitude": ["id": "fixture-quiet", "titleZh": "片刻", "english": "A quiet visit.", "chinese": "安静地待一会。"],
        "nodeId": "start", "beatIndex": -1, "choices": [String](),
    ]
    return try JSONDecoder().decode(BackendOuting.self, from: JSONSerialization.data(withJSONObject: value))
}


struct PlaceOutingProgressTests {
    @Test func isolatedPreviewHasMatchingPhotosAndFourReachableEndings() throws {
        struct Preview: Decodable { let catalog: BackendActivityCatalog; let outings: [BackendOuting] }
        let url = try #require(Bundle.main.url(forResource: "place-outing-preview", withExtension: "json"))
        let preview = try JSONDecoder().decode(Preview.self, from: Data(contentsOf: url))
        try CityActivityRelease.validate(preview.catalog)
        for source in preview.outings {
            try PlaceOutingProgress.validate(source)
            #expect(preview.catalog.places.first { $0.id == source.placeId }?.photo == source.photo)
            if source.mode == .solitude {
                let presented = try PlaceOutingProgress.apply(.init(expectedRevision: 0, type: .presented), to: source)
                #expect(try PlaceOutingProgress.apply(.init(expectedRevision: 1, type: .complete), to: presented).status == .completed)
                continue
            }
            for first in 0..<2 { for second in 0..<2 {
                var current = try readAll(source)
                current = try PlaceOutingProgress.apply(.init(expectedRevision: current.revision, type: .presented), to: current)
                current = try PlaceOutingProgress.apply(.init(expectedRevision: current.revision, type: .choice, choiceID: "start:\(first)"), to: current)
                current = try readAll(current)
                current = try PlaceOutingProgress.apply(.init(expectedRevision: current.revision, type: .choice, choiceID: "\(current.nodeId):\(second)"), to: current)
                current = try readAll(current)
                #expect(try PlaceOutingProgress.apply(.init(expectedRevision: current.revision, type: .complete), to: current).status == .completed)
            } }
        }
    }
    private func readAll(_ source: BackendOuting) throws -> BackendOuting {
        var current = source
        for index in (current.beatIndex + 1)..<PlaceOutingProgress.beats(current).count {
            current = try PlaceOutingProgress.apply(.init(expectedRevision: current.revision, type: .read, beatIndex: index), to: current)
        }
        return current
    }

    @Test func queuesACompleteBranchWithoutRewritingEarlierChoices() throws {
        let original = try makePlaceOutingFixture()
        var current = try readAll(original)
        current = try PlaceOutingProgress.apply(.init(expectedRevision: current.revision, type: .presented), to: current)
        current = try PlaceOutingProgress.apply(.init(expectedRevision: current.revision, type: .choice, choiceID: "start:1"), to: current)
        #expect(current.nodeId == "b")
        current = try readAll(current)
        current = try PlaceOutingProgress.apply(.init(expectedRevision: current.revision, type: .choice, choiceID: "b:0"), to: current)
        current = try readAll(current)
        current = try PlaceOutingProgress.apply(.init(expectedRevision: current.revision, type: .complete), to: current)
        #expect(current.status == .completed)
        #expect(current.choices == ["start:1", "b:0"])
        #expect(PlaceOutingProgress.chapters(current).count == 3)
        #expect(original.choices.isEmpty)
    }

    @Test func rejectsSkippingReadingStaleVersionsAndForeignChoices() throws {
        let original = try makePlaceOutingFixture()
        #expect(throws: PlaceOutingProgress.ProgressError.self) {
            try PlaceOutingProgress.apply(.init(expectedRevision: 0, type: .presented), to: original)
        }
        #expect(throws: PlaceOutingProgress.ProgressError.self) {
            try PlaceOutingProgress.apply(.init(expectedRevision: 0, type: .read, beatIndex: 3), to: original)
        }
        #expect(throws: PlaceOutingProgress.ProgressError.self) {
            try PlaceOutingProgress.apply(.init(expectedRevision: 1, type: .abandon), to: original)
        }
        var shown = try readAll(original)
        shown = try PlaceOutingProgress.apply(.init(expectedRevision: shown.revision, type: .presented), to: shown)
        #expect(throws: PlaceOutingProgress.ProgressError.self) {
            try PlaceOutingProgress.apply(.init(expectedRevision: shown.revision, type: .choice, choiceID: "b:0"), to: shown)
        }
    }

    @Test func rejectsPhotoOrCharacterFromAnotherCity() throws {
        let original = try makePlaceOutingFixture()
        var value = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        value["cityId"] = "newyork"
        let mismatched = try JSONDecoder().decode(BackendOuting.self, from: JSONSerialization.data(withJSONObject: value))
        #expect(throws: PlaceOutingProgress.ProgressError.self) { try PlaceOutingProgress.validate(mismatched) }
    }

    @Test func pendingOperationsSurviveEncodingWithTheirIdempotencyKeys() throws {
        let operations = [BackendOutingOperation(expectedRevision: 0, type: .read, beatIndex: 0),
                          BackendOutingOperation(expectedRevision: 1, type: .choice, choiceID: "start:0")]
        #expect(try JSONDecoder().decode([BackendOutingOperation].self, from: JSONEncoder().encode(operations)) == operations)
    }
}
