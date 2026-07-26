import Foundation
import SwiftData

public enum FavoriteKind: String, Sendable, Equatable {
    case word
    case sentence
}

/// 收藏快照。保留旧版句子收藏，新版入口只新增单词收藏。
public struct FavoriteDTO: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var kind: FavoriteKind
    public var sentence: String
    public var sourceMessageID: UUID?
    public var characterName: String
    public var translationZh: String?
    public var createdAt: Date

    public init(
        id: UUID,
        kind: FavoriteKind = .sentence,
        sentence: String,
        sourceMessageID: UUID?,
        characterName: String,
        translationZh: String?,
        createdAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.sentence = sentence
        self.sourceMessageID = sourceMessageID
        self.characterName = characterName
        self.translationZh = translationZh
        self.createdAt = createdAt
    }
}

/// 收藏夹仓库。保留旧版句子快照，并以规范化单词作为新版收藏的幂等键。
@ModelActor
public actor FavoritesStore {
    private static let wordCollectionMarker = "__word__"

    /// 收藏一个单词；同一单词忽略大小写并保持幂等。
    @discardableResult
    public func addWord(_ rawWord: String, translationZh: String? = nil) throws -> FavoriteDTO? {
        let word = Self.normalizedWord(rawWord)
        guard !word.isEmpty else { return nil }
        if let existing = try fetchWord(word) {
            return Self.dto(from: existing)
        }
        let entity = FavoriteEntity(
            sentence: word,
            sourceMessageID: nil,
            characterName: Self.wordCollectionMarker,
            translationZh: translationZh
        )
        modelContext.insert(entity)
        try journal(entity)
        try modelContext.save()
        return Self.dto(from: entity)
    }

    /// 切换单词收藏，返回切换后的收藏状态。
    public func toggleWord(_ rawWord: String, translationZh: String? = nil) throws -> Bool {
        let word = Self.normalizedWord(rawWord)
        guard !word.isEmpty else { return false }
        if let existing = try fetchWord(word) {
            try ContentMutationJournal.delete(
                in: modelContext,
                resourceType: .favorite,
                resourceID: existing.favoriteID.uuidString.lowercased()
            )
            modelContext.delete(existing)
            try modelContext.save()
            return false
        }
        _ = try addWord(word, translationZh: translationZh)
        return true
    }

    public func isWordFavorited(_ rawWord: String) throws -> Bool {
        let word = Self.normalizedWord(rawWord)
        guard !word.isEmpty else { return false }
        return try fetchWord(word) != nil
    }

    /// 旧版句子收藏写入接口，仅用于兼容已有调用和数据测试。
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
        try journal(entity)
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
        try ContentMutationJournal.delete(
            in: modelContext,
            resourceType: .favorite,
            resourceID: entity.favoriteID.uuidString.lowercased()
        )
        modelContext.delete(entity)
        try modelContext.save()
    }

    public func setTranslation(id: UUID, translationZh: String) throws {
        guard let entity = try modelContext.fetch(
            FetchDescriptor<FavoriteEntity>(predicate: #Predicate { $0.favoriteID == id })
        ).first else { return }
        entity.translationZh = translationZh
        try journal(entity)
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

    private func fetchWord(_ word: String) throws -> FavoriteEntity? {
        let marker = Self.wordCollectionMarker
        return try modelContext.fetch(
            FetchDescriptor<FavoriteEntity>(
                predicate: #Predicate {
                    $0.sourceMessageID == nil
                        && $0.characterName == marker
                        && $0.sentence == word
                }
            )
        ).first
    }

    private static func normalizedWord(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func journal(_ entity: FavoriteEntity) throws {
        try ContentMutationJournal.upsert(
            in: modelContext,
            resourceType: .favorite,
            resourceID: entity.favoriteID.uuidString.lowercased(),
            parentID: nil,
            payloadJSON: try ContentMutationJournal.encode(
                ContentFavoritePayload(
                    characterName: entity.characterName,
                    createdAt: entity.createdAt,
                    sentence: entity.sentence,
                    sourceMessageId: entity.sourceMessageID,
                    translationZh: entity.translationZh
                )
            )
        )
    }

    static func dto(from entity: FavoriteEntity) -> FavoriteDTO {
        FavoriteDTO(
            id: entity.favoriteID,
            kind: entity.characterName == wordCollectionMarker ? .word : .sentence,
            sentence: entity.sentence,
            sourceMessageID: entity.sourceMessageID,
            characterName: entity.characterName,
            translationZh: entity.translationZh,
            createdAt: entity.createdAt
        )
    }
}
