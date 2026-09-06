import XCTest
@testable import PersistenceKit

final class ActivityConversationTests: XCTestCase {
    func testBecomingFriendsPromotesTheSameEncounterConversation() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let roster = RosterStore(modelContainer: container)
        let chat = ChatStore(modelContainer: container)
        let card = CharacterCard(name: "Alex", age: 53, gender: .male, nationality: "British", regionID: "london",
            occupation: "engineer", hobbies: [], appearance: "", personality: "reserved")
        let person = try await roster.addCharacter(card: card, difficulty: .junior3, isFriend: false)
        try await chat.appendActivityLineIfNeeded(messageID: UUID(), characterID: person, role: .assistant,
            text: "Let's keep in touch.", translation: "保持联系。", context: "咖啡馆")
        let before = try await chat.openConversation(characterID: person)
        XCTAssertTrue(before.isEncounterSession)
        try await roster.makeFriend(characterID: person, slotLimit: 5)
        let after = try await chat.openConversation(characterID: person)
        XCTAssertEqual(before.id, after.id)
        XCTAssertFalse(after.isEncounterSession)
        let lines = try await chat.messages(conversationID: after.id)
        XCTAssertEqual(lines.map(\.text), ["Let's keep in touch."])
    }

    func testActivityLinesReuseConversationKeepFriendAndPersistMemoryIdempotently() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let roster = RosterStore(modelContainer: container)
        let chat = ChatStore(modelContainer: container)
        let memory = MemoryStore(modelContainer: container)
        let card = CharacterCard(name: "Alex", age: 53, gender: .male, nationality: "British", regionID: "london",
            occupation: "engineer", hobbies: ["烘焙"], appearance: "", personality: "reserved")
        let person = try await roster.addCharacter(card: card, difficulty: .junior3, isFriend: true)
        let conversation = try await chat.openConversation(characterID: person)
        try await chat.appendMessage(conversationID: conversation.id, role: .user, text: "An earlier chat.")
        let messageID = UUID()
        for _ in 0..<3 {
            try await chat.appendActivityLineIfNeeded(messageID: messageID, characterID: person, role: .assistant,
                text: "Hello again.", translation: "又见面了。", context: "咖啡馆，询问共用座位。")
        }
        let sameConversation = try await chat.openConversation(characterID: person)
        XCTAssertEqual(sameConversation.id, conversation.id)
        let messages = try await chat.messages(conversationID: conversation.id)
        XCTAssertEqual(messages.map(\.text), ["An earlier chat.", "Hello again."])
        let facts = try await memory.memories(characterID: person, tier: .short)
        XCTAssertEqual(facts.count, 1)
        XCTAssertEqual(facts.first?.source, .activity)
        XCTAssertTrue(facts.first?.content.contains("咖啡馆") == true)
        let character = try await roster.character(id: person)
        XCTAssertEqual(character?.card, card)
        XCTAssertEqual(character?.isFriend, true)
        do {
            try await chat.appendActivityLineIfNeeded(messageID: messageID, characterID: person, role: .assistant,
                text: "A different line.", translation: "不同内容", context: "咖啡馆")
            XCTFail("Retry must not overwrite an existing line")
        } catch ChatStore.ChatError.activityIdentityConflict {}
        let after = try await chat.messages(conversationID: conversation.id)
        XCTAssertEqual(after.count, 2)
    }

    func testPrivateStoresDoNotShareEncounterHistory() async throws {
        let first = try ModelContainerFactory.makeContainer(inMemory: true)
        let second = try ModelContainerFactory.makeContainer(inMemory: true)
        let id = UUID()
        let card = CharacterCard(name: "Alex", age: 53, gender: .male, nationality: "British", regionID: "london",
            occupation: "engineer", hobbies: [], appearance: "", personality: "reserved")
        for container in [first, second] {
            _ = try await RosterStore(modelContainer: container).addCharacter(characterID: id, card: card,
                difficulty: .junior3, isFriend: false)
        }
        try await ChatStore(modelContainer: first).appendActivityLineIfNeeded(messageID: UUID(), characterID: id,
            role: .user, text: "Is this seat taken?", translation: "有人吗？", context: "咖啡馆")
        let other = try await ChatStore(modelContainer: second).recentMessages(characterID: id)
        XCTAssertTrue(other.isEmpty)
    }
}
