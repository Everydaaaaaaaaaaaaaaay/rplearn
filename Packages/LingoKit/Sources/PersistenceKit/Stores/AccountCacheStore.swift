import SwiftData

/// 检查账号缓存是否足以离线启动，并兼容清理旧版共享数据库。
/// 新版账号切换通过独立数据库完成，不会删除其他账号的离线数据。
@ModelActor
public actor AccountCacheStore {
    public func hasCachedProfile() throws -> Bool {
        var descriptor = FetchDescriptor<UserProfileEntity>()
        descriptor.fetchLimit = 1
        return try !modelContext.fetch(descriptor).isEmpty
    }

    public func clearAll() throws {
        try modelContext.delete(model: VoiceMediaUploadEntity.self)
        try modelContext.delete(model: VoiceMediaLinkEntity.self)
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
