import Foundation
import Testing
@testable import DomainKit

@Suite("量化学习系统规则")
struct LearningSystemPolicyTests {
    typealias P = LearningSystemPolicy
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    func evidence(day: Double, index: Int, scores: [Int] = [2,2,1,1], independent: Bool = true, confirmation: Bool = false, topic: String? = nil) -> P.Evidence {
        .init(batchID: UUID(), characterID: UUID(), date: start.addingTimeInterval(day * P.day), skill: .preference, band: 1,
              topic: topic ?? ["food","travel","hobbies"][index % 3], scores: scores,
              quote: "I choose option \(index) for reason \(index).", explanation: "选择与理由清楚", independent: independent, confirmation: confirmation)
    }
    func insert(_ value: P.Evidence, into ledger: inout P.Ledger) { let accepted = ledger.record([value], batchID: value.batchID, now: value.date); #expect(accepted) }
    @Test func scoreBoundaries() {
        #expect(evidence(day:0,index:0).successful)
        #expect(!evidence(day:0,index:0,scores:[1,2,2,2]).successful)
        #expect(!evidence(day:0,index:0,scores:[2,2,2,0]).successful)
        #expect(!evidence(day:0,index:0,scores:[2,1,1,1]).successful)
        #expect(!evidence(day:0,index:0,scores:[2,2,2]).valid)
        #expect(!evidence(day:0,index:0,scores:[3,2,2,2]).valid)
    }
    @Test func fourteenDayConfirmation() {
        var ledger = P.Ledger()
        for (i, day) in [0,1,2,3,4,7].enumerated() { insert(evidence(day:Double(day),index:i), into:&ledger) }
        #expect(ledger.status(skill:.preference,band:1,now:start.addingTimeInterval(7*P.day)) == .ready)
        insert(evidence(day:12,index:6,confirmation:true,topic:"work"),into:&ledger)
        #expect(ledger.status(skill:.preference,band:1,now:start.addingTimeInterval(12*P.day)) == .ready)
        #expect(ledger.nextConfirmationDate(skill: .preference, band: 1, now: start.addingTimeInterval(12 * P.day)) == start.addingTimeInterval(14 * P.day))
        insert(evidence(day:14,index:7,confirmation:true,topic:"study"),into:&ledger)
        #expect(ledger.status(skill:.preference,band:1,now:start.addingTimeInterval(14*P.day)) == .confirmed)
        ledger.delete(ledger.evidence.last!.id)
        #expect(ledger.status(skill:.preference,band:1,now:start.addingTimeInterval(14*P.day)) == .ready)
    }
    @Test func practiceCannotForgeIndependence() {
        var ledger = P.Ledger()
        for i in 0..<8 { insert(evidence(day:Double(i),index:i,independent:false),into:&ledger) }
        #expect(ledger.status(skill:.preference,band:1,now:start.addingTimeInterval(8*P.day)) == .attempted)
    }
    @Test func repeatedDayDoesNotAdvance() {
        var ledger = P.Ledger()
        for i in 0..<8 { insert(evidence(day:Double(i)/100,index:i),into:&ledger) }
        #expect(ledger.independentEvidence(skill:.preference,band:1,now:start.addingTimeInterval(P.day)).count == 1)
        #expect(ledger.xp == 30)
        #expect(ledger.level == 1)
    }
    @Test func idempotenceAndDeletionTombstone() throws {
        var ledger = P.Ledger(); let e=evidence(day:0,index:0)
        insert(e,into:&ledger)
        let duplicate = ledger.record([e],batchID:e.batchID,now:e.date); #expect(!duplicate)
        ledger.delete(e.id)
        ledger.award(key:e.fingerprint,now:e.date.addingTimeInterval(P.day))
        #expect(ledger.xp == 10)
        #expect(ledger.nextReview(now:e.date.addingTimeInterval(3*P.day)) == nil)
        #expect(try JSONDecoder().decode(P.Ledger.self,from:JSONEncoder().encode(ledger)) == ledger)
    }
    @Test func clockRollbackFailsClosed() {
        var ledger=P.Ledger(); insert(evidence(day:2,index:0),into:&ledger)
        let earlier=evidence(day:1,index:1)
        let accepted = ledger.record([earlier],batchID:earlier.batchID,now:earlier.date); #expect(!accepted)
        #expect(ledger.nextReview(now:start) == nil)
    }
    @Test func exactReviewIntervals() {
        var ledger=P.Ledger();let e=evidence(day:0,index:0);insert(e,into:&ledger)
        #expect(ledger.nextReview(now:start.addingTimeInterval(2*P.day-1)) == nil)
        #expect(ledger.nextReview(now:start.addingTimeInterval(2*P.day))?.id == e.id)
        ledger.deferredUntil=start.addingTimeInterval(3*P.day)
        #expect(ledger.nextReview(now:start.addingTimeInterval(2*P.day)) == nil)
    }
    @Test func taskBankHasDistinctCompleteCoverage() {
        let bank=LearningTask.bank
        #expect(bank.count == 216)
        #expect(Set(bank.map(\.id)).count == bank.count)
        for skill in P.Skill.allCases { for band in 1...3 {
            #expect(bank.filter { $0.skill == skill && $0.band == band }.count == 18)
        } }
    }
    func bank() -> [LearningListeningItem] {
        (0..<12).map { i in
            LearningListeningItem(id:"q\(i)",band:1,skill:LearningListeningItem.Skill.allCases[i%3],script:"I usually walk to the small library after school because it is quiet and I can read my favourite books there.",question:"去哪？",options:["图书馆","学校","商店"],answer:0,explanation:"图书馆")
        }
    }
    @Test func listeningRequiresCompletedPlaybackAndLocksAnswer() throws {
        var s=try #require(LearningListeningSession(band:1,bank:bank(),seen:[],now:start))
        do { let accepted = s.answer(0,now:start); #expect(!accepted) }
        let item=try #require(s.current)
        s.completedPlayback(itemID:"wrong")
        do { let accepted = s.answer(0,now:start); #expect(!accepted) }
        s.completedPlayback(itemID:item.id);s.completedPlayback(itemID:item.id);s.completedPlayback(itemID:item.id)
        #expect(s.plays[item.id] == 2)
        let accepted = s.answer(item.answer,now:start); #expect(accepted)
        #expect(s.score == 1)
        do { let accepted = s.answer(0,now:start); #expect(!accepted) }
    }
    @Test func listeningTwoFreshFormsSevenDays() throws {
        var a=try #require(LearningListeningSession(band:1,bank:bank(),seen:[],now:start))
        while let q=a.current { a.completedPlayback(itemID:q.id);let accepted = a.answer(q.answer,now:start); #expect(accepted) }
        #expect(!LearningListeningSession.confirmed(band:1,sessions:[a],now:start))
        var b=try #require(LearningListeningSession(band:1,bank:bank(),seen:Set(a.items.map(\.id)),now:start.addingTimeInterval(7*P.day)))
        while let q=b.current { b.completedPlayback(itemID:q.id);let accepted = b.answer(q.answer,now:b.startedAt); #expect(accepted) }
        #expect(LearningListeningSession.confirmed(band:1,sessions:[a,b],now:b.startedAt))
        #expect(LearningListeningSession(band:1,bank:bank(),seen:Set((a.items+b.items).map(\.id)),now:start) == nil)
    }
    @Test("跨日、主题和正确次数缺一不可", arguments: 0..<3)
    func readinessNeedsAllConditions(_ condition: Int) {
        var ledger = P.Ledger()
        for i in 0..<6 {
            let e = evidence(day: condition == 0 ? Double(i) : Double(i * 2), index: i,
                scores: condition == 2 && i < 2 ? [1,1,1,1] : [2,2,1,1],
                topic: condition == 1 ? "food" : nil)
            insert(e, into: &ledger)
        }
        #expect(ledger.status(skill: .preference, band: 1, now: start.addingTimeInterval(12 * P.day)) != .ready)
    }
    @Test func confirmedSkillSurvivesOneFailureThenAges() {
        var ledger = P.Ledger()
        for (i, d) in [0,1,2,3,4,7].enumerated() { insert(evidence(day: Double(d), index: i), into: &ledger) }
        insert(evidence(day: 12, index: 6, confirmation: true, topic: "work"), into: &ledger)
        insert(evidence(day: 14, index: 7, confirmation: true, topic: "study"), into: &ledger)
        insert(evidence(day: 15, index: 8, scores: [0,1,1,1]), into: &ledger)
        #expect(ledger.status(skill: .preference, band: 1, now: start.addingTimeInterval(15 * P.day)) == .confirmed)
        #expect(ledger.status(skill: .preference, band: 1, now: start.addingTimeInterval(104 * P.day + 1)) == .stale)
    }
    @Test func differentAudioVersionsCannotConfirm() throws {
        var a = try #require(LearningListeningSession(band: 1, bank: bank(), seen: [], now: start, audioVersion: "old"))
        while let q = a.current { a.completedPlayback(itemID: q.id); _ = a.answer(q.answer, now: start) }
        var b = try #require(LearningListeningSession(band: 1, bank: bank(), seen: Set(a.items.map(\.id)), now: start.addingTimeInterval(7 * P.day), audioVersion: "new"))
        while let q = b.current { b.completedPlayback(itemID: q.id); _ = b.answer(q.answer, now: b.startedAt) }
        #expect(!LearningListeningSession.confirmed(band: 1, sessions: [a,b], now: b.startedAt))
    }
    @Test func listeningWeakSubskillCannotHideBehindTotal() throws {
        var sessions: [LearningListeningSession] = []
        for day in [0,7] {
            var s = try #require(LearningListeningSession(band: 1, bank: bank(), seen: Set(sessions.flatMap { $0.items.map(\.id) }), now: start.addingTimeInterval(Double(day) * P.day)))
            var missed = false
            while let q = s.current {
                s.completedPlayback(itemID: q.id)
                let wrong = q.skill == .intention && !missed
                if wrong { missed = true }
                _ = s.answer(wrong ? (q.answer + 1) % 3 : q.answer, now: s.startedAt)
            }
            #expect(s.score == 5); sessions.append(s)
        }
        #expect(!LearningListeningSession.confirmed(band: 1, sessions: sessions, now: sessions.last!.startedAt))
    }

    @Test func deletedEvidenceCannotReappearThroughDuplicate() {
        var ledger = P.Ledger()
        let original = evidence(day: 0, index: 0)
        insert(original, into: &ledger); ledger.delete(original.id)
        let duplicate = evidence(day: 3, index: 0)
        insert(duplicate, into: &ledger)
        #expect(ledger.independentEvidence(skill: .preference, band: 1, now: duplicate.date).isEmpty)
        #expect(ledger.xp == 10)
    }

}
