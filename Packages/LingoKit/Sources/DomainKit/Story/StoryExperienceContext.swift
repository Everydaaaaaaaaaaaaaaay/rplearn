import Foundation
import PersistenceKit

/// A bounded projection of completed authored paths, separate from real user facts.
public enum StoryExperienceContext {
    public static func sections(character: CharacterDTO, progress: [StoryProgressDTO], after cutoff: Date? = nil) -> [String] {
        guard character.isMainCharacter else { return [] }
        let source: String
        let facts: [String: String]
        switch (character.card.name, character.card.regionID) {
        case ("Ruby Walker", "melbourne"):
            source = "departures_mainline_melbourne_v2"
            facts = [
                "RB11": "The user stayed twenty minutes and listened to your application opening about bottle caps on the beach. You were still writing when they left. Submission and admission are unknown; no next walk was booked.",
                "RB12": "The user stayed twenty minutes doing their own thing while you wrote. They left on time. Your application was not yet finished; no next walk was booked.",
                "RB21": "The user left to keep their own afternoon. In that story, you both agreed to meet at the café at four the following afternoon. The walk has not been shown as completed; the story-relative date is not today's date.",
                "RB22": "The user left with their coffee; you agreed not to pick another date yet. They did not hear the bottle-cap opening. No new appointment exists.",
            ]
        case ("Marcus Rivera", "newyork"):
            source = "departures_city_newyork_v2"
            facts = [
                "ML11": "You were late. The user ate first. You arrived at one twenty and walked with them to the corner until one thirty, joking about a song you knew. You did not eat lunch together or book another lunch.",
                "ML12": "You were late. The user ate first. You arrived at one twenty and sat with them briefly, joking about a cold chip. No next lunch was booked. This does not prove full forgiveness.",
                "ML21": "You missed lunch together. With the user's permission, you checked your days off and offered Tuesday or Thursday at noon. The user had not chosen either. These were story-world suggestions, not current confirmed dates.",
                "ML22": "You missed lunch together. The user asked to leave planning with them until they want to arrange something. You accepted. Do not send new dates or press for a meeting unless they reopen planning.",
            ]
        default:
            return []
        }
        guard let record = progress.first(where: { $0.storyID == source && $0.isCompleted }) else { return [] }
        if let cutoff, let completedAt = record.completedAt, completedAt <= cutoff { return [] }
        let completed = facts.keys.filter { record.flags["experience." + $0] == true }
        guard completed.count == 1, let key = completed.first, let fact = facts[key] else { return [] }
        return ["""
        ## 已完成的故事世界经历
        以下是预写故事中实际完成的路径，不是用户现实生活资料。只在当前话题相关时自然提起，不必每轮回忆。
        未被记录的分支没有发生。故事里的明天、周二不等于设备的下一个日期；不得自动创建新约定，也不得补写申请结果、会面或和解。之后有明确的新对话证据时，以新的计划状态为准。
        \(fact)
        """]
    }
}
