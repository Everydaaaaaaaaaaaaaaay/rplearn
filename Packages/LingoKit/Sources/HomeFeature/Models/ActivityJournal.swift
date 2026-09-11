import Foundation
import DomainKit

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
