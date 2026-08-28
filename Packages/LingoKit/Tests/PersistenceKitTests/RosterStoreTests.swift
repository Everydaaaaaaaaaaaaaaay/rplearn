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

    @Test("主角色导入幂等，选择与剧情相遇后才进入好友列表")
    func importIdempotent() async throws {
        let store = try makeStore()
        let cards = [
            sampleCard(name: "A", regionID: "london"),
            sampleCard(name: "B", regionID: "melbourne"),
            sampleCard(name: "C", regionID: "newyork"),
        ]
        try await store.importMainCharactersIfNeeded(cards: cards)
        try await store.importMainCharactersIfNeeded(cards: cards)
        var all = try await store.allCharacters()
        #expect(all.count == 3)
        #expect(all.allSatisfy { $0.isMainCharacter && !$0.isFriend })

        try await store.configureMainCharacters(
            unlockedRegionIDs: ["melbourne"],
            difficulty: .senior2
        )
        all = try await store.allCharacters()
        #expect(all.first { $0.card.regionID == "melbourne" }?.isFriend == true)
        #expect(all.filter(\.isFriend).count == 1)
        #expect(all.allSatisfy { $0.difficultyLevel == .senior2 })

        try await store.unlockMainCharacter(regionID: "newyork")
        #expect(try await store.friends().count == 2)
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

    @Test("特别关心状态可持久化、可取消且重复设置幂等")
    func favoriteContact() async throws {
        let store = try makeStore()
        let id = try await store.addCharacter(
            card: sampleCard(name: "Favorite"),
            difficulty: .junior3,
            isFriend: true
        )

        #expect(try await store.character(id: id)?.isFavorite == false)
        try await store.setFavorite(characterID: id, isFavorite: true)
        try await store.setFavorite(characterID: id, isFavorite: true)
        #expect(try await store.character(id: id)?.isFavorite == true)

        try await store.setFavorite(characterID: id, isFavorite: false)
        #expect(try await store.character(id: id)?.isFavorite == false)
    }
}
