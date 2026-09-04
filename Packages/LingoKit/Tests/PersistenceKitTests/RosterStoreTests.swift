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

    @Test("特别关心保存失败时返回明确错误")
    func favoriteSaveFailure() async throws {
        let store = try makeStore()

        await #expect(throws: RosterStore.RosterError.characterNotFound) {
            try await store.setFavorite(characterID: UUID(), isFavorite: true)
        }
    }

    @Test("关系状态持久化并使用版本避免后台结果互相覆盖")
    func relationshipStateUsesOptimisticRevision() async throws {
        let store = try makeStore()
        let id = try await store.addCharacter(
            card: sampleCard(name: "Bond"),
            difficulty: .junior3,
            isFriend: true
        )
        let initial = try #require(try await store.character(id: id)?.relationship)
        #expect(initial.affinity == 10)

        var updated = initial
        updated.affinity = 24
        updated.revision = initial.revision + 1
        #expect(
            try await store.updateRelationship(
                characterID: id,
                snapshot: updated,
                expectedRevision: initial.revision
            )
        )
        #expect(try await store.character(id: id)?.relationship.affinity == 24)

        var stale = initial
        stale.affinity = 99
        #expect(
            try await !store.updateRelationship(
                characterID: id,
                snapshot: stale,
                expectedRevision: initial.revision
            )
        )
        #expect(try await store.character(id: id)?.relationship.affinity == 24)
    }

    @Test("旅伴号稳定、带校验位并支持精确查找")
    func travelerIDIsStableAndSearchable() async throws {
        let store = try makeStore()
        let id = try await store.addCharacter(
            card: sampleCard(name: "Traveler ID"),
            difficulty: .junior3,
            isFriend: true
        )
        let character = try #require(try await store.character(id: id))

        #expect(character.travelerID == TravelerIDGenerator.make(from: id))
        #expect(TravelerIDGenerator.isValid(character.travelerID))
        #expect(try await store.character(travelerID: character.travelerID)?.id == id)
        #expect(try await store.character(travelerID: "00000000000") == nil)
    }

    @Test("移除好友保留资料，主线重建不会静默加回，用户可主动恢复")
    func removedMainCharacterRequiresExplicitRestore() async throws {
        let store = try makeStore()
        var card = sampleCard(name: "Oliver")
        card.avatarAssetName = "avatar_oliver"
        try await store.importMainCharactersIfNeeded(cards: [card])
        try await store.configureMainCharacters(unlockedRegionIDs: ["london"], difficulty: .junior3)
        let id = try #require(try await store.friends().first?.id)

        try await store.removeFriend(characterID: id)
        #expect(try await store.friends().isEmpty)
        #expect(try await store.formerContacts().map(\.id) == [id])

        try await store.configureMainCharacters(unlockedRegionIDs: ["london"], difficulty: .advanced)
        let stillRemoved = try #require(try await store.character(id: id))
        #expect(!stillRemoved.isFriend)
        #expect(stillRemoved.contactStatus == .removed)
        #expect(stillRemoved.difficultyLevel == .advanced)

        try await store.makeFriend(characterID: id, slotLimit: 0)
        let restored = try #require(try await store.character(id: id))
        #expect(restored.isFriend)
        #expect(restored.contactStatus == .friend)
        #expect(try await store.formerContacts().isEmpty)
    }

    @Test("联系人私有偏好与人格成长独立持久化")
    func privatePreferencesAndGrowthPersist() async throws {
        let store = try makeStore()
        let id = try await store.addCharacter(
            card: sampleCard(name: "Private Branch"),
            difficulty: .junior3,
            isFriend: true
        )
        let mutedUntil = Date.now.addingTimeInterval(3_600)
        try await store.updateContactPreferences(
            characterID: id,
            preferences: ContactPreferences(
                remarkName: "  小书商  ",
                privateNote: "  喜欢旧书店  ",
                proactiveMessagesEnabled: false,
                mutedUntil: mutedUntil
            )
        )
        let arc = CharacterGrowthArc(
            trait: .patience,
            direction: .increase,
            progress: 0.2,
            stage: .experimenting,
            reasonZh: "开始先听完别人的想法"
        )
        _ = try await store.mutateGrowth(characterID: id) { current in
            CharacterGrowthSnapshot(revision: current.revision + 1, arcs: [arc])
        }

        let character = try #require(try await store.character(id: id))
        #expect(character.displayName == "小书商")
        #expect(character.contactPreferences.privateNote == "喜欢旧书店")
        #expect(!character.contactPreferences.proactiveMessagesEnabled)
        #expect(character.contactPreferences.mutedUntil == mutedUntil)
        let storedArc = try #require(character.growth.arcs.first)
        #expect(character.growth.arcs.count == 1)
        #expect(storedArc.id == arc.id)
        #expect(storedArc.trait == arc.trait)
        #expect(storedArc.direction == arc.direction)
        #expect(storedArc.progress == arc.progress)
        #expect(storedArc.stage == arc.stage)
        #expect(storedArc.reasonZh == arc.reasonZh)
        #expect(character.card.personality == "witty")
    }
}
