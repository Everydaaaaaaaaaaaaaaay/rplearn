import Foundation
import PersistenceKit
import Testing
@testable import DomainKit

@Suite("NPC 在线状态与注意力时序")
struct NPCAttentionPolicyTests {
    private let policy = NPCAttentionPolicy.standard
    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("四档首气泡延迟严格落在产品区间且阶段有序")
    func replyRangesAndStageOrdering() throws {
        let ranges: [(NPCAttentionLevel, ClosedRange<TimeInterval>)] = [
            (.focused, 3...7),
            (.online, 8...22),
            (.recentlyActive, 20...45),
            (.offline, 60...300),
        ]

        for (attention, range) in ranges {
            for index in 0..<128 {
                let id = try #require(UUID(
                    uuidString: String(format: "00000000-0000-0000-0000-%012X", index)
                ))
                let plan = policy.makeReplyPlan(
                    attention: attention,
                    userMessageID: id,
                    sentAt: referenceDate
                )
                let delay = plan.firstBubbleAt.timeIntervalSince(referenceDate)
                #expect(range.contains(delay))
                #expect(plan.noticedAt >= referenceDate)
                #expect(plan.noticedAt <= plan.typingStartsAt)
                #expect(plan.noticedAt <= plan.generationStartsAt)
                #expect(plan.generationStartsAt <= plan.typingStartsAt)
                #expect(plan.typingStartsAt < plan.firstBubbleAt)
            }
        }
    }

    @Test("七分钟内继续聊天保持专注，超时后退出专注档")
    func focusLeaseRenewsConversationAttention() {
        let character = character(rhythm: .daytime, focusMinutes: 7)
        let assistant = message(
            role: .assistant,
            order: 0,
            at: referenceDate
        )
        let focusedUser = message(
            role: .user,
            order: 1,
            at: referenceDate.addingTimeInterval(6 * 60)
        )
        let expiredUser = message(
            role: .user,
            order: 2,
            at: referenceDate.addingTimeInterval(8 * 60)
        )

        #expect(policy.replyPlan(
            for: character,
            userMessage: focusedUser,
            history: [assistant, focusedUser]
        ).attention == .focused)
        #expect(policy.replyPlan(
            for: character,
            userMessage: expiredUser,
            history: [assistant, expiredUser]
        ).attention != .focused)
    }

    @Test("回复计划跨重启重建仍完全一致")
    func planIsStableForPersistedMessageIdentity() {
        let id = UUID(uuidString: "4F4A0464-8C15-43D7-9DFB-30B98DF72673")!
        let first = policy.makeReplyPlan(
            attention: .recentlyActive,
            userMessageID: id,
            sentAt: referenceDate
        )
        let rebuilt = policy.makeReplyPlan(
            attention: .recentlyActive,
            userMessageID: id,
            sentAt: referenceDate
        )

        #expect(first == rebuilt)
    }

    @Test("夜间型角色深夜在线率显著高于普通角色")
    func nightOwlProbabilityReflectsPersona() {
        let daytimeAtMidnight = policy.onlineProbability(
            rhythm: .daytime,
            localHour: 0.5,
            isWeekend: false
        )
        let nightOwlAtMidnight = policy.onlineProbability(
            rhythm: .nightOwl,
            localHour: 0.5,
            isWeekend: false
        )
        let daytimeInAfternoon = policy.onlineProbability(
            rhythm: .daytime,
            localHour: 16,
            isWeekend: false
        )

        #expect(nightOwlAtMidnight >= daytimeAtMidnight * 10)
        #expect(daytimeInAfternoon > daytimeAtMidnight)
    }

    @Test("双方正在交谈时作息概率不能把角色变成离线")
    func activeConversationOverridesAmbientSchedule() {
        let character = character(rhythm: .daytime, focusMinutes: 7)
        let snapshot = policy.presence(
            for: character,
            at: referenceDate.addingTimeInterval(3 * 60),
            lastAssistantMessageAt: referenceDate,
            pendingReplyPlan: nil
        )

        #expect(snapshot.state == .online)
    }

    @Test("刚认识的角色在夜间也保留在线窗口，重建不延长")
    func encounterWelcomeWindow() {
        var npc = character(rhythm: .daytime, focusMinutes: 7)
        npc.metAt = referenceDate
        let date = referenceDate.addingTimeInterval(19 * 60)
        #expect(policy.presence(for: npc, at: date, lastAssistantMessageAt: nil,
                                pendingReplyPlan: nil).state == .online)
        let user = message(role: .user, order: 0, at: date)
        #expect(policy.replyPlan(for: npc, userMessage: user, history: [user]).attention == .focused)
        let later = referenceDate.addingTimeInterval(36 * 60)
        #expect(policy.presence(for: npc, at: later, lastAssistantMessageAt: nil,
            pendingReplyPlan: nil) == policy.scheduledPresence(for: npc, at: later))
    }

    @Test("作息边界不锁定整点整分且相同时间结果稳定")
    func irregularStablePresenceBoundaries() {
        let npc = character(rhythm: .daytime, focusMinutes: 7)
        var departures = Set<Date>()
        for minute in stride(from: 0, to: 48 * 60, by: 5) {
            let date = referenceDate.addingTimeInterval(Double(minute * 60))
            let value = policy.scheduledPresence(for: npc, at: date)
            #expect(value == policy.scheduledPresence(for: npc, at: date))
            if value.state != .online, let last = value.lastActiveAt {
                #expect(last <= date)
                departures.insert(last)
            }
        }
        #expect(departures.count > 5)
        #expect(departures.allSatisfy { $0.timeIntervalSince1970.truncatingRemainder(dividingBy: 60) != 0 })
    }

    private func character(
        rhythm: NPCActivityRhythm,
        focusMinutes: Int
    ) -> CharacterDTO {
        CharacterDTO(
            id: UUID(uuidString: "A2CC58C1-602B-41B5-8D99-90A18D732227")!,
            card: CharacterCard(
                name: "Avery",
                age: 27,
                gender: .other,
                nationality: "British",
                regionID: "london",
                occupation: "designer",
                hobbies: ["sketching"],
                appearance: "green jacket",
                personality: "thoughtful",
                activityProfile: NPCActivityProfile(
                    timeZoneIdentifier: "Europe/London",
                    rhythm: rhythm,
                    focusDurationMinutes: focusMinutes
                )
            ),
            difficultyLevel: .junior3,
            isMainCharacter: false,
            isFriend: true,
            metAt: referenceDate.addingTimeInterval(-86400)
        )
    }

    private func message(
        role: MessageRole,
        order: Int,
        at date: Date
    ) -> MessageDTO {
        MessageDTO(
            id: UUID(),
            role: role,
            kind: .text,
            text: role == .user ? "Are you there?" : "I'm here.",
            orderIndex: order,
            createdAt: date
        )
    }
}
