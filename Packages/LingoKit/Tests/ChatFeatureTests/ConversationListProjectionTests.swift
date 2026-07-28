import Foundation
import Testing
@testable import ChatFeature
import PersistenceKit

@Suite("Conversation list projection")
struct ConversationListProjectionTests {
    @Test("尚未开聊的初始好友仍出现在消息列表")
    func includesFriendsWithoutConversation() {
        let friends = [
            character(id: UUID(), name: "Oliver"),
            character(id: UUID(), name: "Ruby"),
            character(id: UUID(), name: "Marcus"),
        ]

        let rows = ConversationListProjection.rows(
            friends: friends,
            summaries: []
        )

        #expect(rows.map(\.character.id) == friends.map(\.id))
        #expect(rows.allSatisfy { $0.summary == nil })
    }

    @Test("已有会话的好友不会产生占位重复行")
    func conversationDoesNotDuplicateFriend() {
        let friend = character(id: UUID(), name: "Ruby")
        let summary = ConversationSummaryDTO(
            conversationID: UUID(),
            characterID: friend.id,
            characterName: friend.card.name,
            avatarAssetName: friend.card.avatarAssetName,
            lastMessageText: "G'day!",
            lastMessageAt: .now
        )

        let rows = ConversationListProjection.rows(
            friends: [friend],
            summaries: [summary]
        )

        #expect(rows.count == 1)
        #expect(rows.first?.summary == summary)
    }

    @Test("创建会话前后列表行 ID 保持稳定")
    func rowIdentityStaysStableWhenConversationIsCreated() {
        let friend = character(id: UUID(), name: "Oliver")
        let placeholder = ConversationListProjection.rows(
            friends: [friend],
            summaries: []
        ).first
        let summary = ConversationSummaryDTO(
            conversationID: UUID(),
            characterID: friend.id,
            characterName: friend.card.name,
            avatarAssetName: friend.card.avatarAssetName,
            lastMessageText: "",
            lastMessageAt: .now
        )
        let conversation = ConversationListProjection.rows(
            friends: [friend],
            summaries: [summary]
        ).first

        #expect(placeholder?.id == friend.id)
        #expect(conversation?.id == friend.id)
        #expect(placeholder?.id == conversation?.id)
    }

    private func character(id: UUID, name: String) -> CharacterDTO {
        CharacterDTO(
            id: id,
            card: CharacterCard(
                name: name,
                age: 24,
                gender: .other,
                nationality: "Test",
                regionID: "london",
                occupation: "friend",
                hobbies: [],
                appearance: "",
                personality: "",
                avatarAssetName: nil
            ),
            difficultyLevel: .junior3,
            isMainCharacter: true,
            isFriend: true,
            metAt: .now
        )
    }
}
