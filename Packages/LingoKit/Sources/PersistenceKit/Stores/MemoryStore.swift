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

/// A durable change derived from a saved user message.
public struct CommittedChatMemoryChange: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case remembered, refined, corrected, updated
    }

    public let kind: Kind
    public let messageID: UUID
    public let memoryKey: String
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

    public func contextResourceIDs(for memories: [MemoryDTO]) throws -> [UUID] {
        try memories.compactMap { memory in
            guard modelContext.model(for: memory.id) is MemoryEntity else { return nil }
            return UUID(uuidString: try ContentMutationJournal.resourceID(in: modelContext, resourceType: .memory,
                localKey: ContentMutationJournal.persistentKey(memory.id)))
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


    @discardableResult
    public func applyFacts(
        characterID: UUID, records: [MemoryRecord], sourceIndex: Int
    ) throws -> [CommittedChatMemoryChange] {
        let candidates = Array(records.prefix(2))
        guard !candidates.isEmpty else { return [] }
        if candidates.count == 2, candidates[0].key == candidates[1].key,
           !sameFactValue(candidates[0], candidates[1]) { return [] }

        guard let character = try modelContext.fetch(FetchDescriptor<CharacterEntity>(
            predicate: #Predicate { $0.characterID == characterID })).first else { throw MemoryError.characterNotFound }
        let entries = try modelContext.fetch(FetchDescriptor<MemoryEntity>(
            predicate: #Predicate { $0.character?.characterID == characterID })).compactMap { entity in
                MemoryRecord.decode(entity.content).map { (entity: entity, record: $0) }
            }
        let cutoff = try extractionCutoff(characterID: characterID)
        var changes: [CommittedChatMemoryChange] = []
        var newEntries: [MemoryEntity] = []
        do {
            var seenKeys = Set<String>()
            for candidate in candidates {
                guard seenKeys.insert(candidate.key).inserted,
                      !candidate.forgotten, !candidate.edited, !candidate.archived,
                      candidate.text.count <= 240, candidate.text.contains(where: { $0.isLetter || $0.isNumber }),
                      candidate.key.count <= 64,
                      candidate.key.range(of: #"^user\.[a-z0-9_.-]+$"#, options: .regularExpression) != nil,
                      ["active", "planned", "completed", "cancelled"].contains(candidate.status) else { continue }
                var record = candidate
                if candidate.messageID != nil || candidate.evidence != nil {
                    guard let source = try groundedMessage(for: candidate, characterID: characterID) else { continue }
                    record.observedAt = source.createdAt
                }
                guard cutoff.map({ record.observedAt > $0 }) ?? true else { continue }

                // User edits and forgetting are authoritative, including late model results.
                let matches = entries.filter { $0.record.key == record.key }
                guard matches.count <= 1 else { continue }
                if let (entity, prior) = matches.first {
                    guard entity.sourceRaw == MemorySource.chat.rawValue, !prior.forgotten, !prior.edited else { continue }
                    if prior.observedAt == record.observedAt, prior.messageID == record.messageID,
                       entity.sourceUpToIndex == sourceIndex, sameFactValue(prior, record),
                       try !hasSyncIdentity(entity) {
                        // Repair a previously committed insertion whose permanent ID was not journaled.
                        try journal(entity)
                        if let messageID = record.messageID {
                            changes.append(.init(kind: .remembered, messageID: messageID, memoryKey: record.key))
                        }
                        continue
                    }
                    guard prior.observedAt < record.observedAt else { continue }
                    let repeated = sameFactValue(prior, record) || repeatsEvidence(prior, record)
                    if repeated {
                        // A fresh statement can rule out a delayed write while leaving the remembered value intact.
                        record.text = prior.text
                        record.status = prior.status
                        record.archived = prior.archived
                    }
                    entity.content = try record.encoded()
                    entity.sourceUpToIndex = sourceIndex
                    try journal(entity)
                    if !repeated, let messageID = record.messageID {
                        changes.append(.init(kind: changeKind(for: record, replacing: prior),
                                             messageID: messageID, memoryKey: record.key))
                    }
                } else {
                    let entity = MemoryEntity(tierRaw: MemoryTier.long.rawValue, sourceRaw: MemorySource.chat.rawValue,
                                              content: try record.encoded(), importance: 4, sourceUpToIndex: sourceIndex)
                    entity.character = character
                    modelContext.insert(entity)
                    newEntries.append(entity)
                    if let messageID = record.messageID {
                        changes.append(.init(kind: .remembered, messageID: messageID, memoryKey: record.key))
                    }
                }
            }
            try modelContext.save()
            // The content sync mapping uses a SwiftData ID that is temporary until the first save.
            for entity in newEntries { try journal(entity) }
            if !newEntries.isEmpty { try modelContext.save() }
            return changes
        } catch { modelContext.rollback(); throw error }
    }

    private func groundedMessage(for record: MemoryRecord, characterID: UUID) throws -> MessageEntity? {
        guard let messageID = record.messageID, let quote = record.evidence,
              quote.count >= 4, quote.contains(where: \.isLetter),
              let message = try modelContext.fetch(FetchDescriptor<MessageEntity>(
                predicate: #Predicate { $0.messageID == messageID })).first,
              message.roleRaw == MessageRole.user.rawValue,
              message.conversation?.character?.characterID == characterID,
              message.text.range(of: quote, options: [.caseInsensitive, .literal]) != nil else { return nil }
        return message
    }

    private func hasSyncIdentity(_ entity: MemoryEntity) throws -> Bool {
        let localKey = ContentMutationJournal.persistentKey(entity.persistentModelID)
        let memoryType = ContentResourceKind.memory.rawValue
        return try modelContext.fetchCount(FetchDescriptor<ContentSyncMetadataEntity>(
            predicate: #Predicate { $0.resourceTypeRaw == memoryType && $0.localKey == localKey })) > 0
    }

    private func sameFactValue(_ a: MemoryRecord, _ b: MemoryRecord) -> Bool {
        normalizedFactText(a.text) == normalizedFactText(b.text) && a.status == b.status && a.eventDate == b.eventDate
    }

    private func repeatsEvidence(_ a: MemoryRecord, _ b: MemoryRecord) -> Bool {
        guard let oldQuote = a.evidence, let newQuote = b.evidence, a.eventDate == b.eventDate else { return false }
        return normalizedFactText(oldQuote) == normalizedFactText(newQuote)
    }

    private func normalizedFactText(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".。"))
    }

    private func changeKind(for record: MemoryRecord, replacing prior: MemoryRecord) -> CommittedChatMemoryChange.Kind {
        guard let evidence = record.evidence else { return .updated }
        let correction = #"\b(?:i was wrong|i said it wrong|i meant(?!\s+to\b))\b|\bcorrection\s*:|我说错了|更正一下"#
        if let cue = evidence.range(of: correction, options: [.regularExpression, .caseInsensitive]) {
            let clause = evidence[cue.upperBound...].prefix { !".!?。！？".contains($0) }
            let introducedTerms = factTerms(record.text).subtracting(factTerms(prior.text))
            if !introducedTerms.isDisjoint(with: factTerms(String(clause))) { return .corrected }
        }
        let refinement = #"\b(?:more specifically|to be more specific|to be precise)\b|更具体地说|准确来说"#
        if prior.status == record.status, prior.eventDate == record.eventDate,
           normalizedFactText(record.text).hasPrefix(normalizedFactText(prior.text) + " "),
           evidence.range(of: refinement, options: [.regularExpression, .caseInsensitive]) != nil {
            return .refined
        }
        return .updated
    }

    private func factTerms(_ text: String) -> Set<Substring> {
        Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.filter { $0.count >= 3 })
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
