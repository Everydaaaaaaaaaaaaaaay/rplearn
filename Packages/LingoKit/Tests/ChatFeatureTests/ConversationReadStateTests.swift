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

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "ConversationReadStateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
