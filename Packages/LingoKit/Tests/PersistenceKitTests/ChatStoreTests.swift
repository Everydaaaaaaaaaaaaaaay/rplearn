import CoreKit
import Foundation
import Testing
@testable import PersistenceKit

@Suite("ChatStore")
struct ChatStoreTests {
    private func makeStores() throws -> (ChatStore, RosterStore) {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        return (ChatStore(modelContainer: container), RosterStore(modelContainer: container))
    }

    private func addCharacter(_ roster: RosterStore) async throws -> UUID {
        try await roster.addCharacter(
            card: CharacterCard(
                name: "Chat Partner",
                age: 22,
                gender: .female,
                nationality: "Australian",
                regionID: "melbourne",
                occupation: "barista",
                hobbies: ["surfing"],
                appearance: "blonde",
                personality: "sunny"
            ),
            difficulty: .junior3,
            isFriend: true
        )
    }



    @Test("学习来源与消息一起保存并进入真实同步发件箱")
    func learningOriginsPersistInOutbox() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let chat = ChatStore(modelContainer: container), roster = RosterStore(modelContainer: container)
        let sync = ContentSyncStore(modelContainer: container)
        try await sync.activateOwner(userID: UUID())
        let character = try await addCharacter(roster)
        let conversation = try await chat.openConversation(characterID: character)
        let origin = LearningChatOrigin.user(cycleID: UUID())
        let user = try await chat.appendMessage(conversationID: conversation.id, role: .user, text: "Hello", learningOrigin: origin)
        let source = LearningReplySource(context: .init(conversationID: conversation.id, userMessageID: user.id, cycleID: origin.cycleID), operationID: UUID())
        let replies = try await chat.appendAssistantReply(conversationID: conversation.id, texts: ["Hello!", "Welcome back."], learningSource: source)
        #expect(replies.map(\.learningOrigin) == [source.origin(index: 0, count: 2), source.origin(index: 1, count: 2)])
        let mutations = try await sync.takePending(limit: 50).filter { $0.resourceType == .message }
        #expect(mutations.count == 3)
        for mutation in mutations {
            let data = try #require(mutation.payloadJSON).data(using: .utf8)!
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let value = try #require(object["learningOrigin"])
            let decoded = try JSONDecoder().decode(LearningChatOrigin.self, from: JSONSerialization.data(withJSONObject: value))
            #expect(decoded.cycleID == origin.cycleID)
        }
        let restored = try await ChatStore(modelContainer: container).messages(conversationID: conversation.id)
        #expect(restored.map(\.learningOrigin) == [origin] + replies.map(\.learningOrigin))
    }

    @Test("同一角色重复 open 返回同一会话")
    func openConversationReuses() async throws {
        let (chat, roster) = try makeStores()
        let characterID = try await addCharacter(roster)
        let first = try await chat.openConversation(characterID: characterID)
        let second = try await chat.openConversation(characterID: characterID)
        #expect(first.id == second.id)
    }

    @Test("置顶与已读游标持久化且已读时间只前进")
    func persistsPinnedAndMonotonicReadCursor() async throws {
        let (chat, roster) = try makeStores()
        let characterID = try await addCharacter(roster)
        let conversation = try await chat.openConversation(characterID: characterID)
        let firstRead = Date(timeIntervalSince1970: 200)

        try await chat.setPinned(conversationID: conversation.id, isPinned: true)
        try await chat.markRead(conversationID: conversation.id, at: firstRead)
        try await chat.markRead(
            conversationID: conversation.id,
            at: Date(timeIntervalSince1970: 100)
        )

        let stored = try #require(try await chat.conversation(id: conversation.id))
        #expect(stored.isPinned)
        #expect(stored.lastReadAt == firstRead)
        let summary = try #require(try await chat.conversationSummaries().first)
        #expect(summary.isPinned)
        #expect(summary.lastReadAt == firstRead)
    }

    @Test("角色第一条主动消息只能写入一次")
    func initialMessageIsIdempotent() async throws {
        let (chat, roster) = try makeStores()
        let characterID = try await addCharacter(roster)

        #expect(try await chat.needsInitialMessage(characterID: characterID))
        let first = try await chat.appendInitialMessageIfNeeded(
            characterID: characterID,
            text: "What kind of music do you enjoy?"
        )
        let duplicate = try await chat.appendInitialMessageIfNeeded(
            characterID: characterID,
            text: "This should not be added."
        )

        let conversation = try #require(
            try await chat.conversationSummaries().first
        )
        let messages = try await chat.messages(conversationID: conversation.conversationID)
        #expect(first != nil)
        #expect(duplicate == nil)
        #expect(messages.map(\.text) == ["What kind of music do you enjoy?"])
        #expect(!(try await chat.needsInitialMessage(characterID: characterID)))
    }

    @Test("重新开场仍可读取归档会话中的近期话题")
    func recentMessagesIncludeArchivedConversation() async throws {
        let (chat, roster) = try makeStores()
        let characterID = try await addCharacter(roster)
        _ = try await chat.appendInitialMessageIfNeeded(
            characterID: characterID,
            text: "What kind of music do you enjoy?"
        )
        try await chat.archiveConversations(characterID: characterID)

        #expect(try await chat.needsInitialMessage(characterID: characterID))
        let recent = try await chat.recentMessages(characterID: characterID)
        #expect(recent.map(\.text) == ["What kind of music do you enjoy?"])
    }

    @Test("只允许替换尚未继续交流的矛盾开场白")
    func repairsOnlySoleInitialMessage() async throws {
        let (chat, roster) = try makeStores()
        let characterID = try await addCharacter(roster)
        let invalid = "You actually texted me. Am I dreaming?"
        _ = try await chat.appendInitialMessageIfNeeded(
            characterID: characterID,
            text: invalid
        )

        let repaired = try await chat.replaceSoleInitialMessageIfNeeded(
            characterID: characterID,
            matching: invalid,
            with: "Welcome to town. How was your trip?"
        )
        let conversation = try #require(try await chat.conversationSummaries().first)
        #expect(repaired?.text == "Welcome to town. How was your trip?")

        try await chat.appendMessage(
            conversationID: conversation.conversationID,
            role: .user,
            text: "It was great."
        )
        let refused = try await chat.replaceSoleInitialMessageIfNeeded(
            characterID: characterID,
            matching: "Welcome to town. How was your trip?",
            with: "This must not rewrite history."
        )
        #expect(refused == nil)
    }

    @Test("到期主动消息按事件编号幂等写入")
    func proactiveMessageIsIdempotent() async throws {
        let (chat, roster) = try makeStores()
        let characterID = try await addCharacter(roster)
        let eventID = UUID()
        let deliveredAt = Date(timeIntervalSince1970: 1_788_000_000)

        let first = try await chat.appendProactiveMessageIfNeeded(
            messageID: eventID,
            characterID: characterID,
            text: "What made you smile today?",
            createdAt: deliveredAt
        )
        let duplicate = try await chat.appendProactiveMessageIfNeeded(
            messageID: eventID,
            characterID: characterID,
            text: "Duplicate"
        )

        let summary = try #require(try await chat.conversationSummaries().first)
        let messages = try await chat.messages(conversationID: summary.conversationID)
        #expect(first?.id == eventID)
        #expect(first?.createdAt == deliveredAt)
        #expect(duplicate == nil)
        #expect(messages.map(\.text) == ["What made you smile today?"])
    }

    @Test("消息 orderIndex 单调递增，读取按序返回")
    func messageOrdering() async throws {
        let (chat, roster) = try makeStores()
        let characterID = try await addCharacter(roster)
        let conversation = try await chat.openConversation(characterID: characterID)

        try await chat.appendMessage(conversationID: conversation.id, role: .user, text: "hi")
        try await chat.appendMessage(conversationID: conversation.id, role: .assistant, text: "hey!")
        try await chat.appendMessage(conversationID: conversation.id, role: .user, text: "how are you")

        let messages = try await chat.messages(conversationID: conversation.id)
        #expect(messages.map(\.orderIndex) == [0, 1, 2])
        #expect(messages.map(\.text) == ["hi", "hey!", "how are you"])
    }

    @Test("回复提交前只认可时间线末端仍未回答的用户消息")
    func latestUnansweredMessageGuard() async throws {
        let (chat, roster) = try makeStores()
        let characterID = try await addCharacter(roster)
        let conversation = try await chat.openConversation(characterID: characterID)
        let first = try await chat.appendMessage(
            conversationID: conversation.id,
            role: .user,
            text: "First"
        )
        #expect(try await chat.isLatestUnansweredUserMessage(
            conversationID: conversation.id,
            messageID: first.id
        ))

        let second = try await chat.appendMessage(
            conversationID: conversation.id,
            role: .user,
            text: "Second"
        )
        #expect(!(try await chat.isLatestUnansweredUserMessage(
            conversationID: conversation.id,
            messageID: first.id
        )))
        #expect(try await chat.isLatestUnansweredUserMessage(
            conversationID: conversation.id,
            messageID: second.id
        ))

        let reply = try await chat.appendMessage(
            conversationID: conversation.id,
            role: .assistant,
            text: "Answer"
        )
        #expect(!(try await chat.isLatestUnansweredUserMessage(
            conversationID: conversation.id,
            messageID: second.id
        )))
        #expect(try await chat.isLatestUnansweredUserMessage(
            conversationID: conversation.id,
            messageID: second.id,
            replacingAssistantMessageID: reply.id
        ))
    }

    @Test("首气泡写入与末端消息校验保持原子")
    func firstReplyCommitGuardIsAtomic() async throws {
        let (chat, roster) = try makeStores()
        let characterID = try await addCharacter(roster)
        let conversation = try await chat.openConversation(characterID: characterID)
        let stale = try await chat.appendMessage(
            conversationID: conversation.id,
            role: .user,
            text: "Stale"
        )
        let current = try await chat.appendMessage(
            conversationID: conversation.id,
            role: .user,
            text: "Current"
        )

        let refused = try await chat.appendAssistantReplyPartIfCurrent(
            conversationID: conversation.id,
            text: "Must not appear",
            respondingToMessageID: stale.id
        )
        let inserted = try await chat.appendAssistantReplyPartIfCurrent(
            conversationID: conversation.id,
            text: "Current answer",
            respondingToMessageID: current.id
        )

        #expect(refused == nil)
        #expect(inserted?.text == "Current answer")
        #expect(try await chat.messages(conversationID: conversation.id).map(\.text) == [
            "Stale", "Current", "Current answer",
        ])
    }

    @Test("assistant 消息递增 turnCount")
    func turnCounting() async throws {
        let (chat, roster) = try makeStores()
        let characterID = try await addCharacter(roster)
        let conversation = try await chat.openConversation(characterID: characterID)

        try await chat.appendMessage(conversationID: conversation.id, role: .user, text: "hi")
        try await chat.appendMessage(conversationID: conversation.id, role: .assistant, text: "hey")
        try await chat.appendMessage(conversationID: conversation.id, role: .assistant, text: "again")

        let updated = try await chat.conversation(id: conversation.id)
        #expect(updated?.turnCount == 2)
    }

    @Test("同一角色回复可保存多条气泡但只计一个回合")
    func assistantReplyBurstCountsAsOneTurn() async throws {
        let (chat, roster) = try makeStores()
        let characterID = try await addCharacter(roster)
        let conversation = try await chat.openConversation(characterID: characterID)

        let inserted = try await chat.appendAssistantReply(
            conversationID: conversation.id,
            texts: ["hey mate", "you alright?"]
        )

        let updated = try await chat.conversation(id: conversation.id)
        #expect(inserted.map(\.text) == ["hey mate", "you alright?"])
        #expect(inserted.map(\.orderIndex) == [0, 1])
        #expect(updated?.turnCount == 1)
    }

    @Test("逐条送达的角色气泡仍只计一个回合")
    func pacedAssistantReplyCountsAsOneTurn() async throws {
        let (chat, roster) = try makeStores()
        let characterID = try await addCharacter(roster)
        let conversation = try await chat.openConversation(characterID: characterID)

        let first = try await chat.appendAssistantReplyPart(
            conversationID: conversation.id,
            text: "give me a sec",
            startsNewReply: true
        )
        let second = try await chat.appendAssistantReplyPart(
            conversationID: conversation.id,
            text: "yeah that works",
            startsNewReply: false
        )

        let updated = try await chat.conversation(id: conversation.id)
        #expect([first.text, second.text] == ["give me a sec", "yeah that works"])
        #expect(first.orderIndex == 0)
        #expect(second.orderIndex == 1)
        #expect(updated?.turnCount == 1)
    }

    @Test("流式定稿：更新文本与中断标记")
    func updateText() async throws {
        let (chat, roster) = try makeStores()
        let characterID = try await addCharacter(roster)
        let conversation = try await chat.openConversation(characterID: characterID)
        let message = try await chat.appendMessage(conversationID: conversation.id, role: .assistant, text: "")

        try await chat.updateMessageText(messageID: message.id, text: "partial", isInterrupted: true)
        let messages = try await chat.messages(conversationID: conversation.id)
        #expect(messages.first?.text == "partial")
        #expect(messages.first?.isInterrupted == true)
    }

    @Test("会话摘要按最近消息排序")
    func summaries() async throws {
        let (chat, roster) = try makeStores()
        let characterID = try await addCharacter(roster)
        let conversation = try await chat.openConversation(characterID: characterID)
        try await chat.appendMessage(conversationID: conversation.id, role: .assistant, text: "g'day!")

        let summaries = try await chat.conversationSummaries()
        #expect(summaries.count == 1)
        #expect(summaries.first?.characterName == "Chat Partner")
        #expect(summaries.first?.lastMessageText == "g'day!")
        #expect(summaries.first?.assistantMessageDates.count == 1)
    }

    @Test("聊天全文检索忽略大小写并按时间倒序")
    func searchesCharacterHistory() async throws {
        let (chat, roster) = try makeStores()
        let characterID = try await addCharacter(roster)
        let conversation = try await chat.openConversation(characterID: characterID)
        try await chat.appendMessage(conversationID: conversation.id, role: .user, text: "I found a small market.")
        try await chat.appendMessage(conversationID: conversation.id, role: .assistant, text: "The MARKET closes at six.")
        try await chat.appendMessage(conversationID: conversation.id, role: .user, text: "Thanks!")

        let results = try await chat.searchMessages(characterID: characterID, query: "market")
        #expect(results.map(\.text) == ["The MARKET closes at six.", "I found a small market."])
        #expect(try await chat.searchMessages(characterID: characterID, query: "   ").isEmpty)

        try await chat.archiveConversations(characterID: characterID)
        let current = try await chat.openConversation(characterID: characterID)
        try await chat.appendMessage(
            conversationID: current.id,
            role: .assistant,
            text: "A newer market opened nearby."
        )
        let contextualResults = try await chat.searchMessageResults(
            characterID: characterID,
            query: "market"
        )
        #expect(contextualResults.first?.conversationID == current.id)
        #expect(contextualResults.first?.isArchivedConversation == false)
        #expect(
            contextualResults.dropFirst().allSatisfy {
                $0.isArchivedConversation
            }
        )
    }

    @Test("清空聊天会返回本地语音文件并重置会话计数")
    func clearsHistoryAndReturnsVoiceFiles() async throws {
        let (chat, roster) = try makeStores()
        let characterID = try await addCharacter(roster)
        let conversation = try await chat.openConversation(characterID: characterID)
        try await chat.appendMessage(
            conversationID: conversation.id,
            role: .user,
            kind: .voice,
            text: "hello",
            audioFileName: "voice-test.caf",
            audioDuration: 1.2
        )
        try await chat.appendMessage(conversationID: conversation.id, role: .assistant, text: "Hi!")

        let files = try await chat.clearConversationHistory(characterID: characterID)
        #expect(files == ["voice-test.caf"])
        #expect(try await chat.messages(conversationID: conversation.id).isEmpty)
        let reset = try #require(try await chat.conversation(id: conversation.id))
        #expect(reset.turnCount == 0)
        #expect(reset.lastSummarizedMessageIndex == 0)
    }
}
