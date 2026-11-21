import Foundation
import PersistenceKit

public enum ChatTimelineEvidence {
    public static func mood(reply: String) -> ChatMessageTimelineEvent? {
        ChatMoodEvidence.observe(in: reply).map {
            .init(kind: .mood, state: $0.primary.rawValue, secondary: $0.secondary?.rawValue, strength: $0.intensity)
        }
    }

    static func relationship(
        before: RelationshipSnapshot, after: RelationshipSnapshot,
        receipt: RelationshipEventRecord, confidence: Double
    ) -> ChatMessageTimelineEvent? {
        let delta = receipt.delta
        guard delta.isFinite, confidence >= 0.70 else { return nil }
        let strain = after.unresolvedStrain - before.unresolvedStrain
        let trust = after.trust - before.trust
        let rapport = after.rapport - before.rapport
        let state: String
        if strain <= -0.09 {
            state = "repair"
        } else if strain >= 0.13 {
            state = "strained"
        } else if abs(trust) >= 0.07 {
            state = trust > 0 ? "trustIncreased" : "trustDecreased"
        } else if abs(rapport) >= 0.08 {
            state = rapport > 0 ? "closer" : "distant"
        } else {
            guard abs(delta) >= 0.15 else { return nil }
            state = "affinity"
        }
        return .init(kind: .relationship, state: state, delta: delta)
    }

    /// A recall needs both an explicit callback and a matching saved fact.
    public static func recalledMemory(reply: String, userMessage: MessageDTO, memories: [MemoryDTO]) -> ChatMessageTimelineEvent? {
        let replies = recallClauses(reply)
        guard !replies.isEmpty else { return nil }
        let userText = normalizedWords(userMessage.text)
        let hasMatch = memories.contains { memory in
            guard let record = memory.record, record.status != "cancelled", !record.forgotten, !record.archived,
                  record.messageID != userMessage.id, record.observedAt < userMessage.createdAt else { return false }
            var fact = normalizedWords(record.text)
            for prefix in ["the user ", "user ", "you "] where fact.hasPrefix(prefix) {
                fact.removeFirst(prefix.count)
                break
            }
            return fact.count >= 14 && replies.contains(where: { $0.contains(fact) }) && !userText.contains(fact)
        }
        return hasMatch ? .init(kind: .memory, state: "recalled") : nil
    }

    public static func hasRecallCue(_ reply: String) -> Bool {
        !recallClauses(reply).isEmpty
    }

    private static func recallClauses(_ reply: String) -> [String] {
        let heads = ["i remember you ", "you told me before ", "you mentioned before ", "我记得你", "你以前说过"]
        let unquoted = reply.replacingOccurrences(of: #"[“"][\s\S]*?[”"]"#, with: "", options: .regularExpression)
        return unquoted.split(whereSeparator: { ".!?。！？\n".contains($0) })
            .map { normalizedWords(String($0)) }
            .filter { clause in heads.contains(where: clause.hasPrefix) }
    }

    public static func memory(_ change: CommittedChatMemoryChange) -> ChatMessageTimelineEvent {
        let state: String
        switch change.kind {
        case .remembered: state = "remembered"
        case .refined: state = "refined"
        case .corrected: state = "corrected"
        case .updated: state = "updated"
        }
        return .init(kind: .memory, state: state)
    }

    private static func normalizedWords(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }
}
