import Foundation
import PersistenceKit
import Testing
@testable import DomainKit

@Suite("已完成剧情经历的聊天承接")
struct StoryExperienceContextTests {
    private func marcus(main: Bool = true) -> CharacterDTO {
        CharacterDTO(id: UUID(), card: CharacterCard(name: "Marcus Rivera", age: 26,
            gender: .male, nationality: "American", regionID: "newyork", occupation: "photographer",
            hobbies: ["records"], appearance: "short hair", personality: "direct"),
            difficultyLevel: .primary1, isMainCharacter: main, isFriend: true, metAt: .now)
    }
    private func progress(_ flags: [String: Bool], completed: Bool = true) -> StoryProgressDTO {
        StoryProgressDTO(storyID: "departures_city_newyork_v2", currentNodeID: nil,
                         flags: flags, completedAt: completed ? Date(timeIntervalSince1970: 100) : nil)
    }

    @Test("未完成、未知和互相矛盾的分支证据不进入聊天")
    func rejectsUnsupportedOutcomes() {
        #expect(StoryExperienceContext.sections(character: marcus(), progress: [progress(["ML00": true])]).isEmpty)
        #expect(StoryExperienceContext.sections(character: marcus(), progress: [progress(["experience.ML11": true], completed: false)]).isEmpty)
        #expect(StoryExperienceContext.sections(character: marcus(), progress: [progress(["experience.ML11": true, "experience.ML22": true])]).isEmpty)
        #expect(StoryExperienceContext.sections(character: marcus(main: false), progress: [progress(["experience.ML11": true])]).isEmpty)
    }

    @Test("只承接已走路径，并尊重遗忘，不把候选时间和拒绝写成新约定")
    func concretePathAndForgetting() {
        let context = StoryExperienceContext.sections(character: marcus(), progress: [progress(["experience.ML22": true])]).joined()
        #expect(context.contains("unless they reopen planning"))
        #expect(!context.contains("joking about a song"))
        let offered = StoryExperienceContext.sections(character: marcus(), progress: [progress(["experience.ML21": true])]).joined()
        #expect(offered.contains("had not chosen either"))
        #expect(StoryExperienceContext.sections(character: marcus(), progress: [progress(["experience.ML22": true])],
            after: Date(timeIntervalSince1970: 101)).isEmpty)
    }

    @Test("新版经历优先按完成时间承接，中间版仍可回忆且不串入其他路径")
    func revisedAndOlderExperiences() {
        let older = progress(["experience.ML11": true])
        let revised = StoryProgressDTO(storyID: "departures_city_newyork_v3", currentNodeID: nil,
            flags: ["experience.ML322": true], completedAt: Date(timeIntervalSince1970: 200))
        let context = StoryExperienceContext.sections(character: marcus(), progress: [older, revised]).joined()
        #expect(context.contains("unless they reopen planning"))
        #expect(!context.contains("humming a song"))
        #expect(!context.contains("joking about a song"))
        #expect(StoryExperienceContext.sections(character: marcus(), progress: [older]).joined()
            .contains("joking about a song"))
        #expect(StoryExperienceContext.sections(character: marcus(), progress: [older, revised],
            after: Date(timeIntervalSince1970: 201)).isEmpty)
        #expect(StoryExperienceContext.sourceIDs(for: marcus()).count == 2)
    }
}
