import Foundation
import PersistenceKit
import Testing
@testable import ChatFeature

struct ChatTimelineEventPolicyTests {
    @Test func ordinaryEventsFollowFinishedTurnsAndAreSpaced() {
        let events = [
            ChatMessageTimelineEvent(kind: .mood, state: "sad", strength: 2),
            ChatMessageTimelineEvent(kind: .memory, state: "remembered"),
            ChatMessageTimelineEvent(kind: .relationship, state: "affinity", delta: 0.2),
            ChatMessageTimelineEvent(kind: .mood, state: "angry", strength: 3),
        ]
        var messages: [MessageDTO] = []
        for event in events {
            messages.append(message(.user, events: [event], index: messages.count))
            messages.append(message(.assistant, index: messages.count))
        }
        let projected = ChatTimelineEventPolicy.ordinaryEvents(in: messages)
        #expect(projected[messages[1].id] == events[0])
        #expect(projected[messages[7].id] == events[3])
        #expect(projected.count == 2)
        #expect(ChatTimelineEventPolicy.ordinaryEvents(in: [messages[0]]).isEmpty)
    }

    @Test func aUserBurstSharesOneSlotAndSameMoodDoesNotRepeat() {
        let mood = ChatMessageTimelineEvent(kind: .mood, state: "angry", strength: 3)
        let memory = ChatMessageTimelineEvent(kind: .memory, state: "updated")
        let messages = [
            message(.user, events: [memory], index: 0),
            message(.user, events: [mood], index: 1),
            message(.assistant, index: 2),
            message(.assistant, index: 3),
            message(.user, index: 4), message(.assistant, index: 5),
            message(.user, index: 6), message(.assistant, index: 7),
            message(.user, events: [mood], index: 8), message(.assistant, index: 9),
        ]
        let projected = ChatTimelineEventPolicy.ordinaryEvents(in: messages)
        #expect(projected == [messages[3].id: mood])
    }

    @Test func sparseMeaningfulChangesStillSurface() {
        let memory = ChatMessageTimelineEvent(kind: .memory, state: "corrected")
        let relationship = ChatMessageTimelineEvent(kind: .relationship, state: "affinity", delta: -0.3)
        let messages = [
            message(.user, events: [memory], index: 0), message(.assistant, index: 1),
            message(.user, index: 2), message(.assistant, index: 3),
            message(.user, index: 4), message(.assistant, index: 5),
            message(.user, events: [relationship], index: 6), message(.assistant, index: 7),
        ]
        #expect(ChatTimelineEventPolicy.ordinaryEvents(in: messages) ==
                [messages[1].id: memory, messages[7].id: relationship])
    }

    @Test func denseAlternatingSignalsLeaveTwoTurnsQuiet() {
        let states = ["angry", "happy", "tired", "sad", "relieved"]
        let messages = (0..<30).flatMap { turn in
            [
                message(.user, events: [.init(kind: .mood, state: states[turn % states.count], strength: 3)], index: turn * 2),
                message(.assistant, index: turn * 2 + 1),
            ]
        }
        let results = ChatTimelineEventPolicy.ordinaryEvents(in: messages)
        let turnsWithEvents = (0..<30).filter { results[messages[$0 * 2 + 1].id] != nil }
        #expect(turnsWithEvents == Array(stride(from: 0, to: 30, by: 3)))
    }

    @Test func queuedInputCannotBorrowThePreviousReply() {
        let mood = ChatMessageTimelineEvent(kind: .mood, state: "sad", strength: 2)
        let first = message(.user, events: [mood], index: 0)
        let queued = message(.user, events: [.init(kind: .mood, state: "angry", strength: 3)], index: 1)
        var earlierReply = message(.assistant, index: 2)
        earlierReply.replyToMessageIDs = [first.id]
        var laterReply = message(.assistant, index: 3)
        laterReply.replyToMessageIDs = [queued.id]
        let projected = ChatTimelineEventPolicy.ordinaryEvents(in: [first, queued, earlierReply, laterReply])
        #expect(projected == [earlierReply.id: mood])
    }

    private func message(_ role: MessageRole, events: [ChatMessageTimelineEvent] = [], index: Int) -> MessageDTO {
        MessageDTO(id: UUID(), role: role, kind: .text, text: "dialogue", orderIndex: index,
                   timelineEvents: events, createdAt: Date(timeIntervalSince1970: Double(index * 15)))
    }
}
