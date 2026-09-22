import Foundation
import Testing
@testable import DomainKit

@Suite("学习回顾真实使用队列")
struct LearningReviewQueueTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    @Test func retryAcrossMidnightUsesActualDayBudget() throws {
        let midnight = Date(timeIntervalSince1970: Double(LearningSystemPolicy.utcDay(now) + 1) * LearningSystemPolicy.day)
        let yesterday = LearningSystemPolicy.utcDay(midnight.addingTimeInterval(-1))
        let today = LearningSystemPolicy.utcDay(midnight)
        var calls = [yesterday: 11]
        #expect(LearningReviewQueue.reserveCall(&calls, now: midnight.addingTimeInterval(-1)))
        #expect(calls[yesterday] == 12)
        #expect(LearningReviewQueue.reserveCall(&calls, now: midnight))
        #expect(calls[today] == 1)
        calls = try JSONDecoder().decode([Int:Int].self, from: JSONEncoder().encode(calls))
        for _ in 0..<11 { #expect(LearningReviewQueue.reserveCall(&calls, now: midnight)) }
        #expect(!LearningReviewQueue.reserveCall(&calls, now: midnight))
        #expect(calls[today] == 12)
        #expect(calls[yesterday] == 12)
    }

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
    @Test func failedBatchDoesNotBlockOtherChatsOrSpinAutomaticRetries() {
        let failed = LearningReviewQueue.Candidate(id: UUID(), count: 4, lastDate: now, blocked: true)
        let healthy = LearningReviewQueue.Candidate(id: UUID(), count: 4, lastDate: now)
        #expect(failed.delay(now: now) == nil)
        #expect(LearningReviewQueue.next([failed], now: now) == nil)
        #expect(LearningReviewQueue.next([failed,healthy], now: now) == healthy.id)
        #expect(LearningReviewQueue.next([failed,healthy], now: now, force: true) == failed.id)
    }

    @Test func taskContextKeepsOrderAssistanceAndRemovesDeletedMessages() throws {
        let a = LearningSystemReviewer.Turn(id:UUID(),text:"I choose the park.")
        let b = LearningSystemReviewer.Turn(id:UUID(),text:"Because it is quiet.")
        let first = LearningChallengeContext().appending([a],assisted:true,available:[a.id])
        let restored = try JSONDecoder().decode(LearningChallengeContext.self,from:JSONEncoder().encode(first))
        let combined = restored.appending([a,b],assisted:false,available:[a.id,b.id])
        #expect(combined.turns.map(\.id) == [a.id,b.id])
        #expect(combined.assisted)
        #expect(combined.appending([],assisted:false,available:[b.id]).turns.map(\.id) == [b.id])
    }
    @Test func taskContextHasHardSizeAndCountBounds() {
        let turns = (0..<20).map { LearningSystemReviewer.Turn(id:UUID(),text:"Message \($0)") }
        let context = LearningChallengeContext().appending(turns,assisted:false,available:Set(turns.map(\.id)))
        #expect(context.turns.map(\.id) == turns.suffix(8).map(\.id))
        let large = (0..<5).map { _ in LearningSystemReviewer.Turn(id:UUID(),text:String(repeating:"a",count:1500)) }
        let bounded = LearningChallengeContext().appending(large,assisted:false,available:Set(large.map(\.id)))
        #expect(bounded.turns.count == 2)
        #expect(bounded.turns.reduce(0) { $0 + $1.text.count } <= 4000)
    }

}
