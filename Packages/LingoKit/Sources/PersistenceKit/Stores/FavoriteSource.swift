import Foundation
import SwiftData

/// Read-only context from the original message; never invent a source for legacy words.
public struct FavoriteSourceDTO: Sendable, Equatable {
    public let messageID: UUID
    public let speaker: String
    public let text: String
    public let translationZh: String?
}

extension FavoritesStore {
    public func source(for favoriteID: UUID) throws -> FavoriteSourceDTO? {
        let favorites = FetchDescriptor<FavoriteEntity>(predicate: #Predicate { $0.favoriteID == favoriteID })
        guard let sourceID = try modelContext.fetch(favorites).first?.sourceMessageID else { return nil }
        let messages = FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageID == sourceID })
        guard let message = try modelContext.fetch(messages).first,
              !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !message.isInterrupted else { return nil }
        return FavoriteSourceDTO(
            messageID: message.messageID,
            speaker: message.roleRaw == "user" ? "你" : (message.conversation?.character?.name ?? "旅伴"),
            text: message.text,
            translationZh: message.translationZh
        )
    }
}
