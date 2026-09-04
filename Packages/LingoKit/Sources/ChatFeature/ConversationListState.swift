import Foundation
import PersistenceKit

/// 会话列表状态的纯计算与刷新通知。权威值存放在 SwiftData 会话实体并参与账号同步。
public enum ConversationReadState {
    public static let didChange = Notification.Name("LingoTripConversationReadStateDidChange")

    public static func notifyChange() {
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    public static func isUnread(
        lastMessageAt: Date,
        lastMessageRole: MessageRole?,
        lastReadAt: Date?
    ) -> Bool {
        lastMessageRole == .assistant && (lastReadAt ?? .distantPast) < lastMessageAt
    }

    public static func unreadCount(
        assistantMessageDates: [Date],
        lastReadAt: Date?
    ) -> Int {
        let readAt = lastReadAt ?? .distantPast
        var lowerBound = assistantMessageDates.startIndex
        var upperBound = assistantMessageDates.endIndex
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if assistantMessageDates[middle] <= readAt {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return assistantMessageDates.count - lowerBound
    }

    public static func totalUnreadCount(
        friends: [CharacterDTO],
        summaries: [ConversationSummaryDTO]
    ) -> Int {
        let friendIDs = Set(friends.map(\.id))
        return summaries.reduce(into: 0) { total, summary in
            guard friendIDs.contains(summary.characterID) else { return }
            total += summary.unreadCount
        }
    }
}
