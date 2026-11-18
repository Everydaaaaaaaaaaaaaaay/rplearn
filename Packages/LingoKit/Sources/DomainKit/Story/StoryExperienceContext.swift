import Foundation
import PersistenceKit

/// A bounded projection of completed authored paths, separate from real user facts.
public enum StoryExperienceContext {
    public static func sourceIDs(for character: CharacterDTO) -> [String] {
        guard character.isMainCharacter else { return [] }
        switch (character.card.name, character.card.regionID) {
        case ("Ruby Walker", "melbourne"):
            return ["departures_mainline_melbourne_v2", "departures_mainline_melbourne_v3"]
        case ("Marcus Rivera", "newyork"):
            return ["departures_city_newyork_v2", "departures_city_newyork_v3"]
        default:
            return []
        }
    }

    public static func sections(character: CharacterDTO, progress: [StoryProgressDTO], after cutoff: Date? = nil) -> [String] {
        guard character.isMainCharacter else { return [] }
        let source: String
        let facts: [String: String]
        let revisedFacts: [String: String]
        switch (character.card.name, character.card.regionID) {
        case ("Ruby Walker", "melbourne"):
            source = "departures_mainline_melbourne_v2"
            facts = [
                "RB11": "The user stayed twenty minutes and listened to your application opening about bottle caps on the beach. You were still writing when they left. Submission and admission are unknown; no next walk was booked.",
                "RB12": "The user stayed twenty minutes doing their own thing while you wrote. They left on time. Your application was not yet finished; no next walk was booked.",
                "RB21": "The user left to keep their own afternoon. In that story, you both agreed to meet at the café at four the following afternoon. The walk has not been shown as completed; the story-relative date is not today's date.",
                "RB22": "The user left with their coffee; you agreed not to pick another date yet. They did not hear the bottle-cap opening. No new appointment exists.",
            ]
            revisedFacts = [
                "RB311": "The user stayed twenty minutes and listened to your application draft about repeated bottle caps at Port Phillip Bay. You were still revising when they left. Submission and admission are unknown. No next walk was booked.",
                "RB312": "The user quietly did their own thing beside you for twenty minutes while you wrote and revised the application. They did not hear the bottle-cap draft. Your application was not shown as finished; no new walk was booked.",
                "RB321": "The user left with their coffee. You both agreed to meet at the cafe at four the next afternoon, with the laptop put away. They did not hear the bottle-cap draft. The walk has not happened on screen. This story-relative date is not today's date.",
                "RB322": "The user left with their coffee and chose not to arrange another date yet. You stayed to work on the application. They did not hear the bottle-cap draft. No new appointment exists.",
            ]
        case ("Marcus Rivera", "newyork"):
            source = "departures_city_newyork_v2"
            facts = [
                "ML11": "You were late. The user ate first. You arrived at one twenty and walked with them to the corner until one thirty, joking about a song you knew. You did not eat lunch together or book another lunch.",
                "ML12": "You were late. The user ate first. You arrived at one twenty and sat with them briefly, joking about a cold chip. No next lunch was booked. This does not prove full forgiveness.",
                "ML21": "You missed lunch together. With the user's permission, you checked your days off and offered Tuesday or Thursday at noon. The user had not chosen either. These were story-world suggestions, not current confirmed dates.",
                "ML22": "You missed lunch together. The user asked to leave planning with them until they want to arrange something. You accepted. Do not send new dates or press for a meeting unless they reopen planning.",
            ]
            revisedFacts = [
                "ML311": "You were late. The user ate first. You arrived at one twenty and walked with them to the corner, humming a song you had called the worst on its record. You parted there. No next lunch was booked.",
                "ML312": "You were late. The user ate first. You arrived at one twenty and sat briefly opposite their last cold chip. You had not eaten. The user left and you went to find your own lunch. This does not establish forgiveness or a new appointment.",
                "ML321": "You missed lunch together. That evening, with the user's permission, you checked your shifts and offered Tuesday or Thursday at noon. The user had not chosen either. These were story-world suggestions, not current confirmed dates.",
                "ML322": "You missed lunch together. The user asked to leave planning with them until they want to arrange something. You accepted. Do not send new dates or press for a meeting unless they reopen planning.",
            ]
        default:
            return []
        }
        let sources = sourceIDs(for: character)
        let completedRecords = progress.filter { sources.contains($0.storyID) && $0.isCompleted }
        guard let record = completedRecords.max(by: {
            if $0.completedAt == $1.completedAt {
                return (sources.firstIndex(of: $0.storyID) ?? 0) < (sources.firstIndex(of: $1.storyID) ?? 0)
            }
            return ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast)
        }) else { return [] }
        let applicableFacts = record.storyID == source ? facts : revisedFacts
        if let cutoff, let completedAt = record.completedAt, completedAt <= cutoff { return [] }
        let completed = applicableFacts.keys.filter { record.flags["experience." + $0] == true }
        guard completed.count == 1, let key = completed.first, let fact = applicableFacts[key] else { return [] }
        return ["""
        ## 已完成的故事世界经历
        以下是预写故事中实际完成的路径，不是用户现实生活资料。只在当前话题相关时自然提起，不必每轮回忆。
        未被记录的分支没有发生。故事里的明天、周二不等于设备的下一个日期；不得自动创建新约定，也不得补写申请结果、会面或和解。之后有明确的新对话证据时，以新的计划状态为准。
        \(fact)
        """]
    }
}
