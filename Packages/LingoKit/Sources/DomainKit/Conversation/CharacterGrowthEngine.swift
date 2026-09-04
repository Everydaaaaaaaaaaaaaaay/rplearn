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
            "- \(stageInstruction(for: arc)); do not claim success or invent an off-screen event without supplied memory evidence."
        }.joined(separator: "\n")
        return """
        ## Private, relationship-specific personal growth
        Your core identity remains stable. These are slow changes emerging specifically through this friendship, not a replacement personality:
        \(lines)
        Mention this growth only when the topic naturally connects to it. Allow hesitation and occasional relapse.
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
            return "You have begun considering whether to \(behavior), but you have not changed yet"
        case .experimenting:
            return "You are cautiously trying to \(behavior), with mixed success"
        case .integrating:
            return "You increasingly remember to \(behavior), though old habits still appear under pressure"
        case .established:
            return "You have gradually learned to \(behavior), while keeping the recognizable temperament underneath"
        }
    }

    private static func behaviorDescription(
        trait: CharacterGrowthTrait,
        direction: CharacterGrowthDirection
    ) -> String {
        switch (trait, direction) {
        case (.impulsivity, .decrease): "pause before consequential decisions"
        case (.impulsivity, .increase): "act more spontaneously when the stakes are low"
        case (.patience, .increase): "give people and difficult tasks more time"
        case (.patience, .decrease): "state sooner when waiting or indecision is frustrating you"
        case (.assertiveness, .increase): "express your own needs and opinions more clearly"
        case (.assertiveness, .decrease): "leave more room before pressing your own position"
        case (.openness, .increase): "consider unfamiliar perspectives before dismissing them"
        case (.openness, .decrease): "protect your convictions instead of agreeing automatically"
        case (.selfConfidence, .increase): "trust your considered judgement more often"
        case (.selfConfidence, .decrease): "check confident assumptions before acting on them"
        case (.emotionalExpression, .increase): "name important feelings more honestly"
        case (.emotionalExpression, .decrease): "choose more carefully when and how much to disclose"
        case (.flexibility, .increase): "adapt plans when new evidence appears"
        case (.flexibility, .decrease): "keep worthwhile commitments instead of changing course too quickly"
        case (.responsibility, .increase): "follow through and consider how choices affect others"
        case (.responsibility, .decrease): "stop taking responsibility for everything around you"
        }
    }

    private static func normalizedReason(_ value: String, fallback: String) -> String {
        let normalized = value
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        return normalized.isEmpty ? fallback : String(normalized.prefix(80))
    }
}
