import Foundation
import SwiftData

/// 记忆条目快照。
public struct MemoryDTO: Sendable, Equatable, Identifiable {
    public var id: PersistentIdentifier
    public var tier: MemoryTier
    public var source: MemorySource
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
        sourceUpToIndex: Int,
        source: MemorySource = .chat
    ) throws {
        guard let character = try modelContext.fetch(
            FetchDescriptor<CharacterEntity>(predicate: #Predicate { $0.characterID == characterID })
        ).first else {
            throw MemoryError.characterNotFound
        }
        var inserted: [MemoryEntity] = []
        for fact in facts {
            let entity = MemoryEntity(
                tierRaw: tier.rawValue,
                sourceRaw: source.rawValue,
                content: fact.content,
                importance: min(5, max(1, fact.importance)),
                sourceUpToIndex: sourceUpToIndex
            )
            entity.character = character
            modelContext.insert(entity)
            inserted.append(entity)
        }
        try modelContext.save()
        for entity in inserted {
            try journal(entity)
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
                source: MemorySource(rawValue: entity.sourceRaw) ?? .chat,
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
                let localKey = ContentMutationJournal.persistentKey(
                    entity.persistentModelID
                )
                let resourceID = try ContentMutationJournal.resourceID(
                    in: modelContext,
                    resourceType: .memory,
                    localKey: localKey
                )
                try ContentMutationJournal.delete(
                    in: modelContext,
                    resourceType: .memory,
                    resourceID: resourceID
                )
                modelContext.delete(entity)
            }
        }
        try modelContext.save()
    }

    /// 清除聊天派生的私人记忆，保留剧情与共同活动形成的事实。
    public func deleteChatDerivedMemories(characterID: UUID) throws {
        let source = MemorySource.chat.rawValue
        let entities = try modelContext.fetch(
            FetchDescriptor<MemoryEntity>(predicate: #Predicate {
                $0.character?.characterID == characterID && $0.sourceRaw == source
            })
        )
        try deleteMemories(ids: entities.map(\.persistentModelID))
    }

    private func journal(_ entity: MemoryEntity) throws {
        guard let characterID = entity.character?.characterID else { return }
        let localKey = ContentMutationJournal.persistentKey(entity.persistentModelID)
        let resourceID = try ContentMutationJournal.resourceID(
            in: modelContext,
            resourceType: .memory,
            localKey: localKey
        )
        try ContentMutationJournal.upsert(
            in: modelContext,
            resourceType: .memory,
            resourceID: resourceID,
            parentID: characterID.uuidString.lowercased(),
            payloadJSON: try ContentMutationJournal.encode(
                ContentMemoryPayload(
                    content: entity.content,
                    createdAt: entity.createdAt,
                    importance: entity.importance,
                    source: entity.sourceRaw,
                    sourceUpToIndex: entity.sourceUpToIndex,
                    tier: entity.tierRaw
                )
            )
        )
    }
}
