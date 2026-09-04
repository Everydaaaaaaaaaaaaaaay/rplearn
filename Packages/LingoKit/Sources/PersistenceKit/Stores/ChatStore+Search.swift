import Foundation
import SwiftData

extension ChatStore {
    /// 在该角色的全部会话中检索消息。当前数据量先使用端侧包含匹配；接口保持分页上限，便于后续替换 FTS。
    public func searchMessageResults(
        characterID: UUID,
        query: String,
        limit: Int = 100
    ) throws -> [ChatMessageSearchResultDTO] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, limit > 0 else { return [] }
        guard let character = try modelContext.fetch(
            FetchDescriptor<CharacterEntity>(predicate: #Predicate { $0.characterID == characterID })
        ).first else {
            throw ChatError.characterNotFound
        }
        return character.conversations.flatMap { conversation in
            conversation.messages
                .filter { $0.text.localizedCaseInsensitiveContains(normalized) }
                .map {
                    ChatMessageSearchResultDTO(
                        conversationID: conversation.conversationID,
                        isArchivedConversation: conversation.isArchived,
                        message: dto(from: $0)
                    )
                }
        }
        .sorted {
            if $0.message.createdAt == $1.message.createdAt {
                return $0.message.orderIndex > $1.message.orderIndex
            }
            return $0.message.createdAt > $1.message.createdAt
        }
        .prefix(min(limit, 500))
        .map { $0 }
    }

    public func searchMessages(
        characterID: UUID,
        query: String,
        limit: Int = 100
    ) throws -> [MessageDTO] {
        try searchMessageResults(characterID: characterID, query: query, limit: limit)
            .map(\.message)
    }
}
