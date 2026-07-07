import Foundation
import Testing
@testable import PersistenceKit

@Suite("RosterStore")
struct RosterStoreTests {
    private func makeStore() throws -> RosterStore {
        RosterStore(modelContainer: try ModelContainerFactory.makeContainer(inMemory: true))
    }

    private func sampleCard(name: String, regionID: String = "london") -> CharacterCard {
        CharacterCard(
            name: name,
            age: 24,
            gender: .male,
            nationality: "British",
            regionID: regionID,
            occupation: "bookseller",
            hobbies: ["football"],
            appearance: "brown hair",
            personality: "witty"
        )
    }

    @Test("主角色导入幂等，且默认进好友列表")
    func importIdempotent() async throws {
        let store = try makeStore()
        let cards = [sampleCard(name: "A"), sampleCard(name: "B"), sampleCard(name: "C")]
        try await store.importMainCharactersIfNeeded(cards: cards)
        try await store.importMainCharactersIfNeeded(cards: cards)
        let all = try await store.allCharacters()
        #expect(all.count == 3)
        #expect(all.allSatisfy { $0.isMainCharacter && $0.isFriend })
        // 主角色不占好友位
        #expect(try await store.occupiedFriendSlots() == 0)
    }

    @Test("好友位校验：满员抛错，主角色不受限")
    func friendSlots() async throws {
        let store = try makeStore()
        let first = try await store.addCharacter(card: sampleCard(name: "P1"), difficulty: .junior3, isFriend: false)
        let second = try await store.addCharacter(card: sampleCard(name: "P2"), difficulty: .junior3, isFriend: false)

        try await store.makeFriend(characterID: first, slotLimit: 1)
        await #expect(throws: RosterStore.RosterError.friendSlotsFull) {
            try await store.makeFriend(characterID: second, slotLimit: 1)
        }
        // 重复加好友不报错（幂等）
        try await store.makeFriend(characterID: first, slotLimit: 1)
    }

    @Test("角色卡 JSON 往返完整")
    func cardRoundTrip() async throws {
        let store = try makeStore()
        var card = sampleCard(name: "Round")
        card.speechStyle = "loves saying mate"
        card.background = "grew up in Kent"
        let id = try await store.addCharacter(card: card, difficulty: .senior1, isFriend: true)
        let fetched = try await store.character(id: id)
        #expect(fetched?.card == card)
        #expect(fetched?.difficultyLevel == .senior1)
    }
}
