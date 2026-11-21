import BackendKit
import Foundation

/// Local projection for queued offline operations; the server remains authoritative.
public enum PlaceOutingProgress {
    public enum ProgressError: Error { case invalidContent, staleRevision, invalidAction, ended }

    public static func beats(_ outing: BackendOuting) -> [BackendOutingBeat] {
        outing.mode == .reunion ? outing.story?.reunion.beats ?? []
            : outing.story?.nodes.first { $0.id == outing.nodeId }?.beats ?? []
    }

    public static func validate(_ outing: BackendOuting) throws {
        guard outing.revision >= 0, outing.photo.cityId == outing.cityId,
              outing.photo.placeId == outing.placeId,
              outing.photo.width > 0, outing.photo.height > 0 else { throw ProgressError.invalidContent }
        if outing.mode == .solitude {
            guard outing.npc == nil, outing.story == nil, outing.choices.isEmpty else { throw ProgressError.invalidContent }
            return
        }
        guard let npc = outing.npc, let story = outing.story,
              npc.card.regionId == outing.cityId,
              Set(story.nodes.map(\.id)) == Set(["start", "a", "b", "aa", "ab", "ba", "bb"]), story.nodes.count == 7,
              (4...6).contains(story.reunion.beats.count), story.reunion.beats.first?.speaker == "narrator" else {
            throw ProgressError.invalidContent
        }
        let edges = ["start": ["a", "b"], "a": ["aa", "ab"], "b": ["ba", "bb"], "aa": [], "ab": [], "ba": [], "bb": []]
        for node in story.nodes {
            guard node.choices.map(\.next) == edges[node.id], (4...6).contains(node.beats.count),
                  node.beats.allSatisfy({ ["npc", "narrator"].contains($0.speaker) && !$0.english.isEmpty && !$0.chinese.isEmpty }) else {
                throw ProgressError.invalidContent
            }
        }
        guard outing.beatIndex >= -1, outing.beatIndex < beats(outing).count else { throw ProgressError.invalidContent }
        var nodeID = "start"
        for choiceID in outing.choices {
            guard let node = story.nodes.first(where: { $0.id == nodeID }),
                  let index = node.choices.indices.first(where: { "\(nodeID):\($0)" == choiceID }) else { throw ProgressError.invalidContent }
            nodeID = node.choices[index].next
        }
        guard outing.choices.count <= 2, nodeID == outing.nodeId else { throw ProgressError.invalidContent }
    }

    public static func apply(_ operation: BackendOutingOperation, to outing: BackendOuting) throws -> BackendOuting {
        try validate(outing)
        guard operation.expectedRevision == outing.revision else { throw ProgressError.staleRevision }
        guard ![.completed, .abandoned].contains(outing.status) else { throw ProgressError.ended }
        var next = outing
        switch operation.type {
        case .abandon: next.status = .abandoned
        case .read:
            guard outing.mode != .solitude, let index = operation.beatIndex,
                  index >= 0, index >= outing.beatIndex, index <= outing.beatIndex + 1,
                  index < beats(outing).count else { throw ProgressError.invalidAction }
            next.beatIndex = index
        case .presented:
            guard outing.status == .reserved,
                  outing.mode == .solitude || outing.beatIndex == beats(outing).count - 1 else { throw ProgressError.invalidAction }
            next.status = .opening_presented
        case .choice:
            guard outing.status != .reserved, outing.mode == .first_meeting,
                  let node = outing.story?.nodes.first(where: { $0.id == outing.nodeId }),
                  outing.beatIndex == node.beats.count - 1,
                  let index = node.choices.indices.first(where: { "\(node.id):\($0)" == operation.choiceId }) else { throw ProgressError.invalidAction }
            next.nodeId = node.choices[index].next; next.beatIndex = -1
            next.choices.append("\(node.id):\(index)"); next.status = .in_progress
        case .complete:
            let node = outing.story?.nodes.first { $0.id == outing.nodeId }
            guard outing.status != .reserved,
                  outing.mode == .solitude || outing.beatIndex == beats(outing).count - 1,
                  outing.mode != .first_meeting || (node?.choices.isEmpty == true && outing.choices.count == 2) else { throw ProgressError.invalidAction }
            next.status = .completed
        }
        next.revision += 1
        return next
    }

    public static func chapters(_ outing: BackendOuting) -> [EncounterChapter] {
        guard let story = outing.story else { return [] }
        if outing.mode == .reunion {
            return [.init(title: story.reunion.titleZh, outline: story.reunion.titleZh,
                beats: story.reunion.beats.map { .init(speaker: $0.speaker, english: $0.english, chinese: $0.chinese) }, choices: [])]
        }
        var result: [EncounterChapter] = [], id = "start"
        for index in 0...outing.choices.count {
            guard let node = story.nodes.first(where: { $0.id == id }) else { break }
            result.append(.init(title: story.titleZh, outline: story.titleZh,
                beats: node.beats.map { .init(speaker: $0.speaker, english: $0.english, chinese: $0.chinese) },
                choices: node.choices.map { .init(english: $0.english, chinese: $0.chinese) }))
            guard outing.choices.indices.contains(index),
                  let choiceIndex = node.choices.indices.first(where: { "\(id):\($0)" == outing.choices[index] }) else { break }
            id = node.choices[choiceIndex].next
        }
        return result
    }
}
