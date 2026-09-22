import Foundation
import Testing
@testable import DomainKit

@Suite("对话学习原型闭环")
struct ConversationLearningPrototypeTests {
    typealias Ledger = ConversationLearningLedger
    private func start(_ ledger: inout Ledger, day: Int = 1, context: String = "café", text: String = "I prefer tea because it is warm.", assisted: Bool = false, voice: Bool = false) -> (UUID, UUID) {
        let id = ledger.begin(context: context, character: "Ruby", day: day, origin: .replay)
        if assisted { ledger.observe(.assistance, attemptID: id) }
        let message = UUID()
        ledger.observe(.sent(id: message, text: text, voice: voice), attemptID: id)
        return (id, message)
    }
    private func complete(_ ledger: inout Ledger, id: UUID, message: UUID) throws {
        try ledger.apply(.init(verdict: .complete, evidenceMessageIDs: [message], feedback: "完成表达"), attemptID: id, expectedRevision: ledger.revision)
    }
    @Test("重复回调与重复文本不重复奖励，删除原文保留无原文的去重标记")
    func duplicateAndDeletion() throws {
        var ledger = Ledger()
        let (id, message) = start(&ledger)
        let revision = ledger.revision
        try complete(&ledger, id: id, message: message)
        #expect(ledger.xp == 10)
        #expect(try !ledger.apply(.init(verdict: .complete, evidenceMessageIDs: [message], feedback: "again"), attemptID: id, expectedRevision: revision))
        ledger.deleteEvidence(id)
        #expect(ledger.attempts[0].turns.isEmpty)
        #expect(ledger.attempts[0].evidence.isEmpty)
        #expect(!ledger.attempts[0].independent)
        #expect(ledger.rewardKeys.allSatisfy { !$0.contains("tea") })
        let (retry, repeated) = start(&ledger, day: 2, text: "I PREFER TEA, because it is warm!")
        try complete(&ledger, id: retry, message: repeated)
        #expect(ledger.xp == 10)
        #expect(!ledger.attempts[1].independent)
    }
    @Test("重组旧句引用不重复发奖")
    func recombinedEvidence() throws {
        var ledger = Ledger()
        let (first, old) = start(&ledger)
        try complete(&ledger, id: first, message: old)
        let (second, repeated) = start(&ledger, day: 2)
        let added = UUID()
        ledger.observe(.sent(id: added, text: "It also smells good.", voice: false), attemptID: second)
        try ledger.apply(.init(verdict: .complete, evidenceMessageIDs: [repeated, added], feedback: ""), attemptID: second, expectedRevision: ledger.revision)
        #expect(ledger.xp == 10)
        #expect(!ledger.attempts[1].independent)
    }
    @Test("辅助和语音转写不冒充独立掌握，但参与奖励相同")
    func helpAndVoice() throws {
        for pair in [(true, false), (false, true), (false, false)] {
            var ledger = Ledger()
            let (id, message) = start(&ledger, assisted: pair.0, voice: pair.1)
            try complete(&ledger, id: id, message: message)
            #expect(ledger.xp == 10)
            #expect(ledger.attempts[0].independent == (!pair.0 && !pair.1))
        }
    }
    @Test("迟到判定、虚构证据、放弃后的判定不发奖励")
    func staleAndInvalid() throws {
        var ledger = Ledger()
        let (id, message) = start(&ledger)
        let old = ledger.revision
        ledger.observe(.assistance, attemptID: id)
        #expect(throws: Ledger.Rejection.self) { try ledger.apply(.init(verdict: .complete, evidenceMessageIDs: [message], feedback: ""), attemptID: id, expectedRevision: old) }
        #expect(throws: Ledger.Rejection.self) { try ledger.apply(.init(verdict: .complete, evidenceMessageIDs: [UUID()], feedback: ""), attemptID: id, expectedRevision: ledger.revision) }
        ledger.abandon(id)
        #expect(throws: Ledger.Rejection.self) { try ledger.apply(.init(verdict: .complete, evidenceMessageIDs: [message], feedback: ""), attemptID: id, expectedRevision: ledger.revision) }
        #expect(ledger.xp == 0)
    }
    @Test("持久化恢复未完成尝试，不额外建关卡")
    func resume() throws {
        var ledger = Ledger()
        let (id, _) = start(&ledger, assisted: true)
        let data = try JSONEncoder().encode(ledger)
        var restored = try JSONDecoder().decode(Ledger.self, from: data)
        #expect(restored == ledger)
        #expect(restored.begin(context: "other", character: "Oliver", day: 50, origin: .replay) == id)
        #expect(restored.active?.assistanceUsed == true)
    }
    @Test("不确定不关卡失败；补充后可重新评价")
    func uncertain() throws {
        var ledger = Ledger()
        let (id, message) = start(&ledger)
        try ledger.apply(.init(verdict: .uncertain, evidenceMessageIDs: [message], feedback: "再说一个理由"), attemptID: id, expectedRevision: ledger.revision)
        #expect(ledger.active?.id == id)
        #expect(ledger.xp == 0)
        try complete(&ledger, id: id, message: message)
        #expect(ledger.xp == 10)
    }
    @Test("来源未知只记练习；回放证据不能混入真实能力判断")
    func originAndUnknown() throws {
        var ledger = Ledger()
        for day in 0..<3 {
            let (id, message) = start(&ledger, day: day, context: "context \(day)", text: "Option \(day) suits me because I enjoy it.")
            try complete(&ledger, id: id, message: message)
        }
        #expect(ledger.abilityDescription.contains("多个情境"))
        let id = ledger.begin(context: "live", character: "Ruby", day: 4, origin: .live)
        let message = UUID()
        ledger.observe(.unattributed, attemptID: id)
        ledger.observe(.sent(id: message, text: "I prefer a book because it relaxes me.", voice: false), attemptID: id)
        try complete(&ledger, id: id, message: message)
        #expect(!ledger.attempts.last!.independent)
        #expect(!ledger.abilityDescription.contains("多个情境"))
    }
    @Test("轻重用户半年回放：日奖励有界，重复事件不增加经验，证据时间与情境独立")
    func sixMonthReplay() throws {
        for dailyAttempts in [1, 3, 20] {
            var ledger = Ledger()
            for day in 0..<180 {
                for attempt in 0..<dailyAttempts {
                    let (id, message) = start(&ledger, day: day, context: day.isMultiple(of: 2) ? "beach" : "book", text: "I choose option \(day)-\(attempt) because it suits me.", assisted: attempt.isMultiple(of: 3))
                    let revision = ledger.revision
                    ledger.observe(.sent(id: message, text: "duplicate", voice: false), attemptID: id)
                    #expect(ledger.revision == revision)
                    try complete(&ledger, id: id, message: message)
                }
                #expect(ledger.xp <= (day + 1) * 30)
            }
            #expect(ledger.attempts.count == dailyAttempts * 180)
            #expect(ledger.active == nil)
            #expect(ledger.attempts.allSatisfy { $0.awardedXP == 0 || $0.awardedXP == 10 })
        }
    }
}
