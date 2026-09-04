import Foundation
import SwiftData

extension ChatStore {
    /// 会话列表（消息 tab）：每个未归档会话一行。
    public func conversationSummaries() throws -> [ConversationSummaryDTO] {
        let conversations = try modelContext.fetch(
            FetchDescriptor<ConversationEntity>(predicate: #Predicate { !$0.isArchived })
        )
        return conversations.compactMap { conversation -> ConversationSummaryDTO? in
            guard let character = conversation.character else { return nil }
            var lastMessage: MessageEntity?
            var assistantMessageDates: [Date] = []
            assistantMessageDates.reserveCapacity(conversation.messages.count)
            for message in conversation.messages {
                if lastMessage == nil
                    || message.orderIndex > (lastMessage?.orderIndex ?? -1) {
                    lastMessage = message
                }
                if message.roleRaw == MessageRole.assistant.rawValue {
                    assistantMessageDates.append(message.createdAt)
                }
            }
            return ConversationSummaryDTO(
                conversationID: conversation.conversationID,
                characterID: character.characterID,
                characterName: character.name,
                avatarAssetName: character.avatarAssetName,
                lastMessageText: lastMessage?.text ?? "",
                lastMessageAt: conversation.lastMessageAt,
                lastMessageRole: lastMessage.flatMap { MessageRole(rawValue: $0.roleRaw) },
                lastMessageKind: lastMessage.flatMap { MessageKind(rawValue: $0.kindRaw) },
                isPinned: conversation.isPinned,
                lastReadAt: conversation.lastReadAt,
                assistantMessageDates: assistantMessageDates
            )
        }
        .sorted { $0.lastMessageAt > $1.lastMessageAt }
    }
}
