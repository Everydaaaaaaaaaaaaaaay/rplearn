import Foundation
import Testing
@testable import DomainKit

@Suite("对话学习原型闭环")
struct ConversationLearningPrototypeTests {
    typealias Ledger = ConversationLearningLedger
    @Test("真实操作组合：来源、帮助时机、重启、关闭与延迟评价", arguments: 0..<96)
    func lifecycleCombinations(_ scenario: Int) throws {
        var ledger = Ledger()
        let voice = scenario % 2 == 1
        let help = (scenario / 2) % 3
        let restore = (scenario / 6) % 2 == 1
        let ending = (scenario / 12) % 4
        let origin: Ledger.Origin = scenario < 48 ? .live : .replay
        let id = ledger.begin(context: "weekend", character: "Ruby", day: 1, origin: origin)
        if help == 1 { ledger.observe(.assistance, attemptID: id) }
        let first = UUID(), second = UUID()
        ledger.observe(.sent(id: first, text: "The park.", voice: voice), attemptID: id)
        ledger.observe(.sent(id: second, text: "It is close to home.", voice: voice), attemptID: id)
        if help == 2 { ledger.observe(.assistance, attemptID: id) }
        if restore { ledger = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger)) }
        let reviewedRevision = ledger.revision
        let review = Ledger.Review(verdict: .complete, evidenceMessageIDs: [first, second], feedback: "意思清楚")
        switch ending {
        case 1: ledger.abandon(id)
        case 2: ledger.deleteEvidence(id)
        case 3: ledger.observe(.sent(id: UUID(), text: "Actually I have changed my mind.", voice: false), attemptID: id)
        default: break
        }
        if ending == 0 {
            try ledger.apply(review, attemptID: id, expectedRevision: reviewedRevision, completedDay: 2)
            #expect(ledger.xp == 10)
            #expect(ledger.attempts.last?.independent == (!voice && help == 0))
            #expect(ledger.attempts.last?.day == 2)
            #expect(try !ledger.apply(review, attemptID: id, expectedRevision: reviewedRevision))
        } else {
            #expect(throws: Ledger.Rejection.self) {
                try ledger.apply(review, attemptID: id, expectedRevision: reviewedRevision)
            }
            #expect(ledger.xp == 0)
        }
        let restored = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        #expect(restored == ledger)
    }
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
    @Test("新旧混合表达奖励新增内容，重组已用引用不重复发奖")
    func recombinedEvidence() throws {
        var ledger = Ledger()
        let (first, old) = start(&ledger)
        try complete(&ledger, id: first, message: old)
        let (second, repeated) = start(&ledger, day: 2)
        let added = UUID()
        ledger.observe(.sent(id: added, text: "It also smells good.", voice: false), attemptID: second)
        try ledger.apply(.init(verdict: .complete, evidenceMessageIDs: [repeated, added], feedback: ""), attemptID: second, expectedRevision: ledger.revision)
        #expect(ledger.xp == 20)
        let (third, again) = start(&ledger, day: 3)
        let repeatedAddition = UUID()
        ledger.observe(.sent(id: repeatedAddition, text: "It also smells good.", voice: false), attemptID: third)
        try ledger.apply(.init(verdict: .complete, evidenceMessageIDs: [repeatedAddition, again], feedback: ""), attemptID: third, expectedRevision: ledger.revision)
        #expect(ledger.xp == 20)
        #expect(!ledger.attempts[2].independent)
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
    @Test("长旧消息不阻塞新短句，送审不截断原文且有界")
    func boundedReviewWindow() throws {
        var ledger = Ledger()
        let (id, _) = start(&ledger, text: String(repeating: "x", count: 8001))
        #expect(ledger.active?.reviewTurns().isEmpty == true)
        let next = UUID()
        ledger.observe(.sent(id: next, text: "I prefer tea because it is warm.", voice: false), attemptID: id)
        #expect(ledger.active?.reviewTurns().map(\.id) == [next])
        #expect(ledger.active?.turns.first?.text.count == 8001)
        #expect(ledger.active?.reviewTurns(maxCount: 0).isEmpty == true)
        #expect(ledger.active?.reviewTurns(maxCharacters: 1).isEmpty == true)
    }
    @Test("跨天完成按完成日计入上限，重复引用被拒绝")
    func completionDayAndRepeatedIDs() throws {
        var ledger = Ledger()
        for index in 0..<3 {
            let (id, message) = start(&ledger, day: 2, text: "I choose \(index) because it helps.")
            try complete(&ledger, id: id, message: message)
        }
        let (id, message) = start(&ledger, day: 1, text: "I prefer reading because I enjoy stories.")
        #expect(throws: Ledger.Rejection.self) {
            try ledger.apply(.init(verdict: .complete, evidenceMessageIDs: [message, message], feedback: ""), attemptID: id, expectedRevision: ledger.revision)
        }
        try ledger.apply(.init(verdict: .complete, evidenceMessageIDs: [message], feedback: ""), attemptID: id, expectedRevision: ledger.revision, completedDay: 2)
        #expect(ledger.xp == 30)
        #expect(ledger.attempts.last?.day == 2)
        #expect(ledger.attempts.last?.awardedXP == 0)
        #expect(ledger.attempts.last?.rewardNote?.contains("上限") == true)
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
        #expect(!ledger.attempts.last!.independent)
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
