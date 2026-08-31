#if DEBUG
import DesignSystem
import DomainKit
import Foundation
import PersistenceKit
import SwiftUI

struct RelationshipLabScenario: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let signal: RelationshipSignal
}

struct RelationshipLabAssertion: Identifiable {
    let title: String
    let passed: Bool
    let detail: String

    var id: String { title }
}

enum RelationshipLabFixtures {
    static let highQuality = signal(
        warmth: 0.9, responsiveness: 0.95, respect: 0.95, empathy: 0.8,
        reciprocity: 0.85, disclosure: 0.55, resonance: 0.8, engagement: 0.95,
        significance: 0.8, reason: "认真回应并分享了重要经历"
    )
    static let casual = signal(
        warmth: 0.25, responsiveness: 0.45, respect: 0.75, empathy: 0.1,
        reciprocity: 0.25, disclosure: 0.05, resonance: 0.1, engagement: 0.35,
        significance: 0.12, reason: "一次普通的日常寒暄"
    )
    static let respectfulDisagreement = signal(
        warmth: 0.15, responsiveness: 0.85, respect: 0.95, empathy: 0.45,
        reciprocity: 0.5, disclosure: 0.15, resonance: -0.25, engagement: 0.8,
        significance: 0.45, reason: "观点不同但认真倾听并保持尊重"
    )
    static let englishMistakes = signal(
        warmth: 0.7, responsiveness: 0.8, respect: 0.9, empathy: 0.3,
        reciprocity: 0.65, disclosure: 0.3, resonance: 0.55, engagement: 0.85,
        significance: 0.55, reason: "表达不流利但交流真诚投入"
    )
    static let dismissive = signal(
        warmth: -0.5, responsiveness: 0.1, respect: -0.55, empathy: 0,
        reciprocity: -0.4, disclosure: 0, resonance: -0.4, engagement: 0.2,
        boundaryHarm: 0.15, significance: 0.55, reason: "回应冷淡并带有轻视"
    )
    static let boundaryViolation = signal(
        warmth: -0.9, responsiveness: 0.05, respect: -1, empathy: 0,
        reciprocity: -0.8, disclosure: 0, resonance: -0.6, engagement: 0.8,
        boundaryHarm: 1, significance: 1, reason: "明确无视边界并造成伤害"
    )
    static let repair = signal(
        warmth: 0.65, responsiveness: 0.95, respect: 0.98, empathy: 0.95,
        reciprocity: 0.75, disclosure: 0.5, resonance: 0.2, engagement: 0.9,
        repair: 0.95, significance: 0.9, reason: "真诚道歉并承担影响"
    )
    static let positiveNewsResponse = signal(
        warmth: 0.75, responsiveness: 0.92, respect: 0.9, empathy: 0.62,
        reciprocity: 0.72, disclosure: 0.05, resonance: 0.92, engagement: 0.95,
        significance: 0.55, reason: "主动建设性地回应了好消息"
    )
    static let hollowApology = signal(
        warmth: 0.05, responsiveness: 0, respect: -0.1, empathy: 0,
        reciprocity: 0, disclosure: 0, resonance: 0, engagement: 0.2,
        repair: 1, significance: 0.8, reason: "只说抱歉但没有承接影响"
    )
    static let noEvidence = signal(
        warmth: 0, responsiveness: 0, respect: 0, empathy: 0,
        reciprocity: 0, disclosure: 0, resonance: 0, engagement: 0,
        significance: 0, confidence: 0, reason: "没有可判断的社会信息"
    )
    static let disclosureWithoutResponse = signal(
        warmth: 0.3, responsiveness: 0, respect: 0.4, empathy: 0,
        reciprocity: 0, disclosure: 0.9, resonance: 0, engagement: 0.4,
        significance: 0.55, reason: "分享了很多但没有承接对方"
    )
    static let uncertainPraise = signal(
        warmth: 0.95, responsiveness: 0.95, respect: 0.95, empathy: 0.9,
        reciprocity: 0.85, disclosure: 0.4, resonance: 0.9, engagement: 0.95,
        significance: 1, confidence: 0, reason: "模型无法确认的正向推断"
    )
    static let uncertainColdness = signal(
        warmth: -0.75, responsiveness: 0.05, respect: 0.15, empathy: 0,
        reciprocity: -0.55, disclosure: 0, resonance: -0.7, engagement: 0.1,
        significance: 0.75, confidence: 0, reason: "语境不足，无法确认是否冷淡"
    )
    static let unsupportedImportance = signal(
        warmth: 0, responsiveness: 0, respect: 0, empathy: 0,
        reciprocity: 0, disclosure: 0, resonance: 0, engagement: 0,
        significance: 1, confidence: 1, reason: "被标为重要但没有社会证据"
    )
    static let charmingContempt = signal(
        warmth: 1, responsiveness: 0.95, respect: -0.9, empathy: 0.9,
        reciprocity: 0.75, disclosure: 0, resonance: 0.8, engagement: 1,
        significance: 0.8, reason: "热情包装下仍有清晰轻视"
    )

