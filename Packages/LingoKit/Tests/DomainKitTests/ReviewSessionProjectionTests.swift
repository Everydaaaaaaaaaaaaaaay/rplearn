import Foundation
import Testing
@testable import DomainKit

@Suite("ReviewSessionProjection")
struct ReviewSessionProjectionTests {
    let account = UUID(), session = UUID(), attempt = UUID(), item = UUID()

    func event(
        _ action: ReviewSessionEvent.Action, id: UUID = UUID(),
        attemptID: UUID? = nil, itemID: UUID? = nil, version: Int = 1,
        accountID: UUID? = nil, sessionID: UUID? = nil
    ) -> ReviewSessionEvent {
        .init(eventID: id, accountID: accountID ?? account, sessionID: sessionID ?? session,
              attemptID: attemptID ?? attempt, itemID: itemID ?? item,
              materialVersion: version, action: action)
    }
    func replay(_ events: [ReviewSessionEvent]) throws -> ReviewSessionProjection {
        try .replay(events, accountID: account, sessionID: session)
    }

    @Test("Repeated uploads are idempotent but conflicting payloads fail")
    func duplicates() throws {
        let reveal = event(.reveal), rate = event(.rate(.forgot))
        let result = try replay([reveal, rate, reveal, rate])
        #expect(result.completedAttemptCount == 1)
        #expect(throws: ReviewSessionProjection.ValidationError.conflictingEventID) {
            try replay([reveal, rate, event(.rate(.remembered), id: rate.eventID)])
        }
    }

    @Test("Undo retains exposure and hint; corrected rating remains the same attempt")
    func correction() throws {
        let rate = event(.rate(.forgot))
        let result = try replay([event(.hint), event(.reveal), rate,
                                 event(.undo(targetEventID: rate.eventID)), event(.rate(.remembered))])
        #expect(result.attempts.count == 1)
        #expect(result.attempts[attempt]?.answerExposed == true)
        #expect(result.completedAttemptCount == 1)
        #expect(result.activeRatings.first?.usedHint == true)
        #expect(result.activeRatings.first?.isCorrection == true)
        #expect(result.finalMaterialDistribution[.remembered] == 1)
        #expect(result.finalMaterialDistribution[.forgot] == 0)
    }

    @Test("Repeated undo cannot erase a later correction")
    func repeatedUndo() throws {
        let rate = event(.rate(.forgot))
        let result = try replay([event(.reveal), rate, event(.undo(targetEventID: rate.eventID)),
                                 event(.rate(.fuzzy)), event(.undo(targetEventID: rate.eventID))])
        #expect(result.activeRatings.map(\.value) == [.fuzzy])
    }

    @Test("No reveal or duplicate self-rating fails without producing a projection")
    func invalidRating() {
        #expect(throws: ReviewSessionProjection.ValidationError.answerNotRevealed) {
            try replay([event(.rate(.remembered))])
        }
        #expect(throws: ReviewSessionProjection.ValidationError.ratingAlreadyExists) {
            try replay([event(.reveal), event(.rate(.remembered)), event(.rate(.forgot))])
        }
    }

    @Test("Accounts and sessions cannot be mixed")
    func isolation() {
        #expect(throws: ReviewSessionProjection.ValidationError.wrongAccount) {
            try replay([event(.reveal, accountID: UUID())])
        }
        #expect(throws: ReviewSessionProjection.ValidationError.wrongSession) {
            try replay([event(.reveal, sessionID: UUID())])
        }
    }

    @Test("Attempt material and version are immutable")
    func materialVersion() {
        #expect(throws: ReviewSessionProjection.ValidationError.changedMaterial) {
            try replay([event(.reveal), event(.rate(.forgot), version: 2)])
        }
        #expect(throws: ReviewSessionProjection.ValidationError.changedMaterial) {
            try replay([event(.reveal), event(.rate(.forgot), itemID: UUID())])
        }
        #expect(throws: ReviewSessionProjection.ValidationError.invalidMaterialVersion) {
            try replay([event(.reveal, version: 0)])
        }
    }

    @Test("Undo cannot point outside its attempt")
    func invalidUndo() {
        let rate = event(.rate(.forgot))
        #expect(throws: ReviewSessionProjection.ValidationError.invalidUndoTarget) {
            try replay([event(.reveal), rate, event(.undo(targetEventID: rate.eventID), attemptID: UUID())])
        }
        #expect(throws: ReviewSessionProjection.ValidationError.invalidUndoTarget) {
            try replay([event(.undo(targetEventID: UUID()))])
        }
    }

    @Test("Multiple attempts count separately; final material distribution does not")
    func materialStatistics() throws {
        let otherAttempt = UUID()
        let result = try replay([event(.reveal), event(.rate(.forgot)),
                                 event(.reveal, attemptID: otherAttempt),
                                 event(.rate(.remembered), attemptID: otherAttempt)])
        #expect(result.completedAttemptCount == 2)
        #expect(result.reviewedMaterialCount == 1)
        #expect(result.finalMaterialDistribution.values.reduce(0, +) == 1)
        #expect(result.finalMaterialDistribution[.remembered] == 1)
    }

    @Test("Revealing or undoing without a final rating does not count as completed")
    func incomplete() throws {
        #expect(try replay([event(.reveal)]).completedAttemptCount == 0)
        let rate = event(.rate(.forgot))
        let result = try replay([event(.reveal), rate, event(.undo(targetEventID: rate.eventID))])
        #expect(result.reviewedMaterialCount == 0)
        #expect(result.attempts[attempt]?.answerExposed == true)
    }
}
