import Foundation
import Testing
@testable import PersistenceKit

@Suite("MemorySource")
struct MemorySourceTests {
    @Test("清空聊天派生记忆时保留剧情与活动经历")
    func deletesOnlyChatDerivedMemories() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let roster = RosterStore(modelContainer: container)
        let memory = MemoryStore(modelContainer: container)
        let characterID = try await roster.addCharacter(
            card: CharacterCard(
                name: "Memory Partner",
                age: 25,
                gender: .other,
                nationality: "British",
                regionID: "london",
                occupation: "designer",
                hobbies: ["walking"],
                appearance: "green coat",
                personality: "thoughtful"
            ),
            difficulty: .junior3,
            isFriend: true
        )

        try await memory.addMemories(
            characterID: characterID,
            tier: .long,
            facts: [.init(content: "User likes tea", importance: 3)],
            sourceUpToIndex: 2,
            source: .chat
        )
        try await memory.addMemories(
            characterID: characterID,
            tier: .long,
            facts: [.init(content: "They visited the old station together", importance: 4)],
            sourceUpToIndex: 0,
            source: .story
        )
        try await memory.addMemories(
            characterID: characterID,
            tier: .long,
            facts: [.init(content: "They browsed a market together", importance: 4)],
            sourceUpToIndex: 0,
            source: .activity
        )

        try await memory.deleteChatDerivedMemories(characterID: characterID)
        let remaining = try await memory.memories(characterID: characterID, tier: .long)
        #expect(Set(remaining.map(\.source)) == [.story, .activity])
        #expect(!remaining.map(\.content).contains("User likes tea"))
    }
}