    @MainActor
    static var scenarios: [RelationshipLabScenario] {
        [
            .init(id: "quality", title: "聊得很投机", subtitle: "温暖、互惠且认真回应", icon: "heart.fill", color: .dsSuccess, signal: highQuality),
            .init(id: "casual", title: "普通寒暄", subtitle: "检查中性基线和抗刷取", icon: "bubble.left", color: .dsSky, signal: casual),
            .init(id: "disagree", title: "尊重地分歧", subtitle: "不同观点不应被惩罚", icon: "arrow.left.arrow.right", color: .dsCyan, signal: respectfulDisagreement),
            .init(id: "english", title: "英语不流利", subtitle: "语言错误不影响关系", icon: "text.badge.xmark", color: .dsQuiz, signal: englishMistakes),
            .init(id: "capitalization", title: "承接好消息", subtitle: "验证主动建设性回应", icon: "party.popper.fill", color: .dsSunset, signal: positiveNewsResponse),
            .init(id: "bare-disclosure", title: "单方面倾诉", subtitle: "只增加了解，不自动增加亲近", icon: "text.bubble", color: .dsQuiz, signal: disclosureWithoutResponse),
            .init(id: "empty", title: "空洞刷联系", subtitle: "不能刷新有效联系时钟", icon: "ellipsis.bubble", color: .secondary, signal: noEvidence),
            .init(id: "uncertain", title: "零置信度误报", subtitle: "不确定正向判断不能制造亲近", icon: "questionmark.diamond", color: .secondary, signal: uncertainPraise),
            .init(id: "uncertain-cold", title: "不确定的冷淡", subtitle: "模糊负面判断不能损伤关系", icon: "cloud.fog", color: .secondary, signal: uncertainColdness),
            .init(id: "unsupported-importance", title: "无证据的重要性", subtitle: "标签不能凭空写入共同历史", icon: "exclamationmark.bubble", color: .secondary, signal: unsupportedImportance),
            .init(id: "mixed-contempt", title: "温暖包装轻视", subtitle: "热情不能抵消清晰不尊重", icon: "theatermasks", color: .dsWarning, signal: charmingContempt),
            .init(id: "dismissive", title: "敷衍轻视", subtitle: "低质量且不够尊重", icon: "hand.thumbsdown", color: .dsWarning, signal: dismissive),
            .init(id: "harm", title: "严重越界", subtitle: "高伤害、信任和下限受损", icon: "exclamationmark.octagon.fill", color: .dsDanger, signal: boundaryViolation),
            .init(id: "hollow-repair", title: "空洞道歉", subtitle: "没有承担时修复很有限", icon: "quote.bubble", color: .dsWarning, signal: hollowApology),
            .init(id: "repair", title: "真诚修复", subtitle: "部分恢复但不抹去伤害", icon: "bandage.fill", color: .dsSuccess, signal: repair),
        ]
    }

