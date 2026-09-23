import Foundation

/// Persisted separately from proficiency: presentation never awards learning credit.
public struct LearningChatPresentation: Codable, Sendable, Equatable {
    public var hasChosenRecording = false
    public var acknowledgedEvidence: Set<UUID> = []
    public var deferredUntil: Date?
    public var lastInvitationAt: Date?
    public var invitationsByDay: [Int: Int] = [:]
    public init() {}

    /// Automatic expansion is exceptional. Manual access is always available.
    public func canInvite(now: Date, busy: Bool, composing: Bool) -> Bool {
        guard !busy, !composing, deferredUntil.map({ $0 > now }) != true else { return false }
        if let previous = lastInvitationAt, now.timeIntervalSince(previous) < 600 { return false }
        return invitationsByDay[LearningSystemPolicy.utcDay(now), default: 0] < 2
    }
    public mutating func markInvitation(now: Date) {
        lastInvitationAt = now
        let day = LearningSystemPolicy.utcDay(now)
        invitationsByDay = invitationsByDay.filter { $0.key >= day - 7 }
        invitationsByDay[day, default: 0] += 1
    }
    public mutating func deferToday(now: Date) {
        deferredUntil = now.addingTimeInterval(LearningSystemPolicy.day)
    }

    public static func instruction(for task: LearningTask) -> String {
        """
        The user voluntarily accepted this short conversational practice: \(task.instruction)
        Keep your established friend personality and normal short-message rhythm. This is an imagined practice scene, not a real-world promise. Respond to what the user actually said; don't repeat questions already answered. Let them express the target naturally. Do not announce scores, evaluate their level, supply a model answer, or turn the chat into an exam. If they change topic or say they want to stop, follow them without pressure. A separate learning service handles assessment; you must not claim they passed.
        """
    }
}
