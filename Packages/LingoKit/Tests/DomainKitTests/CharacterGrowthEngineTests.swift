import Foundation
import Testing
@testable import DomainKit
@testable import PersistenceKit

@Suite("CharacterGrowthEngine")
struct CharacterGrowthEngineTests {
    @Test("v1 成长快照升级时默认继续允许成长")
    func decodesLegacySnapshotWithoutPausedFlag() throws {
        let legacyJSON = #"{"arcs":[],"revision":7,"schemaVersion":1}"#
        let snapshot = try #require(CharacterGrowthSnapshot.decode(fromJSON: legacyJSON))
        #expect(snapshot.schemaVersion == 1)
        #expect(snapshot.revision == 7)
        #expect(!snapshot.isPaused)
    }

    @Test("低可信或越界互动不能改变人格")
    func rejectsWeakOrHarmfulSignals() {
        let id = UUID()
        var weak = strongSignal()
        weak.confidence = 0.79
        let unchanged = CharacterGrowthEngine.apply(
            weak,
            to: .initial,
            relationship: relationshipSignal(),
            evidenceMessageID: id
        )
        #expect(unchanged == .initial)

        var harmfulRelationship = relationshipSignal()
        harmfulRelationship.boundaryHarm = 0.8
        let alsoUnchanged = CharacterGrowthEngine.apply(
            strongSignal(),
            to: .initial,
            relationship: harmfulRelationship,
            evidenceMessageID: UUID()
        )
        #expect(alsoUnchanged == .initial)
    }

    @Test("单次建议只进入思考阶段，重复消息保持幂等")
    func oneMessageOnlySeedsChange() throws {
        let id = UUID()
        let first = CharacterGrowthEngine.apply(
            strongSignal(),
            to: .initial,
            relationship: relationshipSignal(),
            evidenceMessageID: id
        )
        let arc = try #require(first.arcs.first)
        #expect(arc.stage == .considering)
        #expect(arc.progress <= 0.05)

        let duplicate = CharacterGrowthEngine.apply(
            strongSignal(),
            to: first,
            relationship: relationshipSignal(),
            evidenceMessageID: id
        )
        #expect(duplicate == first)
    }

    @Test("多条独立证据才会从思考进入尝试")
    func repeatedEvidenceAdvancesStageSlowly() throws {
        var snapshot = CharacterGrowthSnapshot.initial
        for _ in 0..<3 {
            snapshot = CharacterGrowthEngine.apply(
                strongSignal(),
                to: snapshot,
                relationship: relationshipSignal(),
                evidenceMessageID: UUID()
            )
        }
        let arc = try #require(snapshot.arcs.first)
        #expect(arc.evidenceMessageIDs.count == 3)
        #expect(arc.stage == .experimenting)
        #expect(abs(arc.progress - 0.15) < 0.000_001)
    }

    @Test("反向影响先抵消旧变化，且后台重试不会重复扣减")
    func opposingEvidenceCannotInstantlyFlipDirection() throws {
        let firstID = UUID()
        let seeded = CharacterGrowthEngine.apply(
            strongSignal(direction: .decrease),
            to: .initial,
            relationship: relationshipSignal(),
            evidenceMessageID: firstID
        )
        let opposingID = UUID()
        let neutralized = CharacterGrowthEngine.apply(
            strongSignal(direction: .increase),
            to: seeded,
            relationship: relationshipSignal(),
            evidenceMessageID: opposingID
        )
        let neutralArc = try #require(neutralized.arcs.first)
        #expect(neutralArc.direction == .decrease)
        #expect(neutralArc.progress == 0)

        let duplicate = CharacterGrowthEngine.apply(
            strongSignal(direction: .increase),
            to: neutralized,
            relationship: relationshipSignal(),
            evidenceMessageID: opposingID
        )
        #expect(duplicate == neutralized)

        let flipped = CharacterGrowthEngine.apply(
            strongSignal(direction: .increase),
            to: neutralized,
            relationship: relationshipSignal(),
            evidenceMessageID: UUID()
        )
        #expect(flipped.arcs.first?.direction == .increase)
        #expect(flipped.arcs.first?.stage == .considering)
    }

