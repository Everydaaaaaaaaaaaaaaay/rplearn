import DomainKit
import Foundation
import Testing

@Suite("聊天内学习提示")
struct LearningChatPresentationTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    @Test("主动提示不打断输入或回复，日限额和冷却跨重启保留")
    func throttle() throws {
        var state = LearningChatPresentation()
        #expect(!state.canInvite(now: now, busy: true, composing: false))
        #expect(!state.canInvite(now: now, busy: false, composing: true))
        #expect(state.canInvite(now: now, busy: false, composing: false))
        state.markInvitation(now: now)
        state = try JSONDecoder().decode(LearningChatPresentation.self, from: JSONEncoder().encode(state))
        #expect(!state.canInvite(now: now.addingTimeInterval(599), busy: false, composing: false))
        #expect(state.canInvite(now: now.addingTimeInterval(600), busy: false, composing: false))
        state.markInvitation(now: now.addingTimeInterval(600))
        #expect(!state.canInvite(now: now.addingTimeInterval(1200), busy: false, composing: false))
        #expect(state.canInvite(now: now.addingTimeInterval(86_400), busy: false, composing: false))
    }
    @Test("暂缓一天，不因切换角色或重新进入而再次打扰")
    func deferAndClockRollback() {
        var state = LearningChatPresentation()
        state.deferToday(now: now)
        #expect(!state.canInvite(now: now.addingTimeInterval(86_399), busy: false, composing: false))
        #expect(state.canInvite(now: now.addingTimeInterval(86_400), busy: false, composing: false))
        state.markInvitation(now: now)
        #expect(!state.canInvite(now: now.addingTimeInterval(-1), busy: false, composing: false))
    }
    @Test("接受的情境进入正常聊天提示，不让角色充当评分器")
    func prompt() throws {
        let task = try #require(LearningTask.bank.first)
        let instruction = LearningChatPresentation.instruction(for: task)
        #expect(instruction.contains(task.instruction))
        #expect(instruction.contains("don't repeat questions already answered"))
        #expect(instruction.contains("Do not announce scores"))
        #expect(instruction.contains("follow them without pressure"))
    }
}

@Suite("学习记录跨设备合并")
struct LearningLedgerMergeTests {
    @Test("重复同步不加经验，同日跨设备奖励仍封顶，删除不复活")
    func merge() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        var a = LearningSystemPolicy.Ledger(), b = LearningSystemPolicy.Ledger()
        let batch = UUID()
        let evidence = LearningSystemPolicy.Evidence(batchID: batch, characterID: UUID(), date: date,
            skill: .preference, band: 1, topic: "food", scores: [2, 2, 2, 2],
            quote: "I choose tea because it keeps me warm.", explanation: "说清选择和理由", independent: true)
        let recorded = a.record([evidence], batchID: batch, now: date)
        #expect(recorded)
        b = a
        a.award(key: "a1", now: date); a.award(key: "a2", now: date)
        b.award(key: "b1", now: date); b.award(key: "b2", now: date)
        b.delete(evidence.id)
        try a.merge(b)
        #expect(a.xp == LearningSystemPolicy.dailyXP)
        #expect(a.evidence.count == 1)
        #expect(a.evidence.first?.deleted == true)
        let merged = a
        try a.merge(b)
        #expect(a == merged)
        try b.merge(merged)
        #expect(b.evidence == a.evidence)
        #expect(b.xp == a.xp)
        #expect(b.rewards == a.rewards)
        let duplicate = a.record([evidence], batchID: batch, now: date)
        #expect(!duplicate)
    }
}
