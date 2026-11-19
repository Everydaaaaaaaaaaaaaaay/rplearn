import Foundation
import PersistenceKit

enum ChatTimelineEventPolicy {
    /// A turn can hold several user messages and several assistant bubbles.
    static func ordinaryEvents(in messages: [MessageDTO]) -> [UUID: ChatMessageTimelineEvent] {
        var result: [UUID: ChatMessageTimelineEvent] = [:]
        let completed = completedTurns(in: messages)
        var completedTurns = 0
        var lastShownTurn = -3
        var lastShownAt = Date.distantPast
        var lastShownMood: ChatMessageTimelineEvent?
        var lastMoodTurn = -8
        var lastMoodAt = Date.distantPast

        for reply in messages {
            guard let candidates = completed[reply.id] else { continue }
            completedTurns += 1
            guard completedTurns - lastShownTurn >= 3 || reply.createdAt.timeIntervalSince(lastShownAt) >= 20 * 60 else { continue }
            let eligible = candidates.filter { event in
                guard event.kind == .mood else { return true }
                if event.state == "calm", lastShownMood == nil { return false }
                guard let previous = lastShownMood,
                      completedTurns - lastMoodTurn < 8,
                      reply.createdAt.timeIntervalSince(lastMoodAt) < 45 * 60 else { return true }
                let sameFeelings = Set([event.state, event.secondary ?? ""]) ==
                    Set([previous.state, previous.secondary ?? ""])
                return !sameFeelings || (event.strength ?? 1) > (previous.strength ?? 1)
            }
            guard let event = eligible.max(by: { priority($0) < priority($1) }) else { continue }
            result[reply.id] = event
            lastShownTurn = completedTurns
            lastShownAt = reply.createdAt
            if event.kind == .mood {
                lastShownMood = event
                lastMoodTurn = completedTurns
                lastMoodAt = reply.createdAt
            }
        }
        return result
    }

    private static func completedTurns(in messages: [MessageDTO]) -> [UUID: [ChatMessageTimelineEvent]] {
        var linked: [UUID: UUID] = [:]
        for reply in messages where reply.role == .assistant && !reply.isInterrupted {
            for input in reply.replyToMessageIDs { linked[input] = reply.id }
        }
        var results: [UUID: [ChatMessageTimelineEvent]] = [:]
        var localCandidates: [ChatMessageTimelineEvent] = []
        var localReply: UUID?
        var hasLocalInput = false
        for message in messages {
            switch message.role {
            case .user:
                if let localReply {
                    results[localReply] = localCandidates
                    localCandidates.removeAll(keepingCapacity: true)
                    hasLocalInput = false
                }
                localReply = nil
                if let reply = linked[message.id] {
                    results[reply, default: []].append(contentsOf: message.timelineEvents)
                } else {
                    hasLocalInput = true
                    localCandidates.append(contentsOf: message.timelineEvents)
                }
            case .assistant:
                if hasLocalInput, !message.isInterrupted, message.replyToMessageIDs.isEmpty { localReply = message.id }
            case .coach:
                break
            }
        }
        if let localReply { results[localReply] = localCandidates }
        return results
    }

    private static func priority(_ event: ChatMessageTimelineEvent) -> Int {
        switch event.kind {
        case .mood: (event.strength ?? 1) >= 3 ? 6 : 5
        case .memory: 3
        case .relationship: event.state == "affinity" ? 1 : 4
        }
    }
}