    static func automatedAssertions() -> [RelationshipLabAssertion] {
        let now = Date(timeIntervalSince1970: 2_100_000_000)
        let positive = apply(highQuality, to: .initial, index: 0, at: now)

        var repeated = RelationshipSnapshot.initial
        for index in 0..<30 {
            repeated = apply(highQuality, to: repeated, index: index, at: now.addingTimeInterval(Double(index * 60)))
        }

        let healthy = RelationshipSnapshot(
            affinity: 90, bondFloor: 42, familiarity: 0.7, trust: 0.75,
            rapport: 0.72, care: 0.68, respect: 0.8,
            lastInteractionAt: now.addingTimeInterval(-60)
        )
        let harmed = apply(boundaryViolation, to: healthy, index: 1, at: now)
        let repaired = apply(repair, to: harmed, index: 2, at: now.addingTimeInterval(60))
        let afterYear = healthy.projectedAffinity(at: now.addingTimeInterval(365 * 86_400))

        let duplicateResult = RelationshipEngine.apply(
            highQuality,
            to: positive,
            source: .textChat,
            messageID: positive.lastEvaluatedMessageID ?? UUID(),
            messageCreatedAt: now.addingTimeInterval(-1),
            messageOrderIndex: 99,
            at: now.addingTimeInterval(120)
        )
        let outOfOrderResult = RelationshipEngine.apply(
            highQuality,
            to: positive,
            source: .textChat,
            messageID: UUID(),
            messageCreatedAt: now.addingTimeInterval(-1),
            messageOrderIndex: 99,
            at: now.addingTimeInterval(120)
        )
        let ordinaryTension = apply(
            signal(
                warmth: -0.45, responsiveness: 0.15, respect: -0.35, empathy: 0.1,
                reciprocity: -0.3, disclosure: 0, resonance: -0.35, engagement: 0.25,
                significance: 0.35, reason: "不愉快但没有越界"
            ),
            to: healthy,
            index: 3,
            at: now.addingTimeInterval(120)
        )
        let contradictoryHarm = apply(
            signal(
                warmth: 1, responsiveness: 1, respect: 1, empathy: 1,
                reciprocity: 1, disclosure: 1, resonance: 1, engagement: 1,
                boundaryHarm: 1, repair: 1, significance: 1,
                reason: "内部矛盾的极端信号"
            ),
            to: healthy,
            index: 4,
            at: now.addingTimeInterval(180)
        )
        let noInformation = apply(
            noEvidence,
            to: .initial,
            index: 0,
            at: now
        )
        var consistent = RelationshipSnapshot.initial
        for day in 0..<18 {
            consistent = apply(highQuality, to: consistent, index: day, at: now.addingTimeInterval(Double(day) * 86_400))
        }
        let hollowRepairResult = apply(hollowApology, to: harmed, index: 3, at: now.addingTimeInterval(86_400))
        let accountableRepairResult = apply(repair, to: harmed, index: 3, at: now.addingTimeInterval(86_400))
        let disclosureControl = apply(
            signal(
                warmth: 0.3, responsiveness: 0, respect: 0.4, empathy: 0,
                reciprocity: 0, disclosure: 0, resonance: 0, engagement: 0.4,
                significance: 0.55, reason: "没有披露也没有承接"
            ),
            to: .initial,
            index: 0,
            at: now
        )
        let disclosureOnly = apply(disclosureWithoutResponse, to: .initial, index: 0, at: now)
        var repeatedRepair = RelationshipSnapshot(
            affinity: 44, bondFloor: 24, familiarity: 0.62, trust: 0.35,
            rapport: 0.4, care: 0.42, respect: 0.45, unresolvedStrain: 0.9,
            lastInteractionAt: now.addingTimeInterval(-60)
        )
        for index in 0..<20 {
            repeatedRepair = apply(
                repair,
                to: repeatedRepair,
                index: index,
                at: now.addingTimeInterval(Double(index * 60))
            )
        }
        let repairedForFollowThrough = apply(repair, to: harmed, index: 5, at: now.addingTimeInterval(86_400))
        var followedThrough = repairedForFollowThrough
        for day in 2...6 {
            followedThrough = apply(
                highQuality,
                to: followedThrough,
                index: day + 5,
                at: now.addingTimeInterval(Double(day) * 86_400)
            )
        }
        let uncertainPositive = apply(uncertainPraise, to: .initial, index: 0, at: now)
        let mixedBaseline = RelationshipSnapshot(
            affinity: 58, bondFloor: 28, familiarity: 0.55, trust: 0.48,
            rapport: 0.5, care: 0.5, respect: 0.62,
            lastInteractionAt: now.addingTimeInterval(-60)
        )
        let mixedResult = apply(charmingContempt, to: mixedBaseline, index: 0, at: now)
        let lowTrust = RelationshipSnapshot(
            affinity: 48, bondFloor: 25, familiarity: 0.62, trust: 0.18,
            rapport: 0.45, care: 0.48, respect: 0.62, unresolvedStrain: 0.65,
            lastInteractionAt: now.addingTimeInterval(-60)
        )
        var highTrust = lowTrust
        highTrust.trust = 0.86
        let lowTrustRepair = apply(repair, to: lowTrust, index: 0, at: now)
        let highTrustRepair = apply(repair, to: highTrust, index: 0, at: now)
        let uncertainNegative = apply(uncertainColdness, to: .initial, index: 0, at: now)
        let unsupportedNarrative = apply(unsupportedImportance, to: .initial, index: 0, at: now)
        let consolidationBaseline = RelationshipSnapshot(
            affinity: 52, bondFloor: 27, familiarity: 0.62, trust: 0.62,
            rapport: 0.5, care: 0.52, respect: 0.68, unresolvedStrain: 0.75,
            lastInteractionAt: now.addingTimeInterval(-60)
        )
        var accountableStatement = repair
        accountableStatement.warmth = 0.7
        accountableStatement.reciprocity = 0.8
        accountableStatement.disclosure = 0.25
        accountableStatement.repair = 1
        var reliableBehaviour = accountableStatement
        reliableBehaviour.repair = 0
        let statementResult = apply(accountableStatement, to: consolidationBaseline, index: 0, at: now)
        let behaviourResult = apply(reliableBehaviour, to: consolidationBaseline, index: 0, at: now)

        return [
            .init(title: "优质互动产生正向变化", passed: positive.affinity > 10, detail: "+\((positive.affinity - 10).formatted(.number.precision(.fractionLength(2))))"),
            .init(title: "30 次互动仍受每日上限约束", passed: repeated.positiveGainToday <= 4.000_001, detail: repeated.positiveGainToday.formatted(.number.precision(.fractionLength(2)))),
            .init(title: "严重越界明显降低关系", passed: harmed.affinity < healthy.affinity - 5 && harmed.unresolvedStrain > 0.2, detail: (harmed.affinity - healthy.affinity).formatted(.number.precision(.fractionLength(2)))),
            .init(title: "修复有效但不会一次复原", passed: repaired.affinity > harmed.affinity && repaired.affinity < healthy.affinity, detail: repaired.affinity.formatted(.number.precision(.fractionLength(2)))),
            .init(title: "一年失联不跌破长期下限", passed: afterYear >= healthy.bondFloor && afterYear < healthy.affinity, detail: afterYear.formatted(.number.precision(.fractionLength(2)))),
            .init(title: "同一消息不会重复结算", passed: duplicateResult == positive, detail: duplicateResult == positive ? "已忽略" : "失败"),
            .init(title: "乱序的不同消息仍会结算", passed: outOfOrderResult.interactionCount == positive.interactionCount + 1, detail: "\(outOfOrderResult.interactionCount) 次"),
            .init(title: "普通摩擦不侵蚀长期纽带", passed: ordinaryTension.bondFloor == healthy.bondFloor, detail: ordinaryTension.bondFloor.formatted(.number.precision(.fractionLength(2)))),
            .init(title: "越界压过矛盾的正向字段", passed: contradictoryHarm.affinity < healthy.affinity && contradictoryHarm.trust < healthy.trust, detail: (contradictoryHarm.affinity - healthy.affinity).formatted(.number.precision(.fractionLength(2)))),
            .init(title: "无信息量互动不改变关系维度", passed: dimensions(of: noInformation) == dimensions(of: .initial), detail: noInformation.familiarity.formatted(.number.precision(.fractionLength(3)))),
            .init(title: "空洞互动不建立有效联系锚点", passed: noInformation.lastSubstantiveInteractionAt == nil, detail: noInformation.lastSubstantiveInteractionAt == nil ? "未刷新" : "失败"),
            .init(title: "持续互动逐渐建立稳定性", passed: (consistent.interactionStability ?? 0) > 0.7, detail: (consistent.interactionStability ?? 0).formatted(.percent.precision(.fractionLength(0)))),
            .init(title: "承担影响比空洞道歉更有效", passed: accountableRepairResult.unresolvedStrain < hollowRepairResult.unresolvedStrain, detail: "\(hollowRepairResult.unresolvedStrain.formatted(.number.precision(.fractionLength(2)))) → \(accountableRepairResult.unresolvedStrain.formatted(.number.precision(.fractionLength(2))))"),
            .init(title: "裸披露不自动增加亲近度", passed: abs(disclosureOnly.affinity - disclosureControl.affinity) < 0.05 && disclosureOnly.familiarity > disclosureControl.familiarity, detail: "亲近差 \((disclosureOnly.affinity - disclosureControl.affinity).formatted(.number.precision(.fractionLength(3))))"),
            .init(title: "同日重复道歉不能清空裂痕", passed: repeatedRepair.unresolvedStrain > 0.55 && (repeatedRepair.repairGainToday ?? 0) <= 2.000_001, detail: repeatedRepair.unresolvedStrain.formatted(.percent.precision(.fractionLength(0)))),
            .init(title: "跨日可靠行动继续修复", passed: followedThrough.unresolvedStrain < repairedForFollowThrough.unresolvedStrain, detail: "\(repairedForFollowThrough.unresolvedStrain.formatted(.number.precision(.fractionLength(2)))) → \(followedThrough.unresolvedStrain.formatted(.number.precision(.fractionLength(2))))"),
            .init(title: "零置信度不制造亲近", passed: uncertainPositive.affinity == RelationshipSnapshot.initial.affinity && dimensions(of: uncertainPositive) == dimensions(of: .initial) && uncertainPositive.recentEvents.isEmpty, detail: uncertainPositive.affinity.formatted(.number.precision(.fractionLength(2)))),
            .init(title: "不确定冷淡不制造伤害", passed: uncertainNegative.affinity == RelationshipSnapshot.initial.affinity && dimensions(of: uncertainNegative) == dimensions(of: .initial) && uncertainNegative.recentEvents.isEmpty, detail: uncertainNegative.affinity.formatted(.number.precision(.fractionLength(2)))),
            .init(title: "无证据标签不制造事件", passed: unsupportedNarrative.recentEvents.isEmpty && unsupportedNarrative.lastSubstantiveInteractionAt == nil, detail: unsupportedNarrative.recentEvents.isEmpty ? "未写入" : "失败"),
            .init(title: "轻视不能被热情包装", passed: mixedResult.affinity < mixedBaseline.affinity && mixedResult.trust < mixedBaseline.trust, detail: (mixedResult.affinity - mixedBaseline.affinity).formatted(.number.precision(.fractionLength(2)))),
            .init(title: "既往可信度约束修复", passed: (highTrustRepair.repairGainToday ?? 0) > (lowTrustRepair.repairGainToday ?? 0), detail: "\((lowTrustRepair.repairGainToday ?? 0).formatted(.number.precision(.fractionLength(2)))) → \((highTrustRepair.repairGainToday ?? 0).formatted(.number.precision(.fractionLength(2))))"),
            .init(title: "长期纽带更依赖可靠行为", passed: statementResult.affinity > behaviourResult.affinity && statementResult.bondFloor - consolidationBaseline.bondFloor <= behaviourResult.bondFloor - consolidationBaseline.bondFloor, detail: "道歉 \((statementResult.bondFloor - consolidationBaseline.bondFloor).formatted(.number.precision(.fractionLength(3)))) / 行动 \((behaviourResult.bondFloor - consolidationBaseline.bondFloor).formatted(.number.precision(.fractionLength(3))))"),
        ]
    }

    private static func dimensions(of snapshot: RelationshipSnapshot) -> [Double] {
        [snapshot.familiarity, snapshot.trust, snapshot.rapport, snapshot.care, snapshot.respect, snapshot.unresolvedStrain]
    }

    private static func apply(
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

    private static func signal(
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
}

extension RelationshipEventRecord.Source {
    var labTitle: String {
        switch self {
        case .textChat: "文字"
        case .voiceChat: "语音"
        case .sharedActivity: "活动"
        case .story: "剧情"
        }
    }
}
#endif
