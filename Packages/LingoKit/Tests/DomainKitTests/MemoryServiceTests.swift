import Foundation
import LLMKit
import Testing
@testable import DomainKit
@testable import PersistenceKit

@Suite("MemoryService")
struct MemoryServiceTests {
    private struct Fixture {
        let chatStore: ChatStore
        let memoryStore: MemoryStore
        let economyStore: EconomyStore
        let characterID: UUID
        let conversationID: UUID
    }

    private func makeFixture() async throws -> Fixture {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let roster = RosterStore(modelContainer: container)
        let chatStore = ChatStore(modelContainer: container)
        let memoryStore = MemoryStore(modelContainer: container)
        let economyStore = EconomyStore(modelContainer: container)
        let characterID = try await roster.addCharacter(
            card: CharacterCard(
                name: "Memo",
                age: 20,
                gender: .other,
                nationality: "British",
                regionID: "london",
                occupation: "tester",
                hobbies: [],
                appearance: "-",
                personality: "-"
            ),
            difficulty: .junior3,
            isFriend: true
        )
        let conversation = try await chatStore.openConversation(characterID: characterID)
        return Fixture(
            chatStore: chatStore,
            memoryStore: memoryStore,
            economyStore: economyStore,
            characterID: characterID,
            conversationID: conversation.id
        )
    }

    private func seedShorts(_ fixture: Fixture, count: Int) async throws {
        let facts = (0..<count).map { MemoryStore.NewMemory(content: "short fact \($0)", importance: ($0 % 5) + 1) }
        try await fixture.memoryStore.addMemories(
            characterID: fixture.characterID, tier: .short, facts: facts, sourceUpToIndex: 0
        )
    }

    private func fill(_ fixture: Fixture, messageCount: Int) async throws {
        for index in 0..<messageCount {
            try await fixture.chatStore.appendMessage(
                conversationID: fixture.conversationID,
                role: index % 2 == 0 ? .user : .assistant,
                text: "message \(index)"
            )
        }
    }

    private let factsJSON = #"{"memories":[{"content":"Friend supports Arsenal","importance":3},{"content":"Friend plans a trip to Paris","importance":4}]}"#

    @Test("达到 24 条未压缩消息触发压缩并推进游标")
    func triggersAtThreshold() async throws {
        let fixture = try await makeFixture()
        try await fill(fixture, messageCount: 25)
        let mock = MockLLMProvider(completeHandler: { request in
            #expect(request.tier == .fast)
            return self.factsJSON
        })
        let service = MemoryService(llm: mock, chatStore: fixture.chatStore, memoryStore: fixture.memoryStore)

        await service.compressIfNeeded(conversationID: fixture.conversationID, characterName: "Memo")

        let memories = try await fixture.memoryStore.memories(characterID: fixture.characterID, tier: .short)
        #expect(memories.count == 2)
        #expect(memories.first?.content == "Friend supports Arsenal")
        let conversation = try await fixture.chatStore.conversation(id: fixture.conversationID)
        #expect(conversation?.lastSummarizedMessageIndex == 16)
    }

    @Test("未达阈值不触发")
    func belowThresholdNoop() async throws {
        let fixture = try await makeFixture()
        try await fill(fixture, messageCount: 10)
        let mock = MockLLMProvider(completeHandler: { _ in
            Issue.record("不应调用 LLM")
            return self.factsJSON
        })
        let service = MemoryService(llm: mock, chatStore: fixture.chatStore, memoryStore: fixture.memoryStore)
        await service.compressIfNeeded(conversationID: fixture.conversationID, characterName: "Memo")
        #expect(try await fixture.memoryStore.count(characterID: fixture.characterID, tier: .short) == 0)
    }

    @Test("LLM 失败不推进游标（下次重试）")
    func failureKeepsCursor() async throws {
        let fixture = try await makeFixture()
        try await fill(fixture, messageCount: 25)
        let mock = MockLLMProvider(completeHandler: { _ in
            throw LLMError.http(status: 500, message: "boom")
        })
        let service = MemoryService(llm: mock, chatStore: fixture.chatStore, memoryStore: fixture.memoryStore)
        await service.compressIfNeeded(conversationID: fixture.conversationID, characterName: "Memo")

        let conversation = try await fixture.chatStore.conversation(id: fixture.conversationID)
        #expect(conversation?.lastSummarizedMessageIndex == 0)
        #expect(try await fixture.memoryStore.count(characterID: fixture.characterID, tier: .short) == 0)
    }

    @Test("token 超预算 70% 也触发")
    func tokenBudgetTrigger() async throws {
        let fixture = try await makeFixture()
        // 4 条长消息，远超 200 token 预算的 70%
        for index in 0..<4 {
            try await fixture.chatStore.appendMessage(
                conversationID: fixture.conversationID,
                role: .user,
                text: String(repeating: "long message \(index) ", count: 60)
            )
        }
        let mock = MockLLMProvider(completeHandler: { _ in self.factsJSON })
        let service = MemoryService(
            llm: mock,
            chatStore: fixture.chatStore,
            memoryStore: fixture.memoryStore,
            config: .init(tokenBudget: 200)
        )
        await service.compressIfNeeded(conversationID: fixture.conversationID, characterName: "Memo")
        #expect(try await fixture.memoryStore.count(characterID: fixture.characterID, tier: .short) == 2)
    }

