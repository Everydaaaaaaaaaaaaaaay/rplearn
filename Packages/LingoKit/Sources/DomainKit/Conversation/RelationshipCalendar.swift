import Foundation

/// One character-local activity day for chat, contact, shared activities and appointments.
public enum RelationshipCalendar {
    public static func forRegionID(_ regionID: String) -> Calendar {
        RoleplayTemporalContext.calendar(for: regionID)
    }
}
