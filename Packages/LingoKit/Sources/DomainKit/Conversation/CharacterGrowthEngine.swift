import Foundation
import PersistenceKit

/// 联合互动审阅只提出“成长候选”；确定性引擎负责证据门槛、幅度和阶段。
public struct CharacterGrowthSignal: Sendable, Codable, Equatable {
    public var trait: String
    public var direction: String
    public var relevance: Double
    public var agencyRespect: Double
    public var confidence: Double
    public var reasonZh: String

    public init(
        trait: String = "none",
        direction: String = "none",
        relevance: Double = 0,
        agencyRespect: Double = 0,
        confidence: Double = 0,
        reasonZh: String = ""
    ) {
        self.trait = trait
        self.direction = direction
        self.relevance = relevance
        self.agencyRespect = agencyRespect
        self.confidence = confidence
        self.reasonZh = reasonZh
    }
}

/// The joint model review can conservatively miss an explicit growth seed. This narrow resolver
/// recovers only high-signal, autonomy-respecting advice that directly follows the character's own admission.
public enum CharacterGrowthSeedPolicy {
    public static func resolve(
        modelSignal: CharacterGrowthSignal?,
        history: [MessageDTO],
        userMessage: MessageDTO
    ) -> CharacterGrowthSignal? {
        if let modelSignal,
           modelSignal.trait != "none",
           modelSignal.direction != "none",
           modelSignal.confidence >= 0.80,
           modelSignal.relevance >= 0.75,
           modelSignal.agencyRespect >= 0.70 {
            return modelSignal
        }

        let user = userMessage.text.lowercased()
        let respectsAgency = [
            "your choice", "up to you", "if you want", "you could", "maybe", "might help",
        ].contains(where: user.contains)
        let pauseAdvice = [
            "pause before", "pausing before", "think before", "thinking before", "slow down",
            "take a moment", "sleep on it",
        ].contains(where: user.contains)
        guard respectsAgency, pauseAdvice else { return modelSignal }

        let recentCharacterText = history
            .filter { $0.role == .assistant && $0.orderIndex < userMessage.orderIndex }
            .sorted { $0.orderIndex < $1.orderIndex }
            .suffix(4)
            .map(\.text)
            .joined(separator: " ")
            .lowercased()
        let admittedImpulsivity = [
            "act before thinking", "acted before thinking", "without thinking", "before i think",
            "before checking", "jumped ahead", "rush into", "impulsive",
        ].contains(where: recentCharacterText.contains)
        guard admittedImpulsivity else { return modelSignal }

        return CharacterGrowthSignal(
            trait: CharacterGrowthTrait.impulsivity.rawValue,
            direction: CharacterGrowthDirection.decrease.rawValue,
            relevance: 0.82,
            agencyRespect: 0.95,
            confidence: 0.84,
            reasonZh: "朋友在尊重选择的前提下建议先停顿再行动"
        )
    }
}

public enum CharacterGrowthEngine {
    private static let maximumArcs = 6
    private static let maximumEvidencePerArc = 24

    public static func apply(
        _ signal: CharacterGrowthSignal?,
        to snapshot: CharacterGrowthSnapshot,
        relationship: RelationshipSignal,
        evidenceMessageID: UUID,
        at date: Date = .now
    ) -> CharacterGrowthSnapshot {
        guard !snapshot.isPaused,
              let signal,
              signal.confidence >= 0.80,
              signal.relevance >= 0.75,
              signal.agencyRespect >= 0.70,
              relationship.boundaryHarm < 0.10,
              relationship.respect > 0.15,
              let trait = CharacterGrowthTrait(rawValue: signal.trait),
              let direction = CharacterGrowthDirection(rawValue: signal.direction)
        else { return snapshot }

        let alreadyEvaluated = snapshot.arcs.contains {
            $0.evidenceMessageIDs.contains(evidenceMessageID)
        }
        guard !alreadyEvaluated else { return snapshot }

        var next = snapshot
        next.schemaVersion = CharacterGrowthSnapshot.currentSchemaVersion
        let evidenceStrength = min(1, max(0, 0.55 * signal.relevance + 0.45 * signal.confidence))
        // 一次交流只会种下一点变化；形成稳定习惯至少需要多次跨情境证据。
        let increment = min(0.05, 0.015 + 0.035 * evidenceStrength)

        if let index = next.arcs.firstIndex(where: { $0.trait == trait }) {
            var arc = next.arcs[index]
            if arc.direction == direction {
                arc.progress = min(1, arc.progress + increment)
                arc.evidenceMessageIDs = Array((arc.evidenceMessageIDs + [evidenceMessageID]).suffix(maximumEvidencePerArc))
                arc.reasonZh = normalizedReason(signal.reasonZh, fallback: arc.reasonZh)
                arc.updatedAt = date
                arc.stage = stage(progress: arc.progress, evidenceCount: arc.evidenceMessageIDs.count)
                next.arcs[index] = arc
            } else {
                // 相反影响先削弱既有成长，不允许一条对话瞬间把方向翻转。
                // 反向证据同样写入幂等游标，否则后台重试会反复扣减进度。
                let progressBeforeOpposingEvidence = arc.progress
                arc.evidenceMessageIDs = Array((arc.evidenceMessageIDs + [evidenceMessageID]).suffix(maximumEvidencePerArc))
                arc.progress = max(0, progressBeforeOpposingEvidence - increment)
                arc.updatedAt = date
                if progressBeforeOpposingEvidence == 0 {
                    arc.direction = direction
                    arc.progress = increment
                    arc.reasonZh = normalizedReason(signal.reasonZh, fallback: arc.reasonZh)
                }
                arc.stage = stage(progress: arc.progress, evidenceCount: arc.evidenceMessageIDs.count)
                next.arcs[index] = arc
            }
        } else {
            let arc = CharacterGrowthArc(
                trait: trait,
                direction: direction,
                progress: increment,
                stage: .considering,
                reasonZh: normalizedReason(signal.reasonZh, fallback: "一次交流让他开始重新思考自己"),
                evidenceMessageIDs: [evidenceMessageID],
                createdAt: date,
                updatedAt: date
            )
            next.arcs.append(arc)
            next.arcs = Array(next.arcs.sorted { $0.updatedAt > $1.updatedAt }.prefix(maximumArcs))
        }
        next.revision += 1
        return next
    }

