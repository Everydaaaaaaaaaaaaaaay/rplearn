import Foundation
import SwiftData

public struct PendingVoiceMediaUpload: Sendable, Equatable {
    public let assetID: UUID
    public let attemptCount: Int
    public let byteSize: Int
    public let checksumSha256: String
    public let contentType: String
    public let localFileName: String
    public let messageID: UUID
    public let nextAttemptAt: Date
    public let ownerUserID: UUID

    public init(
        assetID: UUID,
        attemptCount: Int,
        byteSize: Int,
        checksumSha256: String,
        contentType: String,
        localFileName: String,
        messageID: UUID,
        nextAttemptAt: Date,
        ownerUserID: UUID
    ) {
        self.assetID = assetID
        self.attemptCount = attemptCount
        self.byteSize = byteSize
        self.checksumSha256 = checksumSha256
        self.contentType = contentType
        self.localFileName = localFileName
        self.messageID = messageID
        self.nextAttemptAt = nextAttemptAt
        self.ownerUserID = ownerUserID
    }
}

public struct PendingVoiceMediaDeletion: Sendable, Equatable {
    public let assetID: UUID
    public let attemptCount: Int
    public let messageID: UUID
    public let nextAttemptAt: Date
    public let ownerUserID: UUID
}

@ModelActor
public actor VoiceMediaQueueStore {
    public func enqueue(_ upload: PendingVoiceMediaUpload) throws {
        if let existing = try entity(assetID: upload.assetID) {
            guard existing.ownerUserID == upload.ownerUserID,
                  existing.messageID == upload.messageID,
                  existing.localFileName == upload.localFileName,
                  existing.byteSize == upload.byteSize,
                  existing.checksumSha256 == upload.checksumSha256,
                  existing.contentType == upload.contentType
            else {
                throw QueueError.assetConflict
            }
            return
        }
        modelContext.insert(
            VoiceMediaUploadEntity(
                assetID: upload.assetID,
                ownerUserID: upload.ownerUserID,
                messageID: upload.messageID,
                localFileName: upload.localFileName,
                byteSize: upload.byteSize,
                checksumSha256: upload.checksumSha256,
                contentType: upload.contentType
            )
        )
        try modelContext.save()
    }

    public func next(ownerUserID: UUID, now: Date = .now) throws -> PendingVoiceMediaUpload? {
        var descriptor = FetchDescriptor<VoiceMediaUploadEntity>(
            predicate: #Predicate {
                $0.ownerUserID == ownerUserID && $0.nextAttemptAt <= now
            },
            sortBy: [SortDescriptor(\.nextAttemptAt), SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map(Self.pending)
    }

    public func complete(assetID: UUID) throws {
        guard let entity = try entity(assetID: assetID) else { return }
        modelContext.delete(entity)
        try modelContext.save()
    }

    public func fail(
        assetID: UUID,
        errorCode: String,
        retryAt: Date
    ) throws {
        guard let entity = try entity(assetID: assetID) else { return }
        entity.attemptCount += 1
        entity.lastErrorCode = String(errorCode.prefix(100))
        entity.nextAttemptAt = retryAt
        try modelContext.save()
    }

    public func pendingCount(ownerUserID: UUID) throws -> Int {
        try modelContext.fetchCount(
            FetchDescriptor<VoiceMediaUploadEntity>(
                predicate: #Predicate { $0.ownerUserID == ownerUserID }
            )
        )
    }

    /// 仅当消息的内容同步 Outbox 已清空时返回删除任务，确保墓碑先于二进制删除。
    public func nextDeletion(
        ownerUserID: UUID,
        now: Date = .now
    ) throws -> PendingVoiceMediaDeletion? {
        let candidates = try modelContext.fetch(
            FetchDescriptor<VoiceMediaDeletionEntity>(
                predicate: #Predicate {
                    $0.ownerUserID == ownerUserID && $0.nextAttemptAt <= now
                },
                sortBy: [SortDescriptor(\.nextAttemptAt), SortDescriptor(\.createdAt)]
            )
        )
        for candidate in candidates {
            let resourceID = candidate.messageID.uuidString.lowercased()
            let pending = try modelContext.fetchCount(
                FetchDescriptor<ContentOutboxEntity>(
                    predicate: #Predicate {
                        $0.ownerUserID == ownerUserID
                            && $0.resourceTypeRaw == "message"
                            && $0.resourceID == resourceID
                    }
                )
            )
            if pending == 0 {
                return PendingVoiceMediaDeletion(
                    assetID: candidate.assetID,
                    attemptCount: candidate.attemptCount,
                    messageID: candidate.messageID,
                    nextAttemptAt: candidate.nextAttemptAt,
                    ownerUserID: candidate.ownerUserID
                )
            }
        }
        return nil
    }

    public func completeDeletion(assetID: UUID) throws {
        guard let entity = try deletion(assetID: assetID) else { return }
        modelContext.delete(entity)
        try modelContext.save()
    }

    public func failDeletion(assetID: UUID, errorCode: String, retryAt: Date) throws {
        guard let entity = try deletion(assetID: assetID) else { return }
        entity.attemptCount += 1
        entity.lastErrorCode = String(errorCode.prefix(100))
        entity.nextAttemptAt = retryAt
        try modelContext.save()
    }

    public func pendingDeletionCount(ownerUserID: UUID) throws -> Int {
        try modelContext.fetchCount(
            FetchDescriptor<VoiceMediaDeletionEntity>(
                predicate: #Predicate { $0.ownerUserID == ownerUserID }
            )
        )
    }

    private func entity(assetID: UUID) throws -> VoiceMediaUploadEntity? {
        try modelContext.fetch(
            FetchDescriptor<VoiceMediaUploadEntity>(
                predicate: #Predicate { $0.assetID == assetID }
            )
        ).first
    }

    private func deletion(assetID: UUID) throws -> VoiceMediaDeletionEntity? {
        try modelContext.fetch(
            FetchDescriptor<VoiceMediaDeletionEntity>(
                predicate: #Predicate { $0.assetID == assetID }
            )
        ).first
    }

    private static func pending(_ entity: VoiceMediaUploadEntity) -> PendingVoiceMediaUpload {
        PendingVoiceMediaUpload(
            assetID: entity.assetID,
            attemptCount: entity.attemptCount,
            byteSize: entity.byteSize,
            checksumSha256: entity.checksumSha256,
            contentType: entity.contentType,
            localFileName: entity.localFileName,
            messageID: entity.messageID,
            nextAttemptAt: entity.nextAttemptAt,
            ownerUserID: entity.ownerUserID
        )
    }

    public enum QueueError: Error {
        case assetConflict
    }
}
