import Foundation

/// 会话列表行摘要。
public struct ConversationSummaryDTO: Sendable, Equatable, Identifiable {
    public var conversationID: UUID
    public var characterID: UUID
    public var characterName: String
    public var avatarAssetName: String?
    public var lastMessageText: String
    public var lastMessageAt: Date
    public var lastMessageRole: MessageRole?
    public var lastMessageKind: MessageKind?
    public var isPinned: Bool
    public var lastReadAt: Date?
    /// 用于端内计算该会话的实际未读消息数，不参与持久化；始终按时间升序。
    public private(set) var assistantMessageDates: [Date]

    public var id: UUID { conversationID }

    public init(
        conversationID: UUID,
        characterID: UUID,
        characterName: String,
        avatarAssetName: String?,
        lastMessageText: String,
        lastMessageAt: Date,
        lastMessageRole: MessageRole? = nil,
        lastMessageKind: MessageKind? = nil,
        isPinned: Bool = false,
        lastReadAt: Date? = nil,
        assistantMessageDates: [Date] = []
    ) {
        self.conversationID = conversationID
        self.characterID = characterID
        self.characterName = characterName
        self.avatarAssetName = avatarAssetName
        self.lastMessageText = lastMessageText
        self.lastMessageAt = lastMessageAt
        self.lastMessageRole = lastMessageRole
        self.lastMessageKind = lastMessageKind
        self.isPinned = isPinned
        self.lastReadAt = lastReadAt
        self.assistantMessageDates = assistantMessageDates.sorted()
    }

    public var unreadCount: Int {
        guard lastMessageRole == .assistant else { return 0 }
        let readAt = lastReadAt ?? .distantPast
        return assistantMessageDates.lazy.filter { $0 > readAt }.count
    }
}

/// 一条聊天检索命中，携带所属会话以便定位当前或历史上下文。
public struct ChatMessageSearchResultDTO: Sendable, Equatable, Identifiable {
    public let conversationID: UUID
    public let isArchivedConversation: Bool
    public let message: MessageDTO

    public var id: UUID { message.id }

    public init(
        conversationID: UUID,
        isArchivedConversation: Bool,
        message: MessageDTO
    ) {
        self.conversationID = conversationID
        self.isArchivedConversation = isArchivedConversation
        self.message = message
    }
}
