import Foundation
import PersistenceKit

/// 会话已读与置顶的轻量本地状态；不改 SwiftData schema。
public enum ConversationReadState {
    public static let didChange = Notification.Name("LingoTripConversationReadStateDidChange")

    private static let readKey = "lingotrip.conversation.lastRead"
    private static let pinnedKey = "lingotrip.conversation.pinned"

    public static func isUnread(
        conversationID: UUID,
        lastMessageAt: Date,
        lastMessageRole: MessageRole?
    ) -> Bool {
        isUnread(
            conversationID: conversationID,
            lastMessageAt: lastMessageAt,
            lastMessageRole: lastMessageRole,
            defaults: .standard
        )
    }

    static func isUnread(
        conversationID: UUID,
        lastMessageAt: Date,
        lastMessageRole: MessageRole?,
        defaults: UserDefaults
    ) -> Bool {
        guard lastMessageRole == .assistant else { return false }
        return lastReadAt(conversationID: conversationID, defaults: defaults) < lastMessageAt
    }

    public static func markRead(conversationID: UUID, at date: Date = .now) {
        markRead(conversationID: conversationID, at: date, defaults: .standard)
    }

    static func markRead(conversationID: UUID, at date: Date, defaults: UserDefaults) {
        var values = defaults.dictionary(forKey: readKey) as? [String: Double] ?? [:]
        let key = conversationID.uuidString
        values[key] = max(values[key] ?? 0, date.timeIntervalSince1970)
        defaults.set(values, forKey: readKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    public static func isPinned(_ conversationID: UUID) -> Bool {
        pinnedIDs.contains(conversationID.uuidString)
    }

    public static func togglePinned(_ conversationID: UUID) {
        var ids = pinnedIDs
        if ids.contains(conversationID.uuidString) {
            ids.remove(conversationID.uuidString)
        } else {
            ids.insert(conversationID.uuidString)
        }
        UserDefaults.standard.set(Array(ids), forKey: pinnedKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    private static func lastReadAt(conversationID: UUID, defaults: UserDefaults) -> Date {
        let values = defaults.dictionary(forKey: readKey) as? [String: Double] ?? [:]
        return Date(timeIntervalSince1970: values[conversationID.uuidString] ?? 0)
    }

    private static var pinnedIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: pinnedKey) ?? [])
    }
}
