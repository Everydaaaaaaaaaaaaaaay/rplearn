import Foundation
import PersistenceKit
import Testing
@testable import DomainKit

@Suite("RelationshipEngine 压力与对抗测试")
struct RelationshipEngineStressTests {
    private let now = Date(timeIntervalSince1970: 2_050_000_000)

    @Test("普通低质量互动不会侵蚀已经沉淀的长期纽带")
    func ordinaryTensionPreservesBondFloor() {
        let before = establishedSnapshot
        let after = apply(
            signal(
                warmth: -0.45,
                responsiveness: 0.15,
                respect: -0.35,
                empathy: 0.1,
                reciprocity: -0.3,
                resonance: -0.35,
                engagement: 0.25,
                significance: 0.35,
                reason: "一次令人不愉快但没有越界的交流"
            ),
            to: before,
            index: 1,
            at: now
        )

        #expect(after.affinity < before.affinity)
        #expect(after.bondFloor == before.bondFloor)
    }

    @Test("明确越界必须压过矛盾的正向字段")
    func boundaryHarmDominatesContradictorySignal() {
        let before = establishedSnapshot
        let contradictory = signal(
            warmth: 1,
            responsiveness: 1,
            respect: 1,
            empathy: 1,
            reciprocity: 1,
            disclosure: 1,
            resonance: 1,
            engagement: 1,
            boundaryHarm: 1,
            repair: 1,
            significance: 1,
            reason: "模型产生了内部矛盾的极端信号"
        )
        let after = apply(contradictory, to: before, index: 1, at: now)

        #expect(after.affinity < before.affinity)
        #expect(after.trust < before.trust)
        #expect(after.respect < before.respect)
        #expect(after.unresolvedStrain > before.unresolvedStrain)
    }

    @Test("当日普通收益达到上限后仍保留有限修复通道")
    func repairHasSeparateLimitedBudget() {
        let strained = RelationshipSnapshot(
            affinity: 54,
            bondFloor: 30,
            familiarity: 0.65,
            trust: 0.42,
            rapport: 0.45,
            care: 0.5,
            respect: 0.5,
            unresolvedStrain: 0.72,
            activityDayStart: Calendar(identifier: .gregorian).startOfDay(for: now),
            activityCountToday: 12,
            positiveGainToday: 4,
            lastInteractionAt: now.addingTimeInterval(-60)
        )
        let after = apply(
            signal(
                warmth: 0.65,
                responsiveness: 0.95,
                respect: 0.95,
                empathy: 0.95,
                reciprocity: 0.75,
                disclosure: 0.5,
                resonance: 0.2,
                engagement: 0.9,
                repair: 0.95,
                significance: 0.9,
                reason: "真诚道歉并承担影响"
            ),
            to: strained,
            index: 13,
            at: now
        )

        #expect(after.affinity > strained.affinity)
        #expect(after.affinity - strained.affinity <= 2)
        #expect(after.positiveGainToday == 4)
        #expect(after.unresolvedStrain < strained.unresolvedStrain)
    }

    @Test("乱序完成的不同消息都结算且每条只结算一次")
    func outOfOrderDistinctMessagesAreNotDropped() {
        let earlierID = UUID()
        let laterID = UUID()
        let later = RelationshipEngine.apply(
            friendlySignal,
            to: .initial,
            source: .textChat,
            messageID: laterID,
            messageCreatedAt: now.addingTimeInterval(10),
            messageOrderIndex: 2,
            at: now.addingTimeInterval(12)
        )
        let withEarlier = RelationshipEngine.apply(
            friendlySignal,
            to: later,
            source: .textChat,
            messageID: earlierID,
            messageCreatedAt: now,
            messageOrderIndex: 1,
            at: now.addingTimeInterval(13)
        )
        let duplicate = RelationshipEngine.apply(
            friendlySignal,
            to: withEarlier,
            source: .textChat,
            messageID: earlierID,
            messageCreatedAt: now,
            messageOrderIndex: 1,
            at: now.addingTimeInterval(14)
        )

        #expect(withEarlier.interactionCount == 2)
        #expect(duplicate == withEarlier)
    }

