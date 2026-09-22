import Foundation
import Testing
@testable import DomainKit

@Suite("学习回顾真实使用队列")
struct LearningReviewQueueTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    @Test func foregroundDoesNotForceFreshMessages() {
        let fresh = LearningReviewQueue.Candidate(id: UUID(), count: 1, lastDate: now)
        #expect(LearningReviewQueue.next([fresh], now: now) == nil)
        #expect(LearningReviewQueue.next([fresh], now: now, force: true) == fresh.id)
        #expect(LearningReviewQueue.next([fresh], now: now.addingTimeInterval(89.999)) == nil)
        #expect(LearningReviewQueue.next([fresh], now: now.addingTimeInterval(90)) == fresh.id)
    }
    @Test func readyConversationIsNotBlockedByFreshConversation() {
        let a = LearningReviewQueue.Candidate(id: UUID(), count: 1, lastDate: now)
        let b = LearningReviewQueue.Candidate(id: UUID(), count: 4, lastDate: now)
        #expect(LearningReviewQueue.next([a,b], now: now) == b.id)
        #expect(LearningReviewQueue.next([.init(id: UUID(), count: 0, lastDate: .distantPast)], now: now, force: true) == nil)
    }
    @Test func backlogPreservesChronologyAndEveryMessage() {
        var pending = (0..<100).map { "Message \($0): " + String(repeating: "a", count: 900) }
        let original = pending
        var evaluated: [String] = []
        while !pending.isEmpty {
            let count = LearningReviewQueue.prefixCount(pending)
            #expect(count > 0 && count <= 8)
            #expect(pending.prefix(count).reduce(0) { $0 + $1.count } <= 4000)
            evaluated += pending.prefix(count); pending.removeFirst(count)
        }
        #expect(evaluated == original)
    }
    @Test func oversizedMessageCannotDiscardFollowingShortMessages() {
        #expect(LearningReviewQueue.prefixCount([String(repeating: "x", count: 4001), "Hello"]) == 0)
        #expect(LearningReviewQueue.prefixCount(["Hello", String(repeating: "x", count: 4001)]) == 1)
    }
    @Test func greetingAndIncompleteAnswerKeepChallengeOpen() throws {
        #expect(!LearningReviewQueue.endsChallenge(paused: false, assessments: []))
        #expect(LearningReviewQueue.endsChallenge(paused: true, assessments: []))
        for (scores, expected) in [([1,2,2,2],false),([2,2,1,1],true),([2,0,2,2],false)] {
            let data = try JSONSerialization.data(withJSONObject: ["skill":"preference","band":1,"topic":"food","scores":scores,"messageIDs":[],"quote":"Tea","explanation":"test"])
            let item = try JSONDecoder().decode(LearningSystemReviewer.Assessment.self, from:data)
            #expect(LearningReviewQueue.endsChallenge(paused: false, assessments: [item]) == expected)
        }
    }
}
