import PersistenceKit
import Testing
@testable import DomainKit

struct ChatTimelineEvidenceTests {
    @Test func describesPersistedRelationshipDimensionsAndBothScoreDirections() throws {
        var before = RelationshipSnapshot.initial
        before.trust = 0.5
        before.rapport = 0.5
        before.unresolvedStrain = 0.3
        let receipt = RelationshipEventRecord(source: .textChat, delta: 0.2, reasonZh: "共同经历")
        let cases: [(String, (inout RelationshipSnapshot) -> Void)] = [
            ("repair", { $0.unresolvedStrain = 0.18 }),
            ("strained", { $0.unresolvedStrain = 0.49 }),
            ("trustIncreased", { $0.trust = 0.6 }),
            ("trustDecreased", { $0.trust = 0.4 }),
            ("closer", { $0.rapport = 0.6 }),
            ("distant", { $0.rapport = 0.4 }),
            ("affinity", { $0.affinity += 0.2 }),
        ]
        for (state, change) in cases {
            var after = before
            change(&after)
            let event = try #require(ChatTimelineEvidence.relationship(
                before: before, after: after, receipt: receipt, confidence: 0.9))
            #expect(event.state == state)
            #expect(event.delta == 0.2)
        }
        var negative = receipt
        negative.delta = -0.3
        #expect(ChatTimelineEvidence.relationship(before: before, after: before, receipt: negative, confidence: 0.8)?.delta == -0.3)
        #expect(ChatTimelineEvidence.relationship(before: before, after: before, receipt: negative, confidence: 0.5) == nil)
        negative.delta = -0.02
        #expect(ChatTimelineEvidence.relationship(before: before, after: before, receipt: negative, confidence: 0.8) == nil)
    }

    @Test func recallNeedsAnExplicitCallbackInTheCharacterVoice() {
        #expect(ChatTimelineEvidence.hasRecallCue("I remember you like the quiet path."))
        #expect(ChatTimelineEvidence.hasRecallCue("The rain has stopped. You mentioned before that you like the river."))
        #expect(!ChatTimelineEvidence.hasRecallCue("I don't remember you mentioning that."))
        #expect(!ChatTimelineEvidence.hasRecallCue("She said, “I remember you like the quiet path.”"))
        #expect(!ChatTimelineEvidence.hasRecallCue("The quiet path is probably nice."))
    }
}
