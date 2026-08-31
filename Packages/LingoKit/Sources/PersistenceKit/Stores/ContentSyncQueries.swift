import Foundation
import SwiftData

extension ContentSyncStore {
// MARK: - Queries

    func owner() throws -> ContentSyncOwnerEntity? {
        try modelContext.fetch(FetchDescriptor<ContentSyncOwnerEntity>()).first
    }

    func outbox(commandID: UUID) throws -> ContentOutboxEntity? {
        let descriptor = FetchDescriptor<ContentOutboxEntity>(
            predicate: #Predicate { $0.commandID == commandID }
        )
        return try modelContext.fetch(descriptor).first
    }

    func pendingForResource(
        ownerUserID: UUID,
        resourceTypeRaw: String,
        resourceID: String
    ) throws -> [ContentOutboxEntity] {
        var descriptor = FetchDescriptor<ContentOutboxEntity>(
            predicate: #Predicate {
                $0.ownerUserID == ownerUserID
                    && $0.resourceTypeRaw == resourceTypeRaw
                    && $0.resourceID == resourceID
            }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt)]
        return try modelContext.fetch(descriptor)
    }

    func metadata(
        resourceType: ContentResourceKind,
        resourceID: String
    ) throws -> ContentSyncMetadataEntity? {
        let key = metadataKey(resourceType, resourceID)
        let descriptor = FetchDescriptor<ContentSyncMetadataEntity>(
            predicate: #Predicate { $0.metadataKey == key }
        )
        return try modelContext.fetch(descriptor).first
    }

    func upsertMetadata(
        _ record: RemoteContentRecord,
        localKey: String
    ) throws {
        if let metadata = try metadata(
            resourceType: record.resourceType,
            resourceID: record.resourceID
        ) {
            metadata.localKey = localKey
            metadata.version = record.version
            metadata.updatedAt = record.updatedAt
        } else {
            modelContext.insert(
                ContentSyncMetadataEntity(
                    resourceType: record.resourceType,
                    resourceID: record.resourceID,
                    localKey: localKey,
                    version: record.version,
                    updatedAt: record.updatedAt
                )
            )
        }
    }

    func character(id: UUID) throws -> CharacterEntity? {
        let descriptor = FetchDescriptor<CharacterEntity>(
            predicate: #Predicate { $0.characterID == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func conversation(id: UUID) throws -> ConversationEntity? {
        let descriptor = FetchDescriptor<ConversationEntity>(
            predicate: #Predicate { $0.conversationID == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func message(id: UUID) throws -> MessageEntity? {
        let descriptor = FetchDescriptor<MessageEntity>(
            predicate: #Predicate { $0.messageID == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func voiceMediaLink(messageID: UUID) throws -> VoiceMediaLinkEntity? {
        try modelContext.fetch(
            FetchDescriptor<VoiceMediaLinkEntity>(
                predicate: #Predicate { $0.messageID == messageID }
            )
        ).first
    }

    func voiceMediaUpload(messageID: UUID) throws -> VoiceMediaUploadEntity? {
        try modelContext.fetch(
            FetchDescriptor<VoiceMediaUploadEntity>(
                predicate: #Predicate { $0.messageID == messageID }
            )
        ).first
    }

    func memory(localKey: String) throws -> MemoryEntity? {
        try modelContext.fetch(FetchDescriptor<MemoryEntity>()).first {
            persistentKey($0.persistentModelID) == localKey
        }
    }

    func quizRecord(localKey: String) throws -> QuizRecordEntity? {
        try modelContext.fetch(FetchDescriptor<QuizRecordEntity>()).first {
            persistentKey($0.persistentModelID) == localKey
        }
    }

    func persistentKey(_ id: PersistentIdentifier) -> String {
        ContentMutationJournal.persistentKey(id)
    }

    func metadataKey(
        _ resourceType: ContentResourceKind,
        _ resourceID: String
    ) -> String {
        "\(resourceType.rawValue):\(resourceID)"
    }

    func decode<T: Decodable>(_ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }
            if let date = ISO8601DateFormatter().date(from: value) {
                return date
            }
            throw SyncStoreError.invalidPayload
        }
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    static func pending(
        from entity: ContentOutboxEntity
    ) throws -> PendingContentMutation {
        guard let operation = ContentMutationOperation(rawValue: entity.operationRaw),
              let type = ContentResourceKind(rawValue: entity.resourceTypeRaw)
        else {
            throw SyncStoreError.unknownResource
        }
        return PendingContentMutation(
            commandID: entity.commandID,
            expectedVersion: entity.expectedVersion,
            operation: operation,
            parentID: entity.parentID,
            payloadJSON: entity.payloadJSON,
            resourceID: entity.resourceID,
            resourceType: type
        )
    }

    static func encodeFlags(_ flags: [String: Bool]) -> String {
        guard let data = try? JSONEncoder().encode(flags) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func decodeFlags(_ json: String) -> [String: Bool] {
        (try? JSONDecoder().decode([String: Bool].self, from: Data(json.utf8))) ?? [:]
    }
}
