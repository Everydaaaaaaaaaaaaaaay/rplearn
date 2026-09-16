import Foundation
import SwiftData
import Testing
@testable import PersistenceKit

@Suite("FavoriteSource")
struct FavoriteSourceTests {
    @Test("原句读取保留用户身份和已有翻译，删除消息不丢收藏")
    @MainActor
    func contextAndDeletedMessage() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let message = MessageEntity(roleRaw: "user", text: "I found a quiet place.", orderIndex: 0,
                                    translationZh: "我找到了一个安静的地方。")
        container.mainContext.insert(message)
        try container.mainContext.save()
        let store = FavoritesStore(modelContainer: container)
        let favorite = try #require(try await store.addWord("quiet", sourceMessageID: message.messageID))
        let context = try #require(try await store.source(for: favorite.id))
        #expect(context.speaker == "你")
        #expect(context.text == "I found a quiet place.")
        #expect(context.translationZh == "我找到了一个安静的地方。")
        try await ChatStore(modelContainer: container).deleteMessage(messageID: message.messageID)
        #expect(try await store.source(for: favorite.id) == nil)
        #expect(try await store.isWordFavorited("quiet"))
    }

    @Test("旧收藏、未同步消息和中断消息不伪造原句")
    @MainActor
    func unavailableContext() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let store = FavoritesStore(modelContainer: container)
        let old = try #require(try await store.addWord("old"))
        let missing = try #require(try await store.addWord("missing", sourceMessageID: UUID()))
        let message = MessageEntity(roleRaw: "assistant", text: "Partial", orderIndex: 0, isInterrupted: true)
        container.mainContext.insert(message)
        try container.mainContext.save()
        let partial = try #require(try await store.addWord("partial", sourceMessageID: message.messageID))
        #expect(try await store.source(for: old.id) == nil)
        #expect(try await store.source(for: missing.id) == nil)
        #expect(try await store.source(for: partial.id) == nil)
        #expect(try await store.source(for: UUID()) == nil)
    }
}
