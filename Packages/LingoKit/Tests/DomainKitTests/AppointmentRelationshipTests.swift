import Foundation
import Testing
@testable import DomainKit
import PersistenceKit

struct AppointmentRelationshipTests {
    private let date = Date(timeIntervalSince1970: 1_793_491_200)
    private var signal: RelationshipSignal {
        RelationshipSignal(warmth: 0.8, responsiveness: 0.9, respect: 0.9, empathy: 0.7,
                           reciprocity: 0.8, disclosure: 0.3, resonance: 0.8, engagement: 0.8,
                           boundaryHarm: 0, repair: 0, significance: 0.6, confidence: 0.9,
                           reasonZh: "认真回应并尊重了彼此的选择")
    }
    @Test func usesExistingEngineAndStableReceipt() {
        let id = UUID()
        let original = RelationshipSnapshot.initial
        let expected = RelationshipEngine.apply(signal, to: original, source: .appointment,
            messageID: id, messageOrderIndex: 0, at: date)
        let actual = AppointmentRelationshipProjection.apply(signal, eventID: id, to: original, at: date)
        #expect(actual.affinity == expected.affinity)
        #expect(actual.settledAppointmentIDs?.contains(id) == true)
        #expect(actual.recentEvents.last?.id == id)
        #expect(actual.recentEvents.last?.source == .appointment)
    }
    @Test func replayIsIgnoredEvenAfterRecentMessageIDsAreEvicted() {
        let id = UUID()
        var settled = AppointmentRelationshipProjection.apply(signal, eventID: id, to: .initial, at: date)
        settled.recentEvaluatedMessageIDs = []
        settled.lastEvaluatedMessageID = nil
        #expect(AppointmentRelationshipProjection.apply(signal, eventID: id, to: settled,
            at: date.addingTimeInterval(90_000)) == settled)
    }
}