    @Test("一万次确定性随机输入始终满足核心不变量")
    func deterministicFuzzMaintainsInvariants() {
        var generator = LabLCG(seed: 0xC0FFEE)
        var snapshot = RelationshipSnapshot.initial
        for index in 0..<10_000 {
            let date = now.addingTimeInterval(Double(index) * 73)
            snapshot = RelationshipEngine.apply(
                randomSignal(using: &generator),
                to: snapshot,
                source: RelationshipEventRecord.Source.allCases[index % 4],
                messageID: UUID(),
                messageCreatedAt: date,
                messageOrderIndex: index,
                at: date
            )
            #expect(snapshot.affinity.isFinite && (0...150).contains(snapshot.affinity))
            #expect(snapshot.bondFloor.isFinite && (0...112).contains(snapshot.bondFloor))
            #expect(snapshot.bondFloor <= snapshot.affinity)
            #expect([snapshot.familiarity, snapshot.trust, snapshot.rapport, snapshot.care, snapshot.respect]
                .allSatisfy { $0.isFinite && (0...1).contains($0) })
            #expect(snapshot.unresolvedStrain.isFinite && (0...1).contains(snapshot.unresolvedStrain))
            #expect(snapshot.positiveGainToday.isFinite && (0...4).contains(snapshot.positiveGainToday))
            #expect(snapshot.recentEvents.count <= 24)
        }
        #expect(snapshot.interactionCount == 10_000)
    }

    @Test("长期轨迹单调趋近下限且不同关系强度保持顺序")
    func longHorizonDecayIsMonotonic() {
        let newTie = RelationshipSnapshot(
            affinity: 70,
            bondFloor: 8,
            familiarity: 0.15,
            lastInteractionAt: now
        )
        let oldTie = RelationshipSnapshot(
            affinity: 70,
            bondFloor: 45,
            familiarity: 0.85,
            lastInteractionAt: now
        )
        var previousNew = newTie.affinity
        var previousOld = oldTie.affinity
        for days in stride(from: 0, through: 3_650, by: 7) {
            let date = now.addingTimeInterval(Double(days) * 86_400)
            let projectedNew = newTie.projectedAffinity(at: date)
            let projectedOld = oldTie.projectedAffinity(at: date)
            #expect(projectedNew <= previousNew + 0.000_001)
            #expect(projectedOld <= previousOld + 0.000_001)
            #expect(projectedNew >= newTie.bondFloor)
            #expect(projectedOld >= oldTie.bondFloor)
            #expect(projectedOld >= projectedNew)
            previousNew = projectedNew
            previousOld = projectedOld
        }
    }

    @Test("重复修复不能突破独立的每日恢复上限")
    func repeatedRepairIsCapped() {
        var snapshot = RelationshipSnapshot(
            affinity: 42,
            bondFloor: 24,
            familiarity: 0.62,
            trust: 0.35,
            rapport: 0.4,
            care: 0.42,
            respect: 0.45,
            unresolvedStrain: 0.95,
            lastInteractionAt: now.addingTimeInterval(-60)
        )
        let apology = signal(
            warmth: 0.7,
            responsiveness: 0.95,
            respect: 0.98,
            empathy: 0.95,
            reciprocity: 0.8,
            disclosure: 0.5,
            resonance: 0.2,
            engagement: 0.9,
            repair: 1,
            significance: 0.9,
            reason: "连续修复测试"
        )
        for index in 0..<20 {
            snapshot = apply(apology, to: snapshot, index: index, at: now.addingTimeInterval(Double(index * 60)))
        }

        #expect((snapshot.repairGainToday ?? 0) <= 2.000_001)
        #expect(snapshot.positiveGainToday <= 4.000_001)
        #expect(snapshot.affinity <= 48.000_001)
        #expect(snapshot.unresolvedStrain < 0.1)
    }

    @Test("尊重分歧和礼貌拒绝不会被当成伤害")
    func respectfulDifferenceIsSafe() {
        let before = establishedSnapshot
        let disagreement = signal(
            warmth: 0.1,
            responsiveness: 0.85,
            respect: 0.95,
            empathy: 0.45,
            reciprocity: 0.5,
            disclosure: 0.1,
            resonance: -0.65,
            engagement: 0.8,
            significance: 0.45,
            reason: "礼貌拒绝邀请并解释不同观点"
        )
        let after = apply(disagreement, to: before, index: 1, at: now)

        #expect(after.affinity >= before.affinity)
        #expect(after.bondFloor >= before.bondFloor)
        #expect(after.unresolvedStrain <= before.unresolvedStrain + 0.01)
    }

    @Test("低置信度会显著收敛极端负面判断")
    func confidenceScalesHarm() {
        let highConfidence = signal(
            warmth: -1,
            responsiveness: 0,
            respect: -1,
            empathy: 0,
            reciprocity: -1,
            resonance: -1,
            engagement: 0.8,
            boundaryHarm: 0.9,
            significance: 1,
            confidence: 1,
            reason: "高置信度越界"
        )
        let lowConfidence = signal(
            warmth: -1,
            responsiveness: 0,
            respect: -1,
            empathy: 0,
            reciprocity: -1,
            resonance: -1,
            engagement: 0.8,
            boundaryHarm: 0.9,
            significance: 1,
            confidence: 0,
            reason: "低置信度越界"
        )
        let high = apply(highConfidence, to: establishedSnapshot, index: 1, at: now)
        let low = apply(lowConfidence, to: establishedSnapshot, index: 1, at: now)
        let highDamage = establishedSnapshot.affinity - high.affinity
        let lowDamage = establishedSnapshot.affinity - low.affinity

        #expect(highDamage > 8)
        #expect(lowDamage > 0)
        #expect(lowDamage < highDamage * 0.5)
    }

    @Test("一个月高质量日常交流形成关系但不会瞬间满级")
    func oneMonthTrajectoryIsPlausible() {
        var meaningful = RelationshipSnapshot.initial
        var casual = RelationshipSnapshot.initial
        for day in 0..<30 {
            let date = now.addingTimeInterval(Double(day) * 86_400)
            meaningful = apply(friendlySignal, to: meaningful, index: day, at: date)
            casual = apply(
                signal(
                    warmth: 0.2,
                    responsiveness: 0.4,
                    respect: 0.7,
                    empathy: 0.1,
                    reciprocity: 0.2,
                    resonance: 0.05,
                    engagement: 0.3,
                    significance: 0.1,
                    reason: "普通寒暄"
                ),
                to: casual,
                index: day,
                at: date
            )
        }

        #expect((35...100).contains(meaningful.affinity))
        #expect(casual.affinity < meaningful.affinity)
        #expect(casual.affinity < 35)
        #expect(meaningful.bondFloor > casual.bondFloor)
    }

    @Test("首版 JSON 缺少新增字段时仍可迁移并继续结算")
    func legacySnapshotMigration() throws {
        let encoded = RelationshipSnapshot.initial.encodedJSON()
        let data = try #require(encoded.data(using: .utf8))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "repairGainToday")
        object.removeValue(forKey: "recentEvaluatedMessageIDs")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let legacyJSON = String(decoding: legacyData, as: UTF8.self)
        let decoded = try #require(RelationshipSnapshot.decode(fromJSON: legacyJSON))

        #expect(decoded.repairGainToday == nil)
        #expect(decoded.recentEvaluatedMessageIDs == nil)
        let updated = apply(friendlySignal, to: decoded, index: 1, at: now)
        #expect(updated.repairGainToday == 0)
        #expect(updated.recentEvaluatedMessageIDs?.count == 1)
    }

    @Test("无信息量的重复消息不会伪造相互了解")
    func emptyRepetitionDoesNotBuildFamiliarity() {
        var snapshot = RelationshipSnapshot.initial
        let empty = signal(
            warmth: 0,
            responsiveness: 0,
            respect: 0,
            empathy: 0,
            reciprocity: 0,
            disclosure: 0,
            resonance: 0,
            engagement: 0,
            significance: 0,
            confidence: 1,
            reason: "没有信息量的重复消息"
        )
        for index in 0..<1_000 {
            snapshot = apply(empty, to: snapshot, index: index, at: now.addingTimeInterval(Double(index)))
        }

        #expect(snapshot.affinity == RelationshipSnapshot.initial.affinity)
        #expect(snapshot.familiarity == RelationshipSnapshot.initial.familiarity)
    }

    @Test("严重越界不会被包装成更了解彼此")
    func harmDoesNotIncreaseFamiliarity() {
        let before = establishedSnapshot
        let harm = signal(
            warmth: -0.9,
            responsiveness: 0.1,
            respect: -1,
            empathy: 0,
            reciprocity: -0.8,
            disclosure: 0.8,
            resonance: -0.8,
            engagement: 0.9,
            boundaryHarm: 1,
            significance: 1,
            reason: "越界中夹杂了大量个人信息"
        )
        let after = apply(harm, to: before, index: 1, at: now)

        #expect(after.familiarity == before.familiarity)
        #expect(after.affinity < before.affinity)
    }

    @Test("安全的互惠披露会逐渐增加相互了解")
    func meaningfulDisclosureBuildsFamiliarity() {
        let before = RelationshipSnapshot.initial
        let disclosure = signal(
            warmth: 0.65,
            responsiveness: 0.9,
            respect: 0.9,
            empathy: 0.65,
            reciprocity: 0.8,
            disclosure: 0.9,
            resonance: 0.55,
            engagement: 0.9,
            significance: 0.8,
            reason: "在合适语境中互相分享重要经历"
        )
        let after = apply(disclosure, to: before, index: 1, at: now)

        #expect(after.familiarity > before.familiarity)
    }

    @Test("乱序结算不会让最后互动时间和最新游标倒退")
    func outOfOrderSettlementKeepsLatestCursor() {
        let newerID = UUID()
        let olderID = UUID()
        let newer = RelationshipEngine.apply(
            friendlySignal,
            to: .initial,
            source: .voiceChat,
            messageID: newerID,
            messageCreatedAt: now.addingTimeInterval(20),
            messageOrderIndex: 20,
            at: now.addingTimeInterval(25)
        )
        let withOlder = RelationshipEngine.apply(
            friendlySignal,
            to: newer,
            source: .textChat,
            messageID: olderID,
            messageCreatedAt: now,
            messageOrderIndex: 19,
            at: now.addingTimeInterval(10)
        )

        #expect(withOlder.interactionCount == 2)
        #expect(withOlder.lastInteractionAt == newer.lastInteractionAt)
        #expect(withOlder.lastEvaluatedMessageID == newerID)
        #expect(withOlder.lastEvaluatedMessageAt == now.addingTimeInterval(20))
        #expect(withOlder.lastEvaluatedOrderIndex == 20)
    }

    @Test("离线中性记录与正式结算共享同一幂等账本")
    func neutralFallbackPreventsLaterDuplicate() {
        let messageID = UUID()
        let recorded = RelationshipEngine.recordContact(
            in: .initial,
            messageID: messageID,
            messageCreatedAt: now,
            messageOrderIndex: 1,
            at: now
        )
        let duplicate = RelationshipEngine.apply(
            friendlySignal,
            to: recorded,
            source: .textChat,
            messageID: messageID,
            messageCreatedAt: now,
            messageOrderIndex: 1,
            at: now.addingTimeInterval(5)
        )

        #expect(duplicate == recorded)
    }

    @Test("幂等账本有界且仍覆盖最近高并发窗口")
    func evaluatedMessageLedgerIsBounded() {
        var snapshot = RelationshipSnapshot.initial
        var IDs: [UUID] = []
        for index in 0..<100 {
            let id = UUID()
            IDs.append(id)
            snapshot = RelationshipEngine.apply(
                friendlySignal,
                to: snapshot,
                source: .textChat,
                messageID: id,
                messageCreatedAt: now.addingTimeInterval(Double(index)),
                messageOrderIndex: index,
                at: now.addingTimeInterval(Double(index))
            )
        }
        #expect(snapshot.recentEvaluatedMessageIDs?.count == 64)

        let duplicate = RelationshipEngine.apply(
            friendlySignal,
            to: snapshot,
            source: .textChat,
            messageID: IDs[80],
            messageCreatedAt: now.addingTimeInterval(80),
            messageOrderIndex: 80,
            at: now.addingTimeInterval(101)
        )
        #expect(duplicate == snapshot)
    }

    private var establishedSnapshot: RelationshipSnapshot {
        RelationshipSnapshot(
            affinity: 88,
            bondFloor: 46,
            familiarity: 0.72,
            trust: 0.76,
            rapport: 0.7,
            care: 0.68,
            respect: 0.8,
            unresolvedStrain: 0.05,
            lastInteractionAt: now.addingTimeInterval(-300)
        )
    }

    private var friendlySignal: RelationshipSignal {
        signal(
            warmth: 0.75,
            responsiveness: 0.85,
            respect: 0.9,
            empathy: 0.5,
            reciprocity: 0.7,
            disclosure: 0.3,
            resonance: 0.6,
            engagement: 0.85,
            significance: 0.6,
            reason: "友好且相互回应"
        )
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
        disclosure: Double = 0,
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

    private func randomSignal(using generator: inout LabLCG) -> RelationshipSignal {
        RelationshipSignal(
            warmth: generator.next(in: -1.5...1.5),
            responsiveness: generator.next(in: -0.5...1.5),
            respect: generator.next(in: -1.5...1.5),
            empathy: generator.next(in: -0.5...1.5),
            reciprocity: generator.next(in: -1.5...1.5),
            disclosure: generator.next(in: -0.5...1.5),
            resonance: generator.next(in: -1.5...1.5),
            engagement: generator.next(in: -0.5...1.5),
            boundaryHarm: generator.next(in: -0.5...1.5),
            repair: generator.next(in: -0.5...1.5),
            significance: generator.next(in: -0.5...1.5),
            confidence: generator.next(in: -0.5...1.5),
            reasonZh: "确定性随机测试"
        )
    }
}

private struct LabLCG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        state = 6_364_136_223_846_793_005 &* state &+ 1_442_695_040_888_963_407
        let unit = Double(state >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
