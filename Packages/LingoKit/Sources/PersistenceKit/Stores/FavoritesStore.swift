import Foundation
import SwiftData

/// 收藏语句快照。
public struct FavoriteDTO: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var sentence: String
    public var sourceMessageID: UUID?
    public var characterName: String
    public var translationZh: String?
    public var createdAt: Date

    public init(
        id: UUID,
        sentence: String,
        sourceMessageID: UUID?,
        characterName: String,
        translationZh: String?,
        createdAt: Date
    ) {
        self.id = id
        self.sentence = sentence
        self.sourceMessageID = sourceMessageID
        self.characterName = characterName
        self.translationZh = translationZh
        self.createdAt = createdAt
    }
}

/// 收藏夹仓库。收藏为句子快照（弱引用消息，消息删除不影响收藏）。
@ModelActor
public actor FavoritesStore {
    @discardableResult
    public func add(
        sentence: String,
        sourceMessageID: UUID?,
        characterName: String,
        translationZh: String? = nil
    ) throws -> FavoriteDTO {
        // 同一来源消息重复收藏时幂等返回已有收藏。
        if let sourceMessageID,
           let existing = try fetchBySource(sourceMessageID) {
            return Self.dto(from: existing)
        }
        let entity = FavoriteEntity(
            sentence: sentence,
            sourceMessageID: sourceMessageID,
            characterName: characterName,
            translationZh: translationZh
        )
        modelContext.insert(entity)
        try modelContext.save()
        return Self.dto(from: entity)
    }

    public func all() throws -> [FavoriteDTO] {
        var descriptor = FetchDescriptor<FavoriteEntity>()
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        return try modelContext.fetch(descriptor).map(Self.dto(from:))
    }

    public func remove(id: UUID) throws {
        guard let entity = try modelContext.fetch(
            FetchDescriptor<FavoriteEntity>(predicate: #Predicate { $0.favoriteID == id })
        ).first else { return }
        modelContext.delete(entity)
        try modelContext.save()
    }

    public func setTranslation(id: UUID, translationZh: String) throws {
        guard let entity = try modelContext.fetch(
            FetchDescriptor<FavoriteEntity>(predicate: #Predicate { $0.favoriteID == id })
        ).first else { return }
        entity.translationZh = translationZh
        try modelContext.save()
    }

    public func isFavorited(sourceMessageID: UUID) throws -> Bool {
        try fetchBySource(sourceMessageID) != nil
    }

    private func fetchBySource(_ sourceMessageID: UUID) throws -> FavoriteEntity? {
        try modelContext.fetch(
            FetchDescriptor<FavoriteEntity>(predicate: #Predicate { $0.sourceMessageID == sourceMessageID })
        ).first
    }

    static func dto(from entity: FavoriteEntity) -> FavoriteDTO {
        FavoriteDTO(
            id: entity.favoriteID,
            sentence: entity.sentence,
            sourceMessageID: entity.sourceMessageID,
            characterName: entity.characterName,
            translationZh: entity.translationZh,
            createdAt: entity.createdAt
        )
    }
}
