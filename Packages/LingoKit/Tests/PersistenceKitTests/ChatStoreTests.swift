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

    @Test("同一角色重复 open 返回同一会话")
    func openConversationReuses() async throws {
        let (chat, roster) = try makeStores()
        let characterID = try await addCharacter(roster)
        let first = try await chat.openConversation(characterID: characterID)
        let second = try await chat.openConversation(characterID: characterID)
        #expect(first.id == second.id)
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

    @Test("到期主动消息按事件编号幂等写入")
    func proactiveMessageIsIdempotent() async throws {
        let (chat, roster) = try makeStores()
        let characterID = try await addCharacter(roster)
        let eventID = UUID()

        let first = try await chat.appendProactiveMessageIfNeeded(
            messageID: eventID,
            characterID: characterID,
            text: "What made you smile today?"
        )
        let duplicate = try await chat.appendProactiveMessageIfNeeded(
            messageID: eventID,
            characterID: characterID,
            text: "Duplicate"
        )

        let summary = try #require(try await chat.conversationSummaries().first)
        let messages = try await chat.messages(conversationID: summary.conversationID)
        #expect(first?.id == eventID)
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

    @Test("assistant 消息递增 turnCount 与 turnsSinceQuiz")
    func turnCounting() async throws {
        let (chat, roster) = try makeStores()
        let characterID = try await addCharacter(roster)
        let conversation = try await chat.openConversation(characterID: characterID)

        try await chat.appendMessage(conversationID: conversation.id, role: .user, text: "hi")
        try await chat.appendMessage(conversationID: conversation.id, role: .assistant, text: "hey")
        try await chat.appendMessage(conversationID: conversation.id, role: .assistant, text: "again")

        let updated = try await chat.conversation(id: conversation.id)
        #expect(updated?.turnCount == 2)
        #expect(updated?.turnsSinceQuiz == 2)
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
        #expect(updated?.turnsSinceQuiz == 1)
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
        #expect(updated?.turnsSinceQuiz == 1)
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
}
