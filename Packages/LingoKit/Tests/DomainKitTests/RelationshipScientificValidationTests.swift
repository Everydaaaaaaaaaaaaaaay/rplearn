import Foundation
import LLMKit
import PersistenceKit
import SwiftData
import Testing
@testable import DomainKit

@Suite("RelationshipEngine 第三代科学性验证")
struct RelationshipScientificValidationTests {
    private let now = Date(timeIntervalSince1970: 2_140_000_000)

    @Test("披露被理解和承接时比单方面倾诉沉淀更多关系")
    func responsiveDisclosureConsolidatesMoreThanDisclosureAlone() {
        let disclosureOnly = signal(
            warmth: 0.2, responsiveness: 0.05, respect: 0.7, empathy: 0.05,
            reciprocity: 0.1, disclosure: 0.9, resonance: 0, engagement: 0.7,
            significance: 0.8, reason: "分享很多但没有承接对方"
        )
        let responsiveDisclosure = signal(
            warmth: 0.75, responsiveness: 0.92, respect: 0.9, empathy: 0.82,
            reciprocity: 0.82, disclosure: 0.9, resonance: 0.45, engagement: 0.9,
            significance: 0.8, reason: "理解并承接了彼此的分享"
        )

        let alone = apply(disclosureOnly, to: .initial, index: 0, at: now)
        let together = apply(responsiveDisclosure, to: .initial, index: 0, at: now)

        #expect(together.affinity > alone.affinity)
        #expect(together.bondFloor - RelationshipSnapshot.initial.bondFloor
            > alone.bondFloor - RelationshipSnapshot.initial.bondFloor)
        #expect(together.trust > alone.trust)
        #expect(together.familiarity > alone.familiarity)
    }

    @Test("积极消息的主动建设性回应优于被动敷衍")
    func activeConstructiveResponseOutperformsPassiveResponse() {
        let passive = signal(
            warmth: 0.35, responsiveness: 0.25, respect: 0.9, empathy: 0.15,
            reciprocity: 0.15, disclosure: 0.05, resonance: 0, engagement: 0.25,
            significance: 0.55, reason: "礼貌但被动地回应好消息"
        )
        let active = signal(
            warmth: 0.75, responsiveness: 0.9, respect: 0.9, empathy: 0.62,
            reciprocity: 0.72, disclosure: 0.05, resonance: 0.9, engagement: 0.92,
            significance: 0.55, reason: "主动建设性地回应好消息"
        )

        let passiveResult = apply(passive, to: .initial, index: 0, at: now)
        let activeResult = apply(active, to: .initial, index: 0, at: now)

        #expect(activeResult.affinity > passiveResult.affinity)
        #expect(activeResult.rapport > passiveResult.rapport)
        #expect(activeResult.bondFloor > passiveResult.bondFloor)
    }

    @Test("空洞消息和离线兜底都不能刷新有效联系时钟")
    func emptyAndUnknownContactsDoNotRefreshSubstantiveAnchor() {
        let oldContact = now.addingTimeInterval(-90 * 86_400)
        let baseline = RelationshipSnapshot(
            affinity: 96,
            bondFloor: 42,
            familiarity: 0.72,
            lastSubstantiveInteractionAt: oldContact,
            lastInteractionAt: oldContact
        )
        let empty = signal(
            warmth: 0, responsiveness: 0, respect: 0, empathy: 0,
            reciprocity: 0, disclosure: 0, resonance: 0, engagement: 0,
            significance: 0, confidence: 0, reason: "无法判断"
        )

        let reviewed = apply(empty, to: baseline, index: 0, at: now)
        let fallback = RelationshipEngine.recordContact(
            in: baseline,
            messageID: UUID(),
            messageCreatedAt: now,
            messageOrderIndex: 0,
            at: now
        )

        #expect(reviewed.lastInteractionAt == now)
        #expect(reviewed.lastSubstantiveInteractionAt == oldContact)
        #expect(fallback.lastInteractionAt == now)
        #expect(fallback.lastSubstantiveInteractionAt == oldContact)
        #expect(reviewed.projectedAffinity(at: now.addingTimeInterval(30 * 86_400)) < reviewed.affinity)
        #expect(fallback.projectedAffinity(at: now.addingTimeInterval(30 * 86_400)) < fallback.affinity)
    }

    @Test("轻量但真实的寒暄可以维护联系而不制造大幅加分")
    func lightweightContactMaintainsWithoutInflating() {
        let oldContact = now.addingTimeInterval(-60 * 86_400)
        let baseline = RelationshipSnapshot(
            affinity: 72,
            bondFloor: 34,
            familiarity: 0.55,
            lastSubstantiveInteractionAt: oldContact,
            lastInteractionAt: oldContact
        )
        let greeting = signal(
            warmth: 0.25, responsiveness: 0.4, respect: 0.65, empathy: 0.05,
            reciprocity: 0.25, disclosure: 0, resonance: 0.05, engagement: 0.35,
            significance: 0.12, reason: "简短但合乎语境的问候"
        )

        let result = apply(greeting, to: baseline, index: 0, at: now)

        #expect(result.lastSubstantiveInteractionAt == now)
        #expect(result.affinity - baseline.projectedAffinity(at: now) < 1)
        #expect(result.affinity >= baseline.projectedAffinity(at: now))
    }

    @Test("一致的正向互动逐渐建立稳定性，突然反转会降低它")
    func consistencyIsLearnedGraduallyAndRespondsToSurprise() throws {
        var stable = RelationshipSnapshot.initial
        for day in 0..<18 {
            stable = apply(Self.supportive, to: stable, index: day, at: now.addingTimeInterval(Double(day) * 86_400))
        }
        let beforeReversal = try #require(stable.interactionStability)
        var reversed = stable
        for day in 18..<23 {
            reversed = apply(Self.contempt, to: reversed, index: day, at: now.addingTimeInterval(Double(day) * 86_400))
        }
        let reversedStability = try #require(reversed.interactionStability)
        let reversedExpectation = try #require(reversed.expectedSocialQuality)
        let stableExpectation = try #require(stable.expectedSocialQuality)

        #expect(beforeReversal > 0.7)
        #expect(reversedStability < beforeReversal)
        #expect(reversedExpectation < stableExpectation)
    }

    @Test("互动稳定性只温和调节信任增长，不改变同一证据的方向")
    func stabilityModestlyModulatesTrustGrowth() {
        let lowStability = RelationshipSnapshot(
            affinity: 48, bondFloor: 22, familiarity: 0.45, trust: 0.2,
            rapport: 0.45, care: 0.4, respect: 0.65,
            expectedSocialQuality: 0.65, interactionStability: 0.1,
            lastInteractionAt: now.addingTimeInterval(-60)
        )
        var highStability = lowStability
        highStability.interactionStability = 0.9

        let low = apply(Self.supportive, to: lowStability, index: 0, at: now)
        let high = apply(Self.supportive, to: highStability, index: 0, at: now)
        let lowGain = low.trust - lowStability.trust
        let highGain = high.trust - highStability.trust

        #expect(lowGain > 0)
        #expect(highGain > lowGain)
        #expect(highGain < lowGain * 1.5)
    }

    @Test("稳定的敌意不会被误当成促进信任的可靠历史")
    func consistentlyNegativeHistoryDoesNotAccelerateTrustRepair() {
        let neutralHistory = RelationshipSnapshot(
            affinity: 40, bondFloor: 20, familiarity: 0.45, trust: 0.2,
            rapport: 0.35, care: 0.35, respect: 0.55,
            expectedSocialQuality: 0, interactionStability: 0.5,
            lastInteractionAt: now.addingTimeInterval(-60)
        )
        var consistentlyHostileHistory = neutralHistory
        consistentlyHostileHistory.expectedSocialQuality = -0.75
        consistentlyHostileHistory.interactionStability = 0.95

        let neutral = apply(Self.supportive, to: neutralHistory, index: 0, at: now)
        let hostile = apply(Self.supportive, to: consistentlyHostileHistory, index: 0, at: now)

        #expect(hostile.trust - consistentlyHostileHistory.trust
            <= neutral.trust - neutralHistory.trust + 0.000_001)
        #expect(hostile.trust > consistentlyHostileHistory.trust)
    }

    @Test("承担影响的修复比只标记为道歉更有效")
    func accountableRepairOutperformsHollowApology() {
        let strained = RelationshipSnapshot(
            affinity: 43, bondFloor: 25, familiarity: 0.62, trust: 0.38,
            rapport: 0.4, care: 0.42, respect: 0.45, unresolvedStrain: 0.82,
            lastInteractionAt: now.addingTimeInterval(-60)
        )
        let hollow = signal(
            warmth: 0.05, responsiveness: 0, respect: -0.1, empathy: 0,
            reciprocity: 0, disclosure: 0, resonance: 0, engagement: 0.2,
            repair: 1, significance: 0.8, reason: "只说了抱歉但没有回应影响"
        )
        let accountable = signal(
            warmth: 0.65, responsiveness: 0.95, respect: 0.98, empathy: 0.95,
            reciprocity: 0.78, disclosure: 0.5, resonance: 0.2, engagement: 0.9,
            repair: 1, significance: 0.8, reason: "承认影响并提出实际修复"
        )

        let hollowResult = apply(hollow, to: strained, index: 0, at: now)
        let accountableResult = apply(accountable, to: strained, index: 0, at: now)

        #expect(accountableResult.affinity - strained.affinity > hollowResult.affinity - strained.affinity)
        #expect(accountableResult.unresolvedStrain < hollowResult.unresolvedStrain)
    }

    @Test("未解决张力使后续同类伤害更严重但仍受单次上限约束")
    func unresolvedStrainAmplifiesRepeatedHarmWithinBounds() {
        let calm = RelationshipSnapshot(
            affinity: 84, bondFloor: 42, familiarity: 0.7, trust: 0.72,
            rapport: 0.68, care: 0.64, respect: 0.76, unresolvedStrain: 0,
            lastInteractionAt: now.addingTimeInterval(-60)
        )
        var strained = calm
        strained.unresolvedStrain = 0.8

        let calmResult = apply(Self.contempt, to: calm, index: 0, at: now)
        let strainedResult = apply(Self.contempt, to: strained, index: 0, at: now)
        let calmDamage = calm.affinity - calmResult.affinity
        let strainedDamage = strained.affinity - strainedResult.affinity

        #expect(strainedDamage > calmDamage)
        #expect(strainedDamage <= 18)
        #expect(strainedResult.unresolvedStrain >= strained.unresolvedStrain)
    }

    @Test("旧快照首次离线联系时保留原有衰减锚点")
    func legacySnapshotPreservesDecayAnchorDuringFallback() throws {
        let oldContact = now.addingTimeInterval(-45 * 86_400)
        let legacy = RelationshipSnapshot(schemaVersion: 1, affinity: 68, bondFloor: 30, lastInteractionAt: oldContact)
        let encoded = legacy.encodedJSON()
        let data = try #require(encoded.data(using: .utf8))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "lastSubstantiveInteractionAt")
        object.removeValue(forKey: "expectedSocialQuality")
        object.removeValue(forKey: "interactionStability")
        let migrated = try #require(RelationshipSnapshot.decode(fromJSON: String(
            decoding: JSONSerialization.data(withJSONObject: object),
            as: UTF8.self
        )))

        let updated = RelationshipEngine.recordContact(
            in: migrated,
            messageID: UUID(),
            messageCreatedAt: now,
            messageOrderIndex: 0,
            at: now
        )

        #expect(updated.lastSubstantiveInteractionAt == oldContact)
        #expect(updated.expectedSocialQuality == nil)
        #expect(updated.interactionStability == nil)
    }

    @Test("有效联系锚点按消息语义时间只前进不倒退")
    func substantiveAnchorDoesNotRegressOnOutOfOrderCompletion() {
        let newerAt = now.addingTimeInterval(60)
        let newer = RelationshipEngine.apply(
            Self.supportive,
            to: .initial,
            source: .textChat,
            messageID: UUID(),
            messageCreatedAt: newerAt,
            messageOrderIndex: 2,
            at: newerAt
        )
        let older = RelationshipEngine.apply(
            Self.supportive,
            to: newer,
            source: .textChat,
            messageID: UUID(),
            messageCreatedAt: now,
            messageOrderIndex: 1,
            at: newerAt.addingTimeInterval(30)
        )

        #expect(newer.lastSubstantiveInteractionAt == newerAt)
        #expect(older.lastSubstantiveInteractionAt == newerAt)
    }

    @Test("社会信号提示明确防止文化表达和消息长度偏差")
    func evaluationPromptContainsCulturalAndProcessGuardrails() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let roster = RosterStore(modelContainer: container)
        let characterID = try await roster.addCharacter(card: Self.card, difficulty: .junior3, isFriend: true)
        let character = try #require(try await roster.character(id: characterID))
        let mock = MockLLMProvider(completeHandler: { request in
            let prompt = request.system ?? ""
            #expect(prompt.contains("never apply a nationality stereotype"))
            #expect(prompt.contains("Culturally plausible brevity"))
            #expect(prompt.contains("Disclosure alone is not intimacy"))
            #expect(prompt.contains("active, constructive response to positive news"))
            #expect(prompt.contains("the word “sorry” alone is insufficient"))
            return Self.neutralReviewJSON
        })

        _ = try await RelationshipService(llm: mock, rosterStore: roster).evaluate(
            character: character,
            history: [],
            userMessage: MessageDTO(
                id: UUID(), role: .user, kind: .text, text: "嗯，知道了，谢谢", orderIndex: 0, createdAt: now
            )
        )
    }

    @Test("三十次空洞接触不如三次高质量回应且不会伪造稳定性")
    func qualityCannotBeReplacedByQuantity() {
        var empty = RelationshipSnapshot.initial
        for index in 0..<30 {
            empty = apply(Self.zeroEvidence, to: empty, index: index, at: now.addingTimeInterval(Double(index) * 86_400))
        }
        var quality = RelationshipSnapshot.initial
        for index in 0..<3 {
            quality = apply(Self.supportive, to: quality, index: index, at: now.addingTimeInterval(Double(index) * 86_400))
        }

        #expect(quality.affinity > empty.affinity)
        #expect(quality.bondFloor > empty.bondFloor)
        #expect(quality.familiarity > empty.familiarity)
        #expect(empty.lastSubstantiveInteractionAt == nil)
        #expect(empty.interactionStability == nil)
    }

    private func apply(
        _ signal: RelationshipSignal,
        to snapshot: RelationshipSnapshot,
        index: Int,
        at date: Date
    ) -> RelationshipSnapshot {
        RelationshipEngine.apply(
            signal,
            to: snapshot,
            source: .textChat,
            messageID: UUID(),
            messageCreatedAt: date,
            messageOrderIndex: index,
            at: date
        )
    }

    private func signal(
        warmth: Double,
        responsiveness: Double,
        respect: Double,
        empathy: Double,
        reciprocity: Double,
        disclosure: Double,
        resonance: Double,
        engagement: Double,
        boundaryHarm: Double = 0,
        repair: Double = 0,
        significance: Double,
        confidence: Double = 0.95,
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

    private static let supportive = RelationshipSignal(
        warmth: 0.78, responsiveness: 0.92, respect: 0.94, empathy: 0.78,
        reciprocity: 0.76, disclosure: 0.55, resonance: 0.68, engagement: 0.9,
        boundaryHarm: 0, repair: 0, significance: 0.7, confidence: 0.95,
        reasonZh: "稳定且认真地回应"
    )

    private static let contempt = RelationshipSignal(
        warmth: -0.68, responsiveness: 0.08, respect: -0.75, empathy: 0,
        reciprocity: -0.55, disclosure: 0, resonance: -0.5, engagement: 0.45,
        boundaryHarm: 0, repair: 0, significance: 0.6, confidence: 0.95,
        reasonZh: "持续轻视并拒绝回应"
    )

    private static let zeroEvidence = RelationshipSignal(
        warmth: 0, responsiveness: 0, respect: 0, empathy: 0,
        reciprocity: 0, disclosure: 0, resonance: 0, engagement: 0,
        boundaryHarm: 0, repair: 0, significance: 0, confidence: 0,
        reasonZh: "无法判断"
    )

    private static let card = CharacterCard(
        name: "Cultural Prompt Tester",
        age: 27,
        gender: .other,
        nationality: "British",
        regionID: "london",
        occupation: "researcher",
        hobbies: ["walking"],
        appearance: "test avatar",
        personality: "warm and observant"
    )

    private static let neutralReviewJSON = """
    {"coach_review":{"has_issues":false,"issues":[]},"relationship":{"warmth":0,"responsiveness":0,"respect":0,"empathy":0,"reciprocity":0,"disclosure":0,"resonance":0,"engagement":0,"boundary_harm":0,"repair":0,"significance":0,"confidence":0,"reason_zh":"无法判断"}}
    """
}