    @Test("记忆段落注入格式")
    func injectionFormat() async throws {
        let fixture = try await makeFixture()
        try await fixture.memoryStore.addMemories(
            characterID: fixture.characterID,
            tier: .short,
            facts: [.init(content: "Friend likes cats", importance: 2)],
            sourceUpToIndex: 16
        )
        let mock = MockLLMProvider()
        let service = MemoryService(llm: mock, chatStore: fixture.chatStore, memoryStore: fixture.memoryStore)
        let sections = await service.memorySections(characterID: fixture.characterID)
        #expect(sections.count == 1)
        #expect(sections.first?.contains("- Friend likes cats") == true)
        #expect(sections.first?.hasPrefix("[Recent things") == true)

        // 无记忆时为空
        let empty = await service.memorySections(characterID: UUID())
        #expect(empty.isEmpty)
    }

    @Test("注入包含 long（长期）与 short/mid（近期）两段")
    func injectionTiers() async throws {
        let fixture = try await makeFixture()
        try await fixture.memoryStore.addMemories(
            characterID: fixture.characterID, tier: .long,
            facts: [.init(content: "Friend is from Chengdu", importance: 5)], sourceUpToIndex: 0
        )
        try await fixture.memoryStore.addMemories(
            characterID: fixture.characterID, tier: .short,
            facts: [.init(content: "Friend went to a concert", importance: 2)], sourceUpToIndex: 0
        )
        let service = MemoryService(llm: MockLLMProvider(), chatStore: fixture.chatStore, memoryStore: fixture.memoryStore)
        let sections = await service.memorySections(characterID: fixture.characterID)
        #expect(sections.count == 2)
        #expect(sections[0].hasPrefix("[Long-term"))
        #expect(sections[0].contains("Friend is from Chengdu"))
        #expect(sections[1].hasPrefix("[Recent things"))
        #expect(sections[1].contains("Friend went to a concert"))
    }

    @Test("quota 随订阅变化")
    func quotaBySubscription() async throws {
        let fixture = try await makeFixture()
        let service = MemoryService(
            llm: MockLLMProvider(), chatStore: fixture.chatStore,
            memoryStore: fixture.memoryStore, economyStore: fixture.economyStore
        )
        // 默认 Free
        #expect(await service.quota() == EconomyService.memoryQuota(for: .free))
        _ = try await fixture.economyStore.updateProfile { $0.subscriptionTier = .pro }
        #expect(await service.quota() == EconomyService.memoryQuota(for: .pro))
    }

    @Test("short 超配额合并进 mid（Free shortMid=8）")
    func shortOverflowMergesToMid() async throws {
        let fixture = try await makeFixture()
        try await seedShorts(fixture, count: 12) // 溢出 4（≥3）
        let midJSON = #"{"memories":[{"content":"They chatted a lot about hobbies","importance":3}]}"#
        let mock = MockLLMProvider(completeHandler: { _ in midJSON })
        let service = MemoryService(
            llm: mock, chatStore: fixture.chatStore,
            memoryStore: fixture.memoryStore, economyStore: fixture.economyStore
        )
        await service.maintainTiers(characterID: fixture.characterID, characterName: "Memo")

        let shortCount = try await fixture.memoryStore.count(characterID: fixture.characterID, tier: .short)
        let mids = try await fixture.memoryStore.memories(characterID: fixture.characterID, tier: .mid)
        #expect(shortCount == 8) // 溢出的 4 条被合并删除
        #expect(mids.count == 1)
        #expect(mids.first?.content == "They chatted a lot about hobbies")
    }

    @Test("short 溢出不足 3 条不触发合并")
    func smallOverflowNoMerge() async throws {
        let fixture = try await makeFixture()
        try await seedShorts(fixture, count: 10) // 溢出 2（<3）
        let mock = MockLLMProvider(completeHandler: { _ in
            Issue.record("不应调用 LLM 合并")
            return "{}"
        })
        let service = MemoryService(
            llm: mock, chatStore: fixture.chatStore,
            memoryStore: fixture.memoryStore, economyStore: fixture.economyStore
        )
        await service.maintainTiers(characterID: fixture.characterID, characterName: "Memo")
        #expect(try await fixture.memoryStore.count(characterID: fixture.characterID, tier: .short) == 10)
        #expect(try await fixture.memoryStore.count(characterID: fixture.characterID, tier: .mid) == 0)
    }

    @Test("long 超配额按重要度裁剪（Free long=5）")
    func longPruneByImportance() async throws {
        let fixture = try await makeFixture()
        // 7 条 long，重要度 1..7 截断为 1..5
        let facts = (1...7).map { MemoryStore.NewMemory(content: "long \($0)", importance: $0) }
        try await fixture.memoryStore.addMemories(
            characterID: fixture.characterID, tier: .long, facts: facts, sourceUpToIndex: 0
        )
        let service = MemoryService(
            llm: MockLLMProvider(), chatStore: fixture.chatStore,
            memoryStore: fixture.memoryStore, economyStore: fixture.economyStore
        )
        await service.maintainTiers(characterID: fixture.characterID, characterName: "Memo")
        let longs = try await fixture.memoryStore.memories(characterID: fixture.characterID, tier: .long)
        #expect(longs.count == 5)
        // 最低重要度（1、2）被裁掉
        #expect(!longs.contains { $0.content == "long 1" })
        #expect(!longs.contains { $0.content == "long 2" })
        #expect(longs.contains { $0.content == "long 7" })
    }
}
