import Foundation
import PersistenceKit

/// Uses the existing multidimensional algorithm, adding a permanent receipt for the server CAS.
public enum AppointmentRelationshipProjection {
    public static func apply(_ signal: RelationshipSignal, eventID: UUID, to snapshot: RelationshipSnapshot,
                             at date: Date, calendar: Calendar = .current) -> RelationshipSnapshot {
        guard !(snapshot.settledAppointmentIDs ?? []).contains(eventID) else { return snapshot }
        var result = RelationshipEngine.apply(signal, to: snapshot, source: .appointment, messageID: eventID,
            messageCreatedAt: date, messageOrderIndex: snapshot.lastEvaluatedOrderIndex + 1, at: date, calendar: calendar)
        let before = snapshot.projectedAffinity(at: max(date, snapshot.lastInteractionAt ?? date))
        let reason = signal.reasonZh.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousIDs = Set(snapshot.recentEvents.map(\.id))
        result.recentEvents.removeAll { !previousIDs.contains($0.id) }
        result.recentEvents.append(RelationshipEventRecord(id: eventID, source: .appointment,
            delta: result.affinity - before, reasonZh: reason.isEmpty ? "这次相处自然结束" : reason, createdAt: date))
        result.recentEvents = Array(result.recentEvents.suffix(24))
        result.settledAppointmentIDs = (snapshot.settledAppointmentIDs ?? []) + [eventID]
        return result
    }
}
