import Foundation

/// Carries only observed, still-existing learner turns across reviews of one open task.
/// It never schedules a review itself; a new learner event is required.
public struct LearningChallengeContext: Codable, Sendable {
    public private(set) var turns: [LearningSystemReviewer.Turn] = []
    public private(set) var assisted = false
    public init() {}
    public func appending(_ fresh: [LearningSystemReviewer.Turn], assisted: Bool, available: Set<UUID>) -> Self {
        var result = Self(), seen = Set<UUID>()
        let unique = (turns + fresh).filter { available.contains($0.id) && seen.insert($0.id).inserted }
        var remaining = 4000
        for turn in unique.reversed().prefix(8) {
            guard turn.text.count <= remaining else { break }
            remaining -= turn.text.count
            result.turns.insert(turn, at: 0)
        }
        result.assisted = self.assisted || assisted
        return result
    }
    public static func evidenceQuote(_ item: LearningSystemReviewer.Assessment, turns: [LearningSystemReviewer.Turn]) -> String {
        let selected = turns.filter { item.messageIDs.contains($0.id) }.map(\.text)
        return selected.isEmpty ? item.quote : selected.joined(separator: "\n")
    }
}
