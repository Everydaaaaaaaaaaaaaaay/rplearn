import Foundation
import PersistenceKit
import Testing
@testable import ChatFeature

@Suite("Conversation read state")
struct ConversationReadStateTests {
    @Test("已读时间排除已看过的助手消息")
    func countsOnlyAssistantMessagesAfterReadCursor() {
        let dates = [100.0, 200.0, 300.0].map(Date.init(timeIntervalSince1970:))
        #expect(
            ConversationReadState.unreadCount(
                assistantMessageDates: dates,
                lastReadAt: Date(timeIntervalSince1970: 200)
            ) == 1
        )
        #expect(
            !ConversationReadState.isUnread(
                lastMessageAt: dates[1],
                lastMessageRole: .assistant,
                lastReadAt: dates[1]
            )
        )
        #expect(
            !ConversationReadState.isUnread(
                lastMessageAt: dates[2],
                lastMessageRole: .user,
                lastReadAt: nil
            )
        )
    }

    @Test("摘要统一排序消息时间并保存置顶和已读状态")
    func summaryOwnsSyncedListState() {
        let dates = [300.0, 100.0, 200.0].map(Date.init(timeIntervalSince1970:))
        let value = ConversationSummaryDTO(
            conversationID: UUID(),
            characterID: UUID(),
            characterName: "Friend",
            avatarAssetName: nil,
            lastMessageText: "Hello",
            lastMessageAt: dates[0],
            lastMessageRole: .assistant,
            isPinned: true,
            lastReadAt: dates[2],
            assistantMessageDates: dates
        )

        #expect(value.assistantMessageDates == dates.sorted())
        #expect(value.isPinned)
        #expect(value.unreadCount == 1)
    }

    @Test("总数只统计好友会话")
    func totalOnlyIncludesFriends() {
        let friend = character()
        let stranger = character()
        let summaries = [
            summary(characterID: friend.id, messageDate: Date(timeIntervalSince1970: 100)),
            summary(characterID: stranger.id, messageDate: Date(timeIntervalSince1970: 200)),
        ]

        #expect(
            ConversationReadState.totalUnreadCount(
                friends: [friend],
                summaries: summaries
            ) == 1
        )
    }

    private func character() -> CharacterDTO {
        CharacterDTO(
            id: UUID(),
            card: CharacterCard(
                name: "Friend",
                age: 25,
                gender: .other,
                nationality: "Test",
                regionID: "test",
                occupation: "tester",
                hobbies: [],
                appearance: "",
                personality: ""
            ),
            difficultyLevel: .junior3,
            isMainCharacter: false,
            isFriend: true,
            metAt: .now
        )
    }

    private func summary(characterID: UUID, messageDate: Date) -> ConversationSummaryDTO {
        ConversationSummaryDTO(
            conversationID: UUID(),
            characterID: characterID,
            characterName: "Friend",
            avatarAssetName: nil,
            lastMessageText: "Hello",
            lastMessageAt: messageDate,
            lastMessageRole: .assistant,
            assistantMessageDates: [messageDate]
        )
    }
}
