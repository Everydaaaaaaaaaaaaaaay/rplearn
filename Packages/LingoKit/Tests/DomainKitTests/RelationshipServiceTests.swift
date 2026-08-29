import Foundation
import LLMKit
import PersistenceKit
import SwiftData
import Testing
@testable import DomainKit

@Suite("RelationshipService")
struct RelationshipServiceTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("温暖、回应充分且有意义的互动会增加好感度和长期纽带")
    func positiveInteraction() {
        let before = RelationshipSnapshot.initial
        let after = RelationshipEngine.apply(
            signal(
                warmth: 0.85,
                responsiveness: 0.9,
                respect: 0.9,
                empathy: 0.7,
                reciprocity: 0.8,
                disclosure: 0.6,
                resonance: 0.75,
                engagement: 0.9,
                significance: 0.8,
                reason: "认真回应并分享了相似经历"
            ),
            to: before,
            source: .textChat,
            messageID: UUID(),
            messageOrderIndex: 1,
            at: now
        )

        #expect(after.affinity > before.affinity)
        #expect(after.bondFloor > before.bondFloor)
        #expect(after.familiarity > before.familiarity)
        #expect(after.interactionCount == 1)
        #expect(after.meaningfulInteractionCount == 1)
        #expect(after.latestEvent?.reasonZh.contains("相似经历") == true)
    }

    @Test("普通寒暄不被刷分，同日重复互动收益递减")
    func repetitionDamping() {
        var snapshot = RelationshipSnapshot.initial
        let friendly = signal(
            warmth: 0.55,
            responsiveness: 0.55,
            respect: 0.8,
            empathy: 0.2,
            reciprocity: 0.45,
            disclosure: 0.1,
            resonance: 0.3,
            engagement: 0.5,
            significance: 0.25,
            reason: "轻松地接住了话题"
        )
        var deltas: [Double] = []
        for index in 0..<6 {
            let before = snapshot.affinity
            snapshot = RelationshipEngine.apply(
                friendly,
                to: snapshot,
                source: .textChat,
                messageID: UUID(),
                messageOrderIndex: index,
                at: now.addingTimeInterval(Double(index * 300))
            )
            deltas.append(snapshot.affinity - before)
        }

        #expect(deltas[0] > deltas[5])
        #expect(deltas.reduce(0, +) < 4)
    }

    @Test("同一天无论重复多少次高质量互动，正向收益不超过每日上限")
    func dailyPositiveCap() {
        var snapshot = RelationshipSnapshot.initial
        let excellent = signal(
            warmth: 1,
            responsiveness: 1,
            respect: 1,
            empathy: 1,
            reciprocity: 1,
            disclosure: 1,
            resonance: 1,
            engagement: 1,
            significance: 1,
            reason: "高质量交流"
        )
        for index in 0..<30 {
            snapshot = RelationshipEngine.apply(
                excellent,
                to: snapshot,
                source: .textChat,
                messageID: UUID(),
                messageOrderIndex: index,
                at: now.addingTimeInterval(Double(index * 60))
            )
        }
        #expect(snapshot.affinity <= 14.000_001)
        #expect(snapshot.positiveGainToday <= 4)
        #expect(snapshot.interactionCount == 30)
    }

    @Test("明显不尊重和越界会降低信任、好感度并产生张力")
    func harmfulInteraction() {
        let before = RelationshipSnapshot(
            affinity: 78,
            bondFloor: 34,
            familiarity: 0.6,
            trust: 0.7,
            rapport: 0.65,
            care: 0.55,
            respect: 0.75,
            lastInteractionAt: now.addingTimeInterval(-86_400)
        )
        let after = RelationshipEngine.apply(
            signal(
                warmth: -0.8,
                responsiveness: 0.1,
                respect: -0.9,
                empathy: 0,
                reciprocity: -0.7,
                disclosure: 0,
                resonance: -0.5,
                engagement: 0.7,
                boundaryHarm: 0.85,
                significance: 0.9,
                reason: "无视边界并带有贬低"
            ),
            to: before,
            source: .voiceChat,
            messageID: UUID(),
            messageOrderIndex: 4,
            at: now
        )

        #expect(after.affinity < before.affinity - 5)
        #expect(after.bondFloor < before.bondFloor)
        #expect(after.trust < before.trust)
        #expect(after.unresolvedStrain > 0.2)
    }

    @Test("真诚修复能恢复一部分，但不会立刻抹去先前伤害")
    func repairIsPartial() {
        let strained = RelationshipSnapshot(
            affinity: 45,
            bondFloor: 25,
            familiarity: 0.6,
            trust: 0.42,
            rapport: 0.45,
            care: 0.5,
            respect: 0.5,
            unresolvedStrain: 0.75,
            lastInteractionAt: now.addingTimeInterval(-3_600),
            lastEvaluatedOrderIndex: 4
        )
        let repaired = RelationshipEngine.apply(
            signal(
                warmth: 0.7,
                responsiveness: 0.9,
                respect: 0.9,
                empathy: 0.8,
                reciprocity: 0.7,
                disclosure: 0.5,
                resonance: 0.3,
                engagement: 0.9,
                repair: 0.9,
                significance: 0.9,
                reason: "主动道歉并承担了影响"
            ),
            to: strained,
            source: .textChat,
            messageID: UUID(),
            messageOrderIndex: 5,
            at: now
        )

        #expect(repaired.affinity > strained.affinity)
        #expect(repaired.affinity - strained.affinity <= 5)
        #expect(repaired.unresolvedStrain < strained.unresolvedStrain)
        #expect(repaired.unresolvedStrain > 0)
    }

    @Test("长期不联系只让活跃亲近度向历史下限收敛")
    func decayHasDurableFloor() {
        let lastContact = now.addingTimeInterval(-30 * 86_400)
        let close = RelationshipSnapshot(
            affinity: 118,
            bondFloor: 72,
            familiarity: 0.82,
            trust: 0.8,
            rapport: 0.8,
            care: 0.75,
            respect: 0.85,
            lastInteractionAt: lastContact
        )
        let afterYear = close.projectedAffinity(at: lastContact.addingTimeInterval(365 * 86_400))
        let afterDecade = close.projectedAffinity(at: lastContact.addingTimeInterval(3_650 * 86_400))

        #expect(afterYear < close.affinity)
        #expect(afterYear > close.bondFloor)
        #expect(afterDecade >= close.bondFloor)
        #expect(afterDecade < afterYear)
    }

    @Test("乱序或重复点评不会再次结算")
    func staleReviewIsIgnored() {
        let evaluatedMessageID = UUID()
        let snapshot = RelationshipSnapshot(
            lastInteractionAt: now,
            lastEvaluatedMessageID: evaluatedMessageID,
            lastEvaluatedMessageAt: now,
            lastEvaluatedOrderIndex: 8,
            revision: 3
        )
        let unchanged = RelationshipEngine.apply(
            signal(significance: 1, reason: "重复结果"),
            to: snapshot,
            source: .textChat,
            messageID: evaluatedMessageID,
            messageCreatedAt: now,
            messageOrderIndex: 8,
            at: now.addingTimeInterval(1)
        )
        #expect(unchanged == snapshot)
    }

    @Test("新会话序号从零开始时仍可结算，同一消息不会重复")
    func messageTimeOrdersAcrossConversations() throws {
        let previousMessageAt = now.addingTimeInterval(-60)
        let snapshot = RelationshipSnapshot(
            lastInteractionAt: previousMessageAt,
            lastEvaluatedMessageID: UUID(),
            lastEvaluatedMessageAt: previousMessageAt,
            lastEvaluatedOrderIndex: 42,
            revision: 4
        )
        let newConversationResult = RelationshipEngine.apply(
            signal(warmth: 0.8, significance: 0.8, reason: "新会话中的自然交流"),
            to: snapshot,
            source: .textChat,
            messageID: UUID(),
            messageCreatedAt: now,
            messageOrderIndex: 0,
            at: now.addingTimeInterval(2)
        )
        #expect(newConversationResult.revision == 5)
        #expect(newConversationResult.lastEvaluatedOrderIndex == 0)

        let settledMessageID = try #require(newConversationResult.lastEvaluatedMessageID)
        let duplicate = RelationshipEngine.apply(
            signal(warmth: 1, significance: 1, reason: "旧会话迟到结果"),
            to: newConversationResult,
            source: .textChat,
            messageID: settledMessageID,
            messageCreatedAt: now,
            messageOrderIndex: 0,
            at: now.addingTimeInterval(3)
        )
        #expect(duplicate == newConversationResult)
    }

    @Test("模型不可用时只记录联系，不擅自增减好感度")
    func contactFallbackIsNeutral() {
        let before = RelationshipSnapshot(
            affinity: 52,
            bondFloor: 26,
            familiarity: 0.5,
            trust: 0.6,
            rapport: 0.55,
            care: 0.45,
            respect: 0.7,
            lastInteractionAt: now.addingTimeInterval(-2 * 86_400)
        )
        let after = RelationshipEngine.recordContact(
            in: before,
            messageID: UUID(),
            messageOrderIndex: 1,
            at: now
        )
        #expect(after.affinity == before.affinity)
        #expect(after.trust == before.trust)
        #expect(after.rapport == before.rapport)
        #expect(after.interactionCount == before.interactionCount + 1)
        #expect(after.lastInteractionAt == now)
        #expect(after.lastSubstantiveInteractionAt == before.lastInteractionAt)
    }

    @Test("联合审阅不评价英语水平，并原子写入关系状态")
    func reviewAndApply() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let roster = RosterStore(modelContainer: container)
        let characterID = try await roster.addCharacter(
            card: card,
            difficulty: .junior3,
            isFriend: true
        )
        let character = try #require(try await roster.character(id: characterID))
        let message = MessageDTO(
            id: UUID(),
            role: .user,
            kind: .text,
            text: "I very like that book, tell me more",
            orderIndex: 2
        )
        let mock = MockLLMProvider(completeHandler: { request in
            #expect(request.task == .coachReview)
            #expect(request.system?.contains("never English proficiency") == true)
            #expect(request.system?.contains("declining an invitation") == true)
            return """
            {"coach_review":{"has_issues":true,"issues":[{"quote":"very like","type":"grammar","correction":"really like","explanation_zh":"really 修饰动词"}]},"relationship":{"warmth":0.7,"responsiveness":0.9,"respect":0.9,"empathy":0.3,"reciprocity":0.6,"disclosure":0.2,"resonance":0.7,"engagement":0.9,"boundary_harm":0,"repair":0,"significance":0.6,"confidence":0.9,"reason_zh":"认真接住了共同兴趣"}}
            """
        })
        let review = try await RelationshipService(llm: mock, rosterStore: roster).reviewAndApply(
            character: character,
            history: [],
            userMessage: message,
            source: .textChat,
            at: now
        )

        #expect(review.hasIssues)
        #expect(try await roster.character(id: characterID)?.relationship.affinity ?? 0 > 10)
        #expect(try await roster.character(id: characterID)?.relationship.lastEvaluatedMessageID == message.id)
    }

    private var card: CharacterCard {
        CharacterCard(
            name: "Oliver Bennett",
            age: 24,
            gender: .male,
            nationality: "British",
            regionID: "london",
            occupation: "bookseller",
            hobbies: ["books", "football"],
            appearance: "brown hair",
            personality: "warm, witty and independent"
        )
    }

    private func signal(
        warmth: Double = 0.4,
        responsiveness: Double = 0.5,
        respect: Double = 0.7,
        empathy: Double = 0.2,
        reciprocity: Double = 0.4,
        disclosure: Double = 0.1,
        resonance: Double = 0.2,
        engagement: Double = 0.5,
        boundaryHarm: Double = 0,
        repair: Double = 0,
        significance: Double = 0.3,
        confidence: Double = 0.9,
        reason: String
    ) -> RelationshipSignal {
        RelationshipSignal(
            warmth: warmth,
            responsiveness: responsiveness,
            respect: respect,
            empathy: empathy,
            reciprocity: reciprocity,
            disclosure: disclosure,
            resonance: resonance,
            engagement: engagement,
            boundaryHarm: boundaryHarm,
            repair: repair,
            significance: significance,
            confidence: confidence,
            reasonZh: reason
        )
    }
}
