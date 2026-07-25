import Foundation
import SwiftData

/// 记忆条目快照。
public struct MemoryDTO: Sendable, Equatable, Identifiable {
    public var id: PersistentIdentifier
    public var tier: MemoryTier
    public var content: String
    public var importance: Int
    public var sourceUpToIndex: Int
    public var createdAt: Date
}

/// 分级记忆仓库。
@ModelActor
public actor MemoryStore {
    public enum MemoryError: Error {
        case characterNotFound
    }

    public struct NewMemory: Sendable {
        public var content: String
        public var importance: Int

        public init(content: String, importance: Int) {
            self.content = content
            self.importance = importance
        }
    }

    /// 追加一批记忆条目。
    public func addMemories(
        characterID: UUID,
        tier: MemoryTier,
        facts: [NewMemory],
        sourceUpToIndex: Int
    ) throws {
        guard let character = try modelContext.fetch(
            FetchDescriptor<CharacterEntity>(predicate: #Predicate { $0.characterID == characterID })
        ).first else {
            throw MemoryError.characterNotFound
        }
        for fact in facts {
            let entity = MemoryEntity(
                tierRaw: tier.rawValue,
                content: fact.content,
                importance: min(5, max(1, fact.importance)),
                sourceUpToIndex: sourceUpToIndex
            )
            entity.character = character
            modelContext.insert(entity)
        }
        try modelContext.save()
    }

    /// 某角色某层的全部记忆（按时间升序）。
    public func memories(characterID: UUID, tier: MemoryTier) throws -> [MemoryDTO] {
        let tierRaw = tier.rawValue
        let predicate = #Predicate<MemoryEntity> { entity in
            entity.tierRaw == tierRaw && entity.character?.characterID == characterID
        }
        let descriptor = FetchDescriptor<MemoryEntity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor).map { entity in
            MemoryDTO(
                id: entity.persistentModelID,
                tier: MemoryTier(rawValue: entity.tierRaw) ?? .short,
                content: entity.content,
                importance: entity.importance,
                sourceUpToIndex: entity.sourceUpToIndex,
                createdAt: entity.createdAt
            )
        }
    }

    public func count(characterID: UUID, tier: MemoryTier) throws -> Int {
        let tierRaw = tier.rawValue
        let predicate = #Predicate<MemoryEntity> { entity in
            entity.tierRaw == tierRaw && entity.character?.characterID == characterID
        }
        return try modelContext.fetchCount(FetchDescriptor<MemoryEntity>(predicate: predicate))
    }

    public func deleteMemories(ids: [PersistentIdentifier]) throws {
        for id in ids {
            if let entity = modelContext.model(for: id) as? MemoryEntity {
                modelContext.delete(entity)
            }
        }
        try modelContext.save()
    }
}
