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
    }
}
