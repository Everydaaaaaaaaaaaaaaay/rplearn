import Foundation
import PersistenceKit
import Testing
@testable import ChatFeature

@Suite("Conversation read state")
struct ConversationReadStateTests {
    @Test("退出会话时可见的助手消息保持已读")
    func visibleAssistantMessageRemainsReadAfterExit() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let conversationID = UUID()
        let replyDate = Date(timeIntervalSince1970: 100)

        #expect(
            ConversationReadState.isUnread(
                conversationID: conversationID,
                lastMessageAt: replyDate,
                lastMessageRole: .assistant,
                defaults: defaults
            )
        )

        ConversationReadState.markRead(
            conversationID: conversationID,
            at: replyDate,
            defaults: defaults
        )

        #expect(
            !ConversationReadState.isUnread(
                conversationID: conversationID,
                lastMessageAt: replyDate,
                lastMessageRole: .assistant,
                defaults: defaults
            )
        )
    }

    @Test("较旧的标记不会让已读状态倒退")
    func olderReadMarkerDoesNotRegressState() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let conversationID = UUID()
        ConversationReadState.markRead(
            conversationID: conversationID,
            at: Date(timeIntervalSince1970: 200),
            defaults: defaults
        )
        ConversationReadState.markRead(
            conversationID: conversationID,
            at: Date(timeIntervalSince1970: 100),
            defaults: defaults
        )

        #expect(
            !ConversationReadState.isUnread(
                conversationID: conversationID,
                lastMessageAt: Date(timeIntervalSince1970: 150),
                lastMessageRole: .assistant,
                defaults: defaults
            )
        )
    }

    @Test("按最后阅读时间统计实际未读助手消息数")
    func countsUnreadAssistantMessages() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let conversationID = UUID()
        let dates = [100.0, 200.0, 300.0].map(Date.init(timeIntervalSince1970:))
        ConversationReadState.markRead(
            conversationID: conversationID,
            at: Date(timeIntervalSince1970: 200),
            defaults: defaults
        )

        #expect(
            ConversationReadState.unreadCount(
                conversationID: conversationID,
                assistantMessageDates: dates,
                defaults: defaults
            ) == 1
        )
    }

    @Test("摘要统一排序消息时间并排除恰好已读的消息")
    func summarySortsDatesForBinaryUnreadLookup() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let conversationID = UUID()
        let dates = [300.0, 100.0, 200.0].map(Date.init(timeIntervalSince1970:))
        let value = ConversationSummaryDTO(
            conversationID: conversationID,
            characterID: UUID(),
            characterName: "Friend",
            avatarAssetName: nil,
            lastMessageText: "Hello",
            lastMessageAt: dates[0],
            lastMessageRole: .assistant,
            assistantMessageDates: dates
        )
        ConversationReadState.markRead(
            conversationID: conversationID,
            at: Date(timeIntervalSince1970: 200),
            defaults: defaults
        )

        #expect(value.assistantMessageDates == dates.sorted())
        #expect(
            ConversationReadState.unreadCount(
                conversationID: conversationID,
                assistantMessageDates: value.assistantMessageDates,
                defaults: defaults
            ) == 1
        )
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

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "ConversationReadStateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
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
