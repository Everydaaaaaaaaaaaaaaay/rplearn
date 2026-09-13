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
    public var record: MemoryRecord? = nil
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
    public func memories(characterID: UUID, tier: MemoryTier, includingArchived: Bool = false, includingForgotten: Bool = false) throws -> [MemoryDTO] {
        let tierRaw = tier.rawValue
        let predicate = #Predicate<MemoryEntity> { entity in
            entity.tierRaw == tierRaw && entity.character?.characterID == characterID
        }
        let descriptor = FetchDescriptor<MemoryEntity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor).compactMap { entity in
            let record = MemoryRecord.decode(entity.content)
            guard includingForgotten || record?.forgotten != true,
                  includingArchived || record?.archived != true else { return nil }
            return MemoryDTO(
                id: entity.persistentModelID,
                tier: MemoryTier(rawValue: entity.tierRaw) ?? .short,
                source: MemorySource(rawValue: entity.sourceRaw) ?? .chat,
                content: record?.text ?? entity.content,
                importance: entity.importance,
                sourceUpToIndex: entity.sourceUpToIndex,
                createdAt: record?.observedAt ?? entity.createdAt,
                record: record
            )
        }
    }

    public func count(characterID: UUID, tier: MemoryTier) throws -> Int {
        try memories(characterID: characterID, tier: tier).count
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


    public func applyFacts(characterID: UUID, records: [MemoryRecord], sourceIndex: Int) throws {
        guard let character = try modelContext.fetch(FetchDescriptor<CharacterEntity>(
            predicate: #Predicate { $0.characterID == characterID })).first else { throw MemoryError.characterNotFound }
        let entries = try modelContext.fetch(FetchDescriptor<MemoryEntity>(
            predicate: #Predicate { $0.character?.characterID == characterID }))
        do {
            let cutoff = try extractionCutoff(characterID: characterID)
            var seenKeys = Set<String>()
            for record in records.prefix(2) {
                guard seenKeys.insert(record.key).inserted, cutoff == nil || record.observedAt > cutoff! else { continue }
                // User edits and forgetting are authoritative, including late model results.
                let matches = entries.filter { MemoryRecord.decode($0.content)?.key == record.key }
                if matches.contains(where: {
                    guard let prior = MemoryRecord.decode($0.content) else { return false }
                    return prior.forgotten || prior.edited || prior.observedAt >= record.observedAt
                }) { continue }
                let entity = matches.first ?? MemoryEntity(tierRaw: MemoryTier.long.rawValue,
                    sourceRaw: MemorySource.chat.rawValue, content: "", importance: 4, sourceUpToIndex: sourceIndex)
                if matches.isEmpty { entity.character = character; modelContext.insert(entity) }
                entity.content = try record.encoded()
                entity.sourceUpToIndex = sourceIndex
                try modelContext.save()
                try journal(entity)
            }
            try modelContext.save()
        } catch { modelContext.rollback(); throw error }
    }

    public func updateMemory(id: PersistentIdentifier, text: String? = nil, forgotten: Bool = false, archived: Bool = false, status: String? = nil) throws {
        guard let entity = modelContext.model(for: id) as? MemoryEntity else { return }
        var record = MemoryRecord.decode(entity.content) ?? MemoryRecord(
            key: "legacy." + ContentMutationJournal.persistentKey(entity.persistentModelID),
            text: entity.content, observedAt: entity.createdAt)
        if let text {
            record.text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
            record.edited = true
            record.evidence = nil
            record.messageID = nil
            record.eventDate = nil
            record.observedAt = .now
        }
        if let status { record.status = status; record.edited = true; record.observedAt = .now }
        if forgotten { record.forgotten = true; record.observedAt = .now; record.text = ""; record.evidence = nil; record.eventDate = nil; record.messageID = nil }
        record.archived = archived
        entity.content = try record.encoded()
        try journal(entity)
        try modelContext.save()
        if forgotten || text != nil || status != nil {
            NotificationCenter.default.post(name: .memoryKnowledgeDidChange, object: nil)
        }
    }

    /// Conservative privacy barrier: pre-forgetting conversations are never re-extracted.
    public func extractionCutoff(characterID: UUID) throws -> Date? {
        try MemoryTier.allCases.flatMap {
            try memories(characterID: characterID, tier: $0, includingArchived: true, includingForgotten: true)
        }.filter { $0.record?.forgotten == true || $0.record?.edited == true }.map(\.createdAt).max()
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