    /// 暂停只控制未来变化；已经形成的成长仍属于这段关系的一部分。
    public static func settingPaused(
        _ isPaused: Bool,
        in snapshot: CharacterGrowthSnapshot
    ) -> CharacterGrowthSnapshot {
        guard snapshot.isPaused != isPaused else { return snapshot }
        var next = snapshot
        next.schemaVersion = CharacterGrowthSnapshot.currentSchemaVersion
        next.isPaused = isPaused
        next.revision += 1
        return next
    }

    /// 撤销单项关系成长，不修改稳定人格，也不删除它来自的聊天或共同经历。
    public static func removingArc(
        id: UUID,
        from snapshot: CharacterGrowthSnapshot
    ) -> CharacterGrowthSnapshot {
        guard snapshot.arcs.contains(where: { $0.id == id }) else { return snapshot }
        var next = snapshot
        next.schemaVersion = CharacterGrowthSnapshot.currentSchemaVersion
        next.arcs.removeAll { $0.id == id }
        next.revision += 1
        return next
    }

    /// 清空已形成的关系成长；保留用户当前的暂停选择。
    public static func clearingGrowth(
        in snapshot: CharacterGrowthSnapshot
    ) -> CharacterGrowthSnapshot {
        guard !snapshot.arcs.isEmpty else { return snapshot }
        var next = snapshot
        next.schemaVersion = CharacterGrowthSnapshot.currentSchemaVersion
        next.arcs.removeAll()
        next.revision += 1
        return next
    }

    public static func promptContext(_ snapshot: CharacterGrowthSnapshot) -> String? {
        let active = snapshot.arcs
            .filter { $0.progress > 0 }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(4)
        guard !active.isEmpty else { return nil }
        let lines = active.map { arc in
            "- \(stageInstruction(for: arc)); 没有提供的记忆证据，不得声称已经成功或编造线下事件。"
        }.joined(separator: "\n")
        return """
        ## 私有的、仅属于这段关系的个人成长
        你的核心身份保持稳定。以下是这段友谊中缓慢出现的变化，不是替换人格：
        \(lines)
        只有话题自然相关时才提及成长。允许犹豫和偶尔退回旧习惯。
        """
    }

    private static func stage(progress: Double, evidenceCount: Int) -> CharacterGrowthStage {
        if progress >= 0.72, evidenceCount >= 12 { return .established }
        if progress >= 0.42, evidenceCount >= 8 { return .integrating }
        if progress >= 0.14, evidenceCount >= 3 { return .experimenting }
        return .considering
    }

    private static func stageInstruction(for arc: CharacterGrowthArc) -> String {
        let behavior = behaviorDescription(trait: arc.trait, direction: arc.direction)
        switch arc.stage {
        case .considering:
            return "你开始考虑是否要\(behavior)，但尚未改变"
        case .experimenting:
            return "你正谨慎尝试\(behavior)，有成有败"
        case .integrating:
            return "你越来越能记得\(behavior)，但压力下仍会出现旧习惯"
        case .established:
            return "你逐渐学会\(behavior)，同时保留原本可辨认的性情"
        }
    }

    private static func behaviorDescription(
        trait: CharacterGrowthTrait,
        direction: CharacterGrowthDirection
    ) -> String {
        switch (trait, direction) {
        case (.impulsivity, .decrease): "在重要决定前停一下"
        case (.impulsivity, .increase): "在风险低时更随性地行动"
        case (.patience, .increase): "给他人和困难任务更多时间"
        case (.patience, .decrease): "等待或犹豫令你烦躁时更早表达"
        case (.assertiveness, .increase): "更清楚地表达自己的需要和观点"
        case (.assertiveness, .decrease): "坚持自己立场前先留出更多空间"
        case (.openness, .increase): "否定陌生观点前先考虑"
        case (.openness, .decrease): "守住自己的信念而非自动同意"
        case (.selfConfidence, .increase): "更常相信自己深思后的判断"
        case (.selfConfidence, .decrease): "行动前检查那些自信的假设"
        case (.emotionalExpression, .increase): "更诚实地说出重要感受"
        case (.emotionalExpression, .decrease): "更谨慎地选择何时披露、披露多少"
        case (.flexibility, .increase): "出现新证据时调整计划"
        case (.flexibility, .decrease): "履行值得的承诺而不是太快改变方向"
        case (.responsibility, .increase): "贯彻行动并考虑选择对他人的影响"
        case (.responsibility, .decrease): "停止为身边所有事情承担责任"
        }
    }

    private static func normalizedReason(_ value: String, fallback: String) -> String {
        let normalized = value
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        return normalized.isEmpty ? fallback : String(normalized.prefix(80))
    }
}
