import Foundation
import LLMKit
import PersistenceKit
import SwiftData
import Testing
@testable import DomainKit

@Suite("RelationshipEngine 第六代科学性验证")
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

    @Test("披露本身只增加了解，不会在缺少承接时自动增加亲近度")
    func disclosureAloneDoesNotManufactureAffinity() {
        let sharedContext = signal(
            warmth: 0.3, responsiveness: 0, respect: 0.4, empathy: 0,
            reciprocity: 0, disclosure: 0, resonance: 0, engagement: 0.4,
            significance: 0.55, reason: "有基本礼貌但没有回应披露"
        )
        var disclosureOnly = sharedContext
        disclosureOnly.disclosure = 0.9

        let control = apply(sharedContext, to: .initial, index: 0, at: now)
        let disclosed = apply(disclosureOnly, to: .initial, index: 0, at: now)

        #expect(abs(disclosed.affinity - control.affinity) < 0.05)
        #expect(disclosed.familiarity > control.familiarity)
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

    @Test("置信度为零的正向误报不能凭空制造亲近或关系事件")
    func zeroConfidencePositiveInferenceCannotManufactureCloseness() {
        var uncertain = Self.supportive
        uncertain.confidence = 0
        uncertain.significance = 1
        uncertain.reasonZh = "模型无法确认的正向推断"

        let result = apply(uncertain, to: .initial, index: 0, at: now)

        #expect(result.affinity == RelationshipSnapshot.initial.affinity)
        #expect(result.bondFloor == RelationshipSnapshot.initial.bondFloor)
        #expect(dimensions(of: result) == dimensions(of: .initial))
        #expect(result.meaningfulInteractionCount == 0)
        #expect(result.lastSubstantiveInteractionAt == nil)
        #expect(result.recentEvents.isEmpty)
    }

    @Test("置信度为零的道歉误报不能恢复好感或张力")
    func zeroConfidenceRepairCannotRestoreRelationship() {
        let strained = RelationshipSnapshot(
            affinity: 46, bondFloor: 24, familiarity: 0.62, trust: 0.38,
            rapport: 0.4, care: 0.42, respect: 0.45, unresolvedStrain: 0.82,
            lastInteractionAt: now.addingTimeInterval(-60)
        )
        var uncertainRepair = signal(
            warmth: 0.72, responsiveness: 0.95, respect: 0.98, empathy: 0.95,
            reciprocity: 0.8, disclosure: 0.2, resonance: 0.2, engagement: 0.9,
            repair: 1, significance: 0.9, confidence: 0,
            reason: "模型无法确认的修复推断"
        )
        uncertainRepair.boundaryHarm = 0

        let result = apply(uncertainRepair, to: strained, index: 0, at: now)

        #expect(result.affinity == strained.affinity)
        #expect(result.unresolvedStrain == strained.unresolvedStrain)
        #expect(result.repairGainToday == 0)
        #expect(result.recentEvents.isEmpty)
    }

    @Test("置信度为零的普通冷淡不能被安全下限误判为真实伤害")
    func zeroConfidenceOrdinaryNegativityCannotDamageRelationship() {
        let ambiguousColdness = signal(
            warmth: -0.75, responsiveness: 0.05, respect: 0.15, empathy: 0,
            reciprocity: -0.55, disclosure: 0, resonance: -0.7, engagement: 0.1,
            significance: 0.75, confidence: 0,
            reason: "语境不足，无法确认是否冷淡"
        )

        let result = apply(ambiguousColdness, to: .initial, index: 0, at: now)

        #expect(result.affinity == RelationshipSnapshot.initial.affinity)
        #expect(result.bondFloor == RelationshipSnapshot.initial.bondFloor)
        #expect(dimensions(of: result) == dimensions(of: .initial))
        #expect(result.meaningfulInteractionCount == 0)
        #expect(result.lastSubstantiveInteractionAt == nil)
        #expect(result.recentEvents.isEmpty)
    }

    @Test("没有社会证据时高重要性标签不能制造关系叙事")
    func unsupportedSignificanceCannotManufactureNarrativeEvent() {
        let unsupported = signal(
            warmth: 0, responsiveness: 0, respect: 0, empathy: 0,
            reciprocity: 0, disclosure: 0, resonance: 0, engagement: 0,
            significance: 1, confidence: 1,
            reason: "模型声称重要但没有任何社会证据"
        )

        let result = apply(unsupported, to: .initial, index: 0, at: now)

        #expect(result.affinity == RelationshipSnapshot.initial.affinity)
        #expect(dimensions(of: result) == dimensions(of: .initial))
        #expect(result.lastSubstantiveInteractionAt == nil)
        #expect(result.meaningfulInteractionCount == 0)
        #expect(result.recentEvents.isEmpty)
    }

    @Test("一次道歉可以即时修复但长期纽带更依赖后续可靠行为")
    func apologyDoesNotConsolidateMoreDurableBondThanBehaviour() {
        let strained = RelationshipSnapshot(
            affinity: 52, bondFloor: 27, familiarity: 0.62, trust: 0.62,
            rapport: 0.5, care: 0.52, respect: 0.68, unresolvedStrain: 0.75,
            lastInteractionAt: now.addingTimeInterval(-60)
        )
        let safeBehaviour = signal(
            warmth: 0.7, responsiveness: 0.95, respect: 0.98, empathy: 0.95,
            reciprocity: 0.8, disclosure: 0.25, resonance: 0.2, engagement: 0.9,
            repair: 0, significance: 0.9, reason: "以可靠行动回应先前问题"
        )
        var accountableApology = safeBehaviour
        accountableApology.repair = 1
        accountableApology.reasonZh = "承认影响并承诺改变"

        let behaviourResult = apply(safeBehaviour, to: strained, index: 0, at: now)
        let apologyResult = apply(accountableApology, to: strained, index: 0, at: now)

        #expect(apologyResult.affinity > behaviourResult.affinity)
        #expect(apologyResult.unresolvedStrain < behaviourResult.unresolvedStrain)
        #expect(apologyResult.bondFloor - strained.bondFloor
            <= behaviourResult.bondFloor - strained.bondFloor)
    }

    @Test("不同但合宜的支持方式不应像冷暖反复一样被判为不稳定")
    func adaptiveSupportVariationIsNotHostileVolatility() throws {
        let listening = signal(
            warmth: 0.78, responsiveness: 0.92, respect: 0.98, empathy: 0.95,
            reciprocity: 0.58, disclosure: 0.05, resonance: 0.45, engagement: 0.85,
            significance: 0.65, reason: "倾听并尊重对方的处理方式"
        )
        let collaborativeHelp = signal(
            warmth: 0.52, responsiveness: 0.88, respect: 0.96, empathy: 0.62,
            reciprocity: 0.82, disclosure: 0.2, resonance: 0.72, engagement: 0.92,
            significance: 0.65, reason: "在征得同意后共同解决问题"
        )
        var adaptive = RelationshipSnapshot.initial
        var volatile = RelationshipSnapshot.initial

        for day in 0..<16 {
            let date = now.addingTimeInterval(Double(day) * 86_400)
            adaptive = apply(day.isMultiple(of: 2) ? listening : collaborativeHelp, to: adaptive, index: day, at: date)
            volatile = apply(day.isMultiple(of: 2) ? listening : Self.contempt, to: volatile, index: day, at: date)
        }

        let adaptiveStability = try #require(adaptive.interactionStability)
        let volatileStability = try #require(volatile.interactionStability)
        #expect(adaptiveStability > volatileStability)
        #expect(adaptive.affinity > volatile.affinity)
        #expect(adaptive.expectedSocialQuality ?? 0 > 0)
    }

    @Test("修复效果受既往可信度约束而不是只看道歉文本")
    func repairEffectDependsOnPostViolationTrust() {
        let lowTrust = RelationshipSnapshot(
            affinity: 48, bondFloor: 25, familiarity: 0.62, trust: 0.18,
            rapport: 0.45, care: 0.48, respect: 0.62, unresolvedStrain: 0.65,
            lastInteractionAt: now.addingTimeInterval(-60)
        )
        var highTrust = lowTrust
        highTrust.trust = 0.86
        let accountable = signal(
            warmth: 0.72, responsiveness: 0.95, respect: 0.98, empathy: 0.95,
            reciprocity: 0.8, disclosure: 0.25, resonance: 0.2, engagement: 0.9,
            repair: 1, significance: 0.9, reason: "承认影响并提出实际改变"
        )

        let lowResult = apply(accountable, to: lowTrust, index: 0, at: now)
        let highResult = apply(accountable, to: highTrust, index: 0, at: now)

        #expect((highResult.repairGainToday ?? 0) > (lowResult.repairGainToday ?? 0))
        #expect(highResult.unresolvedStrain < lowResult.unresolvedStrain)
    }

    @Test("严重未修复伤害下单次道歉的即时效果更克制")
    func severeStrainReducesImmediateApologyEffect() {
        let mild = RelationshipSnapshot(
            affinity: 48, bondFloor: 25, familiarity: 0.62, trust: 0.62,
            rapport: 0.45, care: 0.48, respect: 0.66, unresolvedStrain: 0.25,
            lastInteractionAt: now.addingTimeInterval(-60)
        )
        var severe = mild
        severe.unresolvedStrain = 0.9
        let accountable = signal(
            warmth: 0.72, responsiveness: 0.95, respect: 0.98, empathy: 0.95,
            reciprocity: 0.8, disclosure: 0.25, resonance: 0.2, engagement: 0.9,
            repair: 1, significance: 0.9, reason: "承认影响并提出实际改变"
        )

        let mildResult = apply(accountable, to: mild, index: 0, at: now)
        let severeResult = apply(accountable, to: severe, index: 0, at: now)

        #expect((mildResult.repairGainToday ?? 0) > (severeResult.repairGainToday ?? 0))
        #expect(severeResult.unresolvedStrain > mildResult.unresolvedStrain)
    }

    @Test("跨日重复伤害会使后续同样的道歉逐渐失去可信度")
    func repeatedViolationMakesLaterApologyLessEffective() throws {
        let violation = signal(
            warmth: -0.65, responsiveness: 0.05, respect: -0.8, empathy: 0,
            reciprocity: -0.5, disclosure: 0, resonance: -0.55, engagement: 0.6,
            boundaryHarm: 0.7, significance: 0.8, reason: "重复发生了明确越界"
        )
        let accountable = signal(
            warmth: 0.72, responsiveness: 0.95, respect: 0.98, empathy: 0.95,
            reciprocity: 0.8, disclosure: 0.25, resonance: 0.2, engagement: 0.9,
            repair: 1, significance: 0.9, reason: "再次承认影响并道歉"
        )
        var snapshot = RelationshipSnapshot(
            affinity: 84, bondFloor: 40, familiarity: 0.7, trust: 0.72,
            rapport: 0.68, care: 0.66, respect: 0.76,
            lastInteractionAt: now.addingTimeInterval(-86_400)
        )
        var repairCredits: [Double] = []

        for cycle in 0..<5 {
            snapshot = apply(
                violation,
                to: snapshot,
                index: cycle * 2,
                at: now.addingTimeInterval(Double(cycle * 2) * 86_400)
            )
            snapshot = apply(
                accountable,
                to: snapshot,
                index: cycle * 2 + 1,
                at: now.addingTimeInterval(Double(cycle * 2 + 1) * 86_400)
            )
            repairCredits.append(snapshot.repairGainToday ?? 0)
        }

        let first = try #require(repairCredits.first)
        let last = try #require(repairCredits.last)
        #expect(last < first * 0.85)
        #expect(snapshot.affinity < 84)
        #expect(snapshot.unresolvedStrain > 0.5)
    }

    @Test("温暖包装不能抵消清晰轻视")
    func charmCannotNeutralizeClearContempt() {
        let baseline = RelationshipSnapshot(
            affinity: 58, bondFloor: 28, familiarity: 0.55, trust: 0.48,
            rapport: 0.5, care: 0.5, respect: 0.62,
            lastInteractionAt: now.addingTimeInterval(-60)
        )
        let charmingContempt = signal(
            warmth: 1, responsiveness: 0.95, respect: -0.9, empathy: 0.9,
            reciprocity: 0.75, disclosure: 0, resonance: 0.8, engagement: 1,
            significance: 0.8, reason: "热情包装下仍有清晰轻视"
        )

        let result = apply(charmingContempt, to: baseline, index: 0, at: now)

        #expect(result.affinity < baseline.affinity)
        #expect(result.trust < baseline.trust)
        #expect(result.respect < baseline.respect)
    }

    @Test("同一天重复道歉不能清空裂痕")
    func repeatedSameDayApologyCannotEraseStrain() {
        var snapshot = RelationshipSnapshot(
            affinity: 44, bondFloor: 24, familiarity: 0.62, trust: 0.35,
            rapport: 0.4, care: 0.42, respect: 0.45, unresolvedStrain: 0.9,
            lastInteractionAt: now.addingTimeInterval(-60)
        )
        let accountable = signal(
            warmth: 0.75, responsiveness: 0.95, respect: 0.98, empathy: 0.95,
            reciprocity: 0.8, disclosure: 0.3, resonance: 0.2, engagement: 0.9,
            repair: 1, significance: 0.9, reason: "承认影响并提出实际改变"
        )

        for index in 0..<20 {
            snapshot = apply(
                accountable,
                to: snapshot,
                index: index,
                at: now.addingTimeInterval(Double(index * 60))
            )
        }

        #expect(snapshot.unresolvedStrain > 0.55)
        #expect((snapshot.repairGainToday ?? 0) <= 2.000_001)
    }

    @Test("可信道歉后的跨日安全行动会继续修复关系")
    func safeFollowThroughContinuesRepairAcrossDays() {
        let strained = RelationshipSnapshot(
            affinity: 48, bondFloor: 26, familiarity: 0.65, trust: 0.4,
            rapport: 0.44, care: 0.48, respect: 0.5, unresolvedStrain: 0.82,
            lastInteractionAt: now.addingTimeInterval(-60)
        )
        let accountable = signal(
            warmth: 0.7, responsiveness: 0.95, respect: 0.98, empathy: 0.95,
            reciprocity: 0.8, disclosure: 0.25, resonance: 0.2, engagement: 0.9,
            repair: 1, significance: 0.9, reason: "承认影响并提出实际改变"
        )
        let repaired = apply(accountable, to: strained, index: 0, at: now)
        var followedThrough = repaired
        for day in 1...5 {
            followedThrough = apply(
                Self.supportive,
                to: followedThrough,
                index: day,
                at: now.addingTimeInterval(Double(day) * 86_400)
            )
        }

        #expect(followedThrough.unresolvedStrain < repaired.unresolvedStrain * 0.85)
        #expect(followedThrough.affinity > repaired.affinity)
    }

    @Test("稳定关系按自身联系节律获得有限宽限")
    func establishedContactCadenceAdjustsDecayWithoutRemovingIt() {
        func learnedHistory(intervalDays: Int) -> RelationshipSnapshot {
            let interval = Double(intervalDays) * 86_400
            var snapshot = RelationshipSnapshot(
                affinity: 66, bondFloor: 30, familiarity: 0.55,
                lastSubstantiveInteractionAt: now.addingTimeInterval(-4 * interval),
                lastInteractionAt: now.addingTimeInterval(-4 * interval)
            )
            for index in 0..<4 {
                let date = now.addingTimeInterval(-Double(3 - index) * interval)
                snapshot = apply(Self.supportive, to: snapshot, index: index, at: date)
            }
            snapshot.affinity = 90
            snapshot.bondFloor = 38
            snapshot.familiarity = 0.55
            snapshot.lastSubstantiveInteractionAt = now
            snapshot.lastInteractionAt = now
            return snapshot
        }

        let daily = learnedHistory(intervalDays: 1)
        let fortnightly = learnedHistory(intervalDays: 14)
        let projectedDate = now.addingTimeInterval(18 * 86_400)

        #expect(fortnightly.projectedAffinity(at: projectedDate) > daily.projectedAffinity(at: projectedDate) + 0.5)
        #expect(fortnightly.projectedAffinity(at: now.addingTimeInterval(365 * 86_400)) < fortnightly.affinity)
    }

    @Test("单次长间隔和同一会话消息都不能伪造稳定联系节律")
    func cadenceRequiresRepeatedCrossSessionEvidence() throws {
        let oldContact = now.addingTimeInterval(-180 * 86_400)
        var oneLongGap = RelationshipSnapshot(
            affinity: 70, bondFloor: 32, familiarity: 0.55,
            lastSubstantiveInteractionAt: oldContact,
            lastInteractionAt: oldContact
        )
        oneLongGap = apply(Self.supportive, to: oneLongGap, index: 0, at: now)
        #expect(oneLongGap.substantiveIntervalSampleCount == 1)

        var withoutCadence = oneLongGap
        withoutCadence.typicalContactIntervalDays = nil
        withoutCadence.substantiveIntervalSampleCount = nil
        #expect(oneLongGap.projectedAffinity(at: now.addingTimeInterval(30 * 86_400))
            == withoutCadence.projectedAffinity(at: now.addingTimeInterval(30 * 86_400)))

        let nextMinute = apply(Self.supportive, to: oneLongGap, index: 1, at: now.addingTimeInterval(60))
        #expect(nextMinute.substantiveIntervalSampleCount == 1)

        let decoded = try #require(RelationshipSnapshot.decode(fromJSON: nextMinute.encodedJSON()))
        #expect(decoded.typicalContactIntervalDays == nextMinute.typicalContactIntervalDays)
        #expect(decoded.substantiveIntervalSampleCount == nextMinute.substantiveIntervalSampleCount)
    }

    @Test("成熟联系节律对单次异常长间隔缓慢响应并保持硬上限")
    func cadenceResistsSingleOutlierAndAdaptsGradually() throws {
        var snapshot = RelationshipSnapshot(
            affinity: 76, bondFloor: 36, familiarity: 0.64,
            lastSubstantiveInteractionAt: now.addingTimeInterval(-10 * 86_400),
            lastInteractionAt: now.addingTimeInterval(-10 * 86_400)
        )
        for day in -9...0 {
            snapshot = apply(
                Self.supportive,
                to: snapshot,
                index: day + 9,
                at: now.addingTimeInterval(Double(day) * 86_400)
            )
        }
        let dailyCadence = try #require(snapshot.typicalContactIntervalDays)
        let afterOutlier = apply(
            Self.supportive,
            to: snapshot,
            index: 10,
            at: now.addingTimeInterval(60 * 86_400)
        )
        let outlierCadence = try #require(afterOutlier.typicalContactIntervalDays)
        var adapted = afterOutlier
        for step in 1...6 {
            adapted = apply(
                Self.supportive,
                to: adapted,
                index: 10 + step,
                at: now.addingTimeInterval(Double(60 + 30 * step) * 86_400)
            )
        }
        let adaptedCadence = try #require(adapted.typicalContactIntervalDays)

        #expect(dailyCadence < 1.1)
        #expect(outlierCadence < 3)
        #expect(adaptedCadence > outlierCadence)
        #expect(adaptedCadence <= 45)
    }

    @Test("v2 无有效联系的快照不会在升级时把技术接触误作关系维护")
    func versionTwoSnapshotPreservesMissingSubstantiveAnchor() throws {
        let oldContact = now.addingTimeInterval(-45 * 86_400)
        let encoded = RelationshipSnapshot(
            schemaVersion: 2,
            affinity: 68,
            bondFloor: 30,
            lastInteractionAt: oldContact
        ).encodedJSON()
        let data = try #require(encoded.data(using: .utf8))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "lastSubstantiveInteractionAt")
        object.removeValue(forKey: "typicalContactIntervalDays")
        object.removeValue(forKey: "substantiveIntervalSampleCount")
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

        #expect(updated.lastSubstantiveInteractionAt == nil)
        #expect(updated.schemaVersion == RelationshipSnapshot.currentSchemaVersion)
    }

    @Test("礼貌但缺少回应的后续接触不会自动消除张力")
    func genericPleasantContactDoesNotCountAsFollowThrough() {
        let strained = RelationshipSnapshot(
            affinity: 54, bondFloor: 28, familiarity: 0.6,
            unresolvedStrain: 0.7, lastInteractionAt: now.addingTimeInterval(-60)
        )
        let pleasantButUnresponsive = signal(
            warmth: 0.65, responsiveness: 0.2, respect: 0.8, empathy: 0.1,
            reciprocity: 0.15, disclosure: 0, resonance: 0.2, engagement: 0.3,
            significance: 0.5, reason: "语气友好但没有回应先前问题"
        )

        let result = apply(pleasantButUnresponsive, to: strained, index: 0, at: now)

        #expect(result.unresolvedStrain == strained.unresolvedStrain)
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
            #expect(prompt.contains("不得套用国籍刻板印象"))
            #expect(prompt.contains("文化上合理的简短"))
            #expect(prompt.contains("自我披露本身不等于亲密"))
            #expect(prompt.contains("对好消息积极且有建设性的回应"))
            #expect(prompt.contains("仅说“sorry”不够"))
            #expect(prompt.contains("不要要求立即或完全对等的回报"))
            #expect(prompt.contains("匹配对方实际请求或表达的需要"))
            #expect(prompt.contains("未经请求地解决问题、施压、淡化感受或接管局面"))
            #expect(prompt.contains("尊重拒绝或询问想要什么支持"))
            #expect(prompt.contains("指令式指导可以有实际帮助"))
            #expect(prompt.contains("保留对方的自主和选择"))
            #expect(prompt.contains("不同意或拒绝建议仍可能支持自主性"))
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

    @Test("关系分数只能调节语气不能伪造共同记忆")
    func relationshipPromptForbidsInventedSharedHistory() {
        let prompt = RelationshipEngine.promptContext(.initial, at: now)

        #expect(prompt.contains("不得编造共同经历"))
        #expect(prompt.contains("具体个人事实必须有提供的对话或记忆证据"))
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

    private func dimensions(of snapshot: RelationshipSnapshot) -> [Double] {
        [snapshot.familiarity, snapshot.trust, snapshot.rapport, snapshot.care, snapshot.respect, snapshot.unresolvedStrain]
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
