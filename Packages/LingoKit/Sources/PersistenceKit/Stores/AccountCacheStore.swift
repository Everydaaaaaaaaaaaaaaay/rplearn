import SwiftData

/// 清除本机账号域数据。账号切换时宁可重新同步，也不能让前一账号的数据短暂可见。
@ModelActor
public actor AccountCacheStore {
    public func clearAll() throws {
        try modelContext.delete(model: ContentOutboxEntity.self)
        try modelContext.delete(model: ContentSyncMetadataEntity.self)
        try modelContext.delete(model: ContentSyncOwnerEntity.self)
        try modelContext.delete(model: QuizRecordEntity.self)
        try modelContext.delete(model: MessageEntity.self)
        try modelContext.delete(model: ConversationEntity.self)
        try modelContext.delete(model: MemoryEntity.self)
        try modelContext.delete(model: CharacterEntity.self)
        try modelContext.delete(model: FavoriteEntity.self)
        try modelContext.delete(model: ItemEntity.self)
        try modelContext.delete(model: TicketStubEntity.self)
        try modelContext.delete(model: StoryProgressEntity.self)
        try modelContext.delete(model: UserProfileEntity.self)
        try modelContext.save()
    }
}
