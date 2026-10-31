import Foundation
import DomainKit
import BackendKit

struct ActivityRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let activityID: String
    let title: String
    let date: Date
    let choices: [Selection]
    var solitudeStory: String? = nil
    var chapters: [EncounterChapter]? = nil
    var characterID: UUID? = nil
    var characterName: String? = nil
    var placeID: String? = nil
    var releaseID: String? = nil
    var photoAssetName: String? = nil
    var placeTitle: String? = nil
    var photo: BackendActivityPhoto? = nil
    var endedEarly: Bool? = nil
    var solitudeEnglish: String? = nil
    struct Selection: Codable, Equatable {
        let context: String
        let question: String
        let english: String
        let chinese: String
        let response: String
    }
}

/// Explicitly local, scoped to both account and city. Corrupt or newer data is
/// kept intact; failed loading must never be followed by an empty overwrite.
struct ActivityJournal {
    private struct Archive: Codable { let version: Int; var records: [ActivityRecord] }
    enum JournalError: Error { case unsupportedVersion, invalidCompletion }
    let defaults: UserDefaults
    let key: String

    init(namespace: String, city: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let scope = Data("\(namespace.utf8.count):\(namespace)\(city)".utf8).base64EncodedString()
        key = "lingotrip.activity-journal.v1.\(scope)"
    }
    func records() throws -> [ActivityRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        guard archive.version == 1 else { throw JournalError.unsupportedVersion }
        return archive.records
    }

    @discardableResult
    func completePlaceOuting(_ outing: BackendOuting, date: Date = Date()) throws -> [ActivityRecord] {
        guard outing.status == .completed else { throw JournalError.invalidCompletion }
        return try endPlaceOuting(outing, date: date)
    }
    @discardableResult
    func endPlaceOuting(_ outing: BackendOuting, date: Date = Date()) throws -> [ActivityRecord] {
        try PlaceOutingProgress.validate(outing)
        guard [.completed, .abandoned].contains(outing.status) else { throw JournalError.invalidCompletion }
        var saved = try records()
        guard !saved.contains(where: { $0.id == outing.runId }) else { return saved }
        var chapters = PlaceOutingProgress.chapters(outing)
        if outing.status == .abandoned, !chapters.isEmpty {
            let last = chapters.removeLast()
            chapters.append(.init(title: last.title, outline: last.outline,
                beats: Array(last.beats.prefix(max(0, outing.beatIndex + 1))), choices: last.choices))
        }
        let selections = zip(chapters, outing.choices).compactMap { chapter, choiceID -> ActivityRecord.Selection? in
            guard let index = Int(choiceID.split(separator: ":").last ?? ""), chapter.choices.indices.contains(index) else { return nil }
            let choice = chapter.choices[index]
            return .init(context: chapter.title, question: "你想怎么做？", english: choice.english, chinese: choice.chinese, response: "")
        }
        saved.append(.init(id: outing.runId, activityID: outing.placeId,
            title: outing.mode == .solitude ? outing.solitude.titleZh : chapters.first?.title ?? outing.placeTitleZh,
            date: date, choices: selections, solitudeStory: outing.mode == .solitude ? outing.solitude.chinese : nil,
            chapters: outing.mode == .solitude ? nil : chapters, characterID: outing.npc?.id, characterName: outing.npc?.card.name,
            placeID: outing.placeId, releaseID: outing.releaseId, photoAssetName: outing.photo.assetName,
            placeTitle: outing.placeTitleZh, photo: outing.photo, endedEarly: outing.status == .abandoned,
            solitudeEnglish: outing.mode == .solitude ? outing.solitude.english : nil))
        defaults.set(try JSONEncoder().encode(Archive(version: 1, records: saved)), forKey: key)
        return saved
    }
    @discardableResult
    func completeSolitude(_ activity: SceneActivity, runID: UUID, date: Date = Date()) throws -> [ActivityRecord] {
        var saved = try records()
        guard !saved.contains(where: { $0.id == runID }) else { return saved }
        saved.append(.init(id: runID, activityID: activity.id, title: activity.solitude.title,
            date: date, choices: [], solitudeStory: activity.solitude.story))
        defaults.set(try JSONEncoder().encode(Archive(version: 1, records: saved)), forKey: key)
        return saved
    }
    @discardableResult
    func complete(_ activity: SceneActivity, selections: [Int], runID: UUID, date: Date = Date(),
                  characterID: UUID? = nil, characterName: String? = nil, responses: [String] = [], chapters: [EncounterChapter]? = nil) throws -> [ActivityRecord] {
        let isReunion = chapters?.count == 1 && chapters?.first?.choices.isEmpty == true && selections.isEmpty
        guard isReunion || selections.count == activity.steps.count,
              zip(activity.steps, selections).allSatisfy({ $0.choices.indices.contains($1) })
        else { throw JournalError.invalidCompletion }
        var saved = try records()
        guard !saved.contains(where: { $0.id == runID }) else { return saved }
        let choices = zip(activity.steps, selections).enumerated().map { stepIndex, pair in
            let (step, index) = pair
            let choice = step.choices[index]
            return ActivityRecord.Selection(context: step.context, question: step.question, english: choice.english,
                                            chinese: choice.chinese, response: responses.indices.contains(stepIndex)
                                                ? "\(responses[stepIndex])\n\(choice.response)" : choice.response)
        }
        saved.append(.init(id: runID, activityID: activity.id, title: chapters?.first?.title ?? activity.title, date: date, choices: choices,
                           chapters: chapters, characterID: characterID, characterName: characterName))
        defaults.set(try JSONEncoder().encode(Archive(version: 1, records: saved)), forKey: key)
        return saved
    }
}
