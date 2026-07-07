import Foundation
import Testing
@testable import PersistenceKit

@Suite("FavoritesStore")
struct FavoritesStoreTests {
    private func makeStore() throws -> FavoritesStore {
        FavoritesStore(modelContainer: try ModelContainerFactory.makeContainer(inMemory: true))
    }

    @Test("收藏、翻阅、删除")
    func crud() async throws {
        let store = try makeStore()
        let added = try await store.add(
            sentence: "Fancy a pint later?",
            sourceMessageID: UUID(),
            characterName: "Oliver Bennett",
            translationZh: "待会儿去喝一杯？"
        )
        var all = try await store.all()
        #expect(all.count == 1)
        #expect(all.first?.sentence == "Fancy a pint later?")
        #expect(all.first?.translationZh == "待会儿去喝一杯？")

        try await store.remove(id: added.id)
        all = try await store.all()
        #expect(all.isEmpty)
    }

    @Test("同一消息重复收藏幂等")
    func idempotentBySource() async throws {
        let store = try makeStore()
        let messageID = UUID()
        let first = try await store.add(sentence: "hi", sourceMessageID: messageID, characterName: "A")
        let second = try await store.add(sentence: "hi", sourceMessageID: messageID, characterName: "A")
        #expect(first.id == second.id)
        #expect(try await store.all().count == 1)
        #expect(try await store.isFavorited(sourceMessageID: messageID))
    }

    @Test("补充翻译缓存")
    func setTranslation() async throws {
        let store = try makeStore()
        let added = try await store.add(sentence: "no worries", sourceMessageID: nil, characterName: "Ruby")
        try await store.setTranslation(id: added.id, translationZh: "没事儿")
        #expect(try await store.all().first?.translationZh == "没事儿")
    }

    @Test("按收藏时间倒序")
    func sortedByDate() async throws {
        let store = try makeStore()
        _ = try await store.add(sentence: "first", sourceMessageID: nil, characterName: "A")
        try await Task.sleep(for: .milliseconds(20))
        _ = try await store.add(sentence: "second", sourceMessageID: nil, characterName: "A")
        let all = try await store.all()
        #expect(all.map(\.sentence) == ["second", "first"])
    }
}
