import Foundation

/// Self-report about recall before revealing the answer, never a mastery score.
public enum ReviewSelfRating: String, Codable, CaseIterable, Sendable {
    case forgot, fuzzy, remembered
}

/// Single-session facts. Persistence, ordering and scheduling are separate responsibilities.
public struct ReviewSessionEvent: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case hint
        case reveal
        case rate(ReviewSelfRating)
        case undo(targetEventID: UUID)
    }

    public let eventID: UUID
    public let accountID: UUID
    public let sessionID: UUID
    public let attemptID: UUID
    public let itemID: UUID
    public let materialVersion: Int
    public let action: Action

    public init(
        eventID: UUID, accountID: UUID, sessionID: UUID, attemptID: UUID,
        itemID: UUID, materialVersion: Int, action: Action
    ) {
        self.eventID = eventID
        self.accountID = accountID
        self.sessionID = sessionID
        self.attemptID = attemptID
        self.itemID = itemID
        self.materialVersion = materialVersion
        self.action = action
    }
}

/// Deterministic projection for the review session UI, not a cross-device merge or scheduler.
public struct ReviewSessionProjection: Equatable, Sendable {
    public struct Rating: Equatable, Sendable {
        public let eventID: UUID
        public let attemptID: UUID
        public let itemID: UUID
        public let materialVersion: Int
        public let value: ReviewSelfRating
        public let usedHint: Bool
        public let isCorrection: Bool
    }

    public struct Attempt: Equatable, Sendable {
        public let itemID: UUID
        public let materialVersion: Int
        public fileprivate(set) var usedHint = false
        public fileprivate(set) var answerExposed = false
        public fileprivate(set) var wasCorrected = false
        public fileprivate(set) var activeRating: Rating?
    }

    public enum ValidationError: Error, Equatable {
        case wrongAccount, wrongSession, invalidMaterialVersion
        case conflictingEventID, changedMaterial, answerNotRevealed
        case ratingAlreadyExists, invalidUndoTarget
    }

    public let attempts: [UUID: Attempt]
    /// Valid ratings in original event order; multiple attempts may concern the same material.
    public let activeRatings: [Rating]

    public var completedAttemptCount: Int { activeRatings.count }
    public var reviewedMaterialCount: Int { Set(activeRatings.map(\.itemID)).count }

    /// One final self-rating per material. Sum equals reviewedMaterialCount, not vocabulary size.
    public var finalMaterialDistribution: [ReviewSelfRating: Int] {
        var final: [UUID: ReviewSelfRating] = [:]
        for rating in activeRatings { final[rating.itemID] = rating.value }
        return Dictionary(uniqueKeysWithValues: ReviewSelfRating.allCases.map { value in
            (value, final.values.filter { $0 == value }.count)
        })
    }

    /// Input must be in canonical session order. Exact retries are ignored; conflicts fail closed.
    public static func replay(
        _ events: [ReviewSessionEvent], accountID: UUID, sessionID: UUID
    ) throws -> Self {
        var seen: [UUID: ReviewSessionEvent] = [:]
        var attempts: [UUID: Attempt] = [:]
        var ratings: [Rating] = []
        var ratingByID: [UUID: Rating] = [:]
        var undone: Set<UUID> = []
        for event in events {
            guard event.accountID == accountID else { throw ValidationError.wrongAccount }
            guard event.sessionID == sessionID else { throw ValidationError.wrongSession }
            guard event.materialVersion > 0 else { throw ValidationError.invalidMaterialVersion }
            if let previous = seen[event.eventID] {
                guard previous == event else { throw ValidationError.conflictingEventID }
                continue
            }
            seen[event.eventID] = event
            var attempt = attempts[event.attemptID] ?? Attempt(
                itemID: event.itemID, materialVersion: event.materialVersion
            )
            guard attempt.itemID == event.itemID,
                  attempt.materialVersion == event.materialVersion
            else { throw ValidationError.changedMaterial }
            switch event.action {
            case .hint:
                attempt.usedHint = true
            case .reveal:
                attempt.answerExposed = true
            case let .rate(value):
                guard attempt.answerExposed else { throw ValidationError.answerNotRevealed }
                guard attempt.activeRating == nil else { throw ValidationError.ratingAlreadyExists }
                let rating = Rating(
                    eventID: event.eventID, attemptID: event.attemptID,
                    itemID: event.itemID, materialVersion: event.materialVersion,
                    value: value, usedHint: attempt.usedHint, isCorrection: attempt.wasCorrected
                )
                ratings.append(rating)
                ratingByID[event.eventID] = rating
                attempt.activeRating = rating
            case let .undo(targetEventID):
                guard let target = ratingByID[targetEventID], target.attemptID == event.attemptID
                else { throw ValidationError.invalidUndoTarget }
                if undone.insert(targetEventID).inserted {
                    if attempt.activeRating?.eventID == targetEventID { attempt.activeRating = nil }
                    attempt.wasCorrected = true
                }
            }
            attempts[event.attemptID] = attempt
        }
        return Self(attempts: attempts, activeRatings: ratings.filter { !undone.contains($0.eventID) })
    }
}