    @Test("成长提示保留核心人格并禁止虚构屏外改变")
    func promptKeepsCoreIdentityStable() throws {
        let snapshot = CharacterGrowthEngine.apply(
            strongSignal(),
            to: .initial,
            relationship: relationshipSignal(),
            evidenceMessageID: UUID()
        )
        let prompt = try #require(CharacterGrowthEngine.promptContext(snapshot))
        #expect(prompt.contains("core identity remains stable"))
        #expect(prompt.contains("do not claim success or invent an off-screen event"))
        #expect(prompt.contains("not changed yet"))
    }

    @Test("暂停后拒绝新证据，恢复后可以继续成长")
    func pausingAndResumingGrowth() throws {
        let paused = CharacterGrowthEngine.settingPaused(true, in: .initial)
        #expect(paused.isPaused)
        #expect(paused.revision == 1)

        let whilePaused = CharacterGrowthEngine.apply(
            strongSignal(),
            to: paused,
            relationship: relationshipSignal(),
            evidenceMessageID: UUID()
        )
        #expect(whilePaused == paused)

        let resumed = CharacterGrowthEngine.settingPaused(false, in: whilePaused)
        let afterNewEvidence = CharacterGrowthEngine.apply(
            strongSignal(),
            to: resumed,
            relationship: relationshipSignal(),
            evidenceMessageID: UUID()
        )
        #expect(!resumed.isPaused)
        #expect(afterNewEvidence.arcs.count == 1)
        #expect(afterNewEvidence.revision == 3)
    }

    @Test("重复设置同一暂停状态保持幂等")
    func pauseSettingIsIdempotent() {
        let paused = CharacterGrowthEngine.settingPaused(true, in: .initial)
        #expect(CharacterGrowthEngine.settingPaused(true, in: paused) == paused)
    }

    @Test("撤销单项成长不影响其他成长")
    func removesOnlySelectedArc() {
        let removedID = UUID()
        let retainedID = UUID()
        let snapshot = CharacterGrowthSnapshot(
            revision: 4,
            arcs: [
                growthArc(id: removedID, trait: .impulsivity),
                growthArc(id: retainedID, trait: .patience),
            ]
        )

        let updated = CharacterGrowthEngine.removingArc(id: removedID, from: snapshot)
        #expect(updated.arcs.map(\.id) == [retainedID])
        #expect(updated.revision == 5)
        #expect(CharacterGrowthEngine.removingArc(id: removedID, from: updated) == updated)
    }

    @Test("清空成长时保留暂停选择")
    func clearsGrowthButPreservesPausePreference() {
        let snapshot = CharacterGrowthSnapshot(
            revision: 2,
            isPaused: true,
            arcs: [growthArc(id: UUID(), trait: .openness)]
        )
        let cleared = CharacterGrowthEngine.clearingGrowth(in: snapshot)
        #expect(cleared.arcs.isEmpty)
        #expect(cleared.isPaused)
        #expect(cleared.revision == 3)
    }

    private func growthArc(id: UUID, trait: CharacterGrowthTrait) -> CharacterGrowthArc {
        CharacterGrowthArc(
            id: id,
            trait: trait,
            direction: .increase,
            progress: 0.2,
            stage: .experimenting,
            reasonZh: "多次交流留下的变化",
            evidenceMessageIDs: [UUID(), UUID(), UUID()]
        )
    }

    private func strongSignal(
        direction: CharacterGrowthDirection = .decrease
    ) -> CharacterGrowthSignal {
        CharacterGrowthSignal(
            trait: CharacterGrowthTrait.impulsivity.rawValue,
            direction: direction.rawValue,
            relevance: 1,
            agencyRespect: 1,
            confidence: 1,
            reasonZh: "用户的安慰让角色愿意在重要决定前停一下"
        )
    }

    private func relationshipSignal() -> RelationshipSignal {
        RelationshipSignal(
            warmth: 0.7,
            responsiveness: 0.8,
            respect: 0.8,
            empathy: 0.8,
            reciprocity: 0.5,
            disclosure: 0.6,
            resonance: 0.5,
            engagement: 0.8,
            boundaryHarm: 0,
            repair: 0,
            significance: 0.8,
            confidence: 0.9,
            reasonZh: "尊重且有意义的交流"
        )
    }
}
