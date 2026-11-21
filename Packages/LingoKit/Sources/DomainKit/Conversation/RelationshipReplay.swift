import Foundation
import PersistenceKit

/// Reuses the existing deterministic engine; neither scoring approximations nor model calls belong here.
public enum RelationshipReplay {
    public static func reviewed(_ signal: RelationshipSignal, source: RelationshipEventRecord.Source,
                                messageID: UUID, messageCreatedAt: Date, messageOrderIndex: Int,
                                at date: Date, calendar: Calendar = .current) throws -> RelationshipReplayInput {
        let json = String(decoding: try JSONEncoder().encode(signal), as: UTF8.self)
        return RelationshipReplayInput(kind: .reviewed, signalJSON: json, source: source,
            messageID: messageID, messageCreatedAt: messageCreatedAt, messageOrderIndex: messageOrderIndex,
            evaluatedAt: date, calendar: calendar)
    }

    public static func apply(_ inputs: [RelationshipReplayInput], to snapshot: RelationshipSnapshot) throws -> RelationshipSnapshot {
        var result = snapshot
        var seen = Set<UUID>()
        for input in inputs {
            guard seen.insert(input.messageID).inserted else { continue }
            if result.settledAppointmentIDs?.contains(input.messageID) == true { continue }
            switch input.kind {
            case .reviewed:
                guard let json = input.signalJSON else {
                    throw ContentRelationshipReconciliation.ReconciliationError.missingEvidence
                }
                let signal = try JSONDecoder().decode(RelationshipSignal.self, from: Data(json.utf8))
                result = RelationshipEngine.apply(signal, to: result, source: input.source,
                    messageID: input.messageID, messageCreatedAt: input.messageCreatedAt,
                    messageOrderIndex: input.messageOrderIndex, at: input.evaluatedAt, calendar: input.calendar)
            case .contact:
                result = RelationshipEngine.recordContact(in: result, messageID: input.messageID,
                    messageCreatedAt: input.messageCreatedAt, messageOrderIndex: input.messageOrderIndex,
                    at: input.evaluatedAt, calendar: input.calendar)
            }
        }
        return result
    }
}
