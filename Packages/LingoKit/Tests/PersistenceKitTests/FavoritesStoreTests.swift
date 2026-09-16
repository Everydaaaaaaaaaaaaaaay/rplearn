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

    @Test("单词收藏忽略大小写并保持幂等")
    func wordFavoriteIsNormalizedAndIdempotent() async throws {
        let store = try makeStore()
        let first = try #require(
            try await store.addWord("  Seeking ", translationZh: "寻找；寻求")
        )
        let second = try #require(
            try await store.addWord("seeking", translationZh: "不应覆盖")
        )

        #expect(first.id == second.id)
        #expect(first.kind == .word)
        #expect(first.sentence == "seeking")
        #expect(try await store.isWordFavorited("SEEKING"))
        #expect(try await store.all().count == 1)
    }

    @Test("单词收藏可切换并与旧句子收藏共存")
    func togglesWordWithoutRemovingLegacySentence() async throws {
        let store = try makeStore()
        _ = try await store.add(
            sentence: "I am seeking a quiet place.",
            sourceMessageID: UUID(),
            characterName: "Oliver"
        )

        #expect(try await store.toggleWord("seeking", translationZh: "寻找"))
        #expect(try await store.all().map(\.kind).contains(.word))
        #expect(!(try await store.toggleWord("seeking")))
        #expect(try await store.all().map(\.kind) == [.sentence])
    }

    @Test("同一消息的多个词与句子收藏互不冲突")
    func sourceWordsDoNotCollideWithSentence() async throws {
        let store = try makeStore()
        let source = UUID()
        let word = try #require(try await store.addWord("Quiet", sourceMessageID: source))
        _ = try await store.addWord("place", sourceMessageID: source)
        #expect(!(try await store.isFavorited(sourceMessageID: source)))
        let sentence = try await store.add(sentence: "A quiet place.", sourceMessageID: source, characterName: "Ruby")
        #expect(sentence.kind == .sentence)
        #expect(sentence.id != word.id)
        #expect(try await store.all().count == 3)
        #expect(try await store.isWordFavorited("QUIET"))
        #expect(!(try await store.toggleWord("quiet")))
        #expect(try await store.isFavorited(sourceMessageID: source))
        #expect(try await store.isWordFavorited("place"))
    }

    @Test("旧单词可补来源且重复遇见不覆盖原语境")
    func enrichesLegacySourceOnlyOnce() async throws {
        let store = try makeStore()
        let legacy = try #require(try await store.addWord("quiet", translationZh: "安静的"))
        let source = UUID()
        let enriched = try #require(try await store.addWord("QUIET", sourceMessageID: source))
        let repeated = try #require(try await store.addWord("quiet", sourceMessageID: UUID()))
        #expect(enriched.id == legacy.id)
        #expect(repeated.sourceMessageID == source)
        #expect(repeated.translationZh == "安静的")
        #expect(try await store.all().count == 1)
    }

    @Test("带来源单词同步至新设备后仍可去重与取消收藏")
    func sourceSurvivesSync() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let sync = ContentSyncStore(modelContainer: container)
        let store = FavoritesStore(modelContainer: container)
        let owner = UUID()
        try await sync.activateOwner(userID: owner)
        let source = UUID()
        #expect(try await store.toggleWord("Quiet", sourceMessageID: source))
        let pending = try #require(try await sync.takePending().first)
        let payload = try #require(pending.payloadJSON)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ContentFavoritePayload.self, from: Data(payload.utf8))
        #expect(decoded.sourceMessageId == source)
        let otherContainer = try ModelContainerFactory.makeContainer(inMemory: true)
        let otherSync = ContentSyncStore(modelContainer: otherContainer)
        let otherStore = FavoritesStore(modelContainer: otherContainer)
        try await otherSync.activateOwner(userID: owner)
        try await otherSync.apply(records: [RemoteContentRecord(
            createdAt: .now, deletedAt: nil, parentID: nil, payloadJSON: payload,
            resourceID: pending.resourceID, resourceType: .favorite, updatedAt: .now, version: 1
        )], nextCursor: "1")
        let restored = try #require(try await otherStore.addWord("QUIET"))
        #expect(restored.sourceMessageID == source)
        #expect(try await otherStore.all().count == 1)
        #expect(!(try await otherStore.toggleWord("quiet")))
        #expect(try await otherStore.all().isEmpty)
    }

    @Test("语法点收藏按稳定 ID 幂等并保留展示快照")
    func grammarPointFavoriteIsIdempotent() async throws {
        let store = try makeStore()
        let first = try #require(
            try await store.addGrammarPoint(
                id: "present-perfect",
                title: "现在完成时",
                explanationZh: "表示过去发生且与现在有关的动作。"
            )
        )
        let second = try #require(
            try await store.addGrammarPoint(
                id: "present-perfect",
                title: "不会覆盖",
                explanationZh: "不会覆盖"
            )
        )

        #expect(first.id == second.id)
        #expect(first.kind == .grammarPoint)
        #expect(first.referenceID == "present-perfect")
        #expect(first.sentence == "现在完成时")
        #expect(first.translationZh == "表示过去发生且与现在有关的动作。")
        #expect(try await store.isGrammarPointFavorited(id: "present-perfect"))
        #expect(try await store.all().count == 1)
    }

    @Test("语法点收藏可切换且不影响单词收藏")
    func togglesGrammarPointWithoutRemovingWord() async throws {
        let store = try makeStore()
        _ = try await store.addWord("ready", translationZh: "准备好的")

        #expect(
            try await store.toggleGrammarPoint(
                id: "be-ready-to",
                title: "be ready to do",
                explanationZh: "准备做某事"
            )
        )
        #expect(Set(try await store.all().map(\.kind)) == [.word, .grammarPoint])
        #expect(
            !(try await store.toggleGrammarPoint(
                id: "be-ready-to",
                title: "be ready to do"
            ))
        )
        #expect(try await store.all().map(\.kind) == [.word])
    }
}
