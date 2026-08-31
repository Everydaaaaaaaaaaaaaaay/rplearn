import Foundation
import SwiftData

public struct RemoteContentRecord: Sendable, Equatable {
    public let createdAt: Date
    public let deletedAt: Date?
    public let parentID: String?
    public let payloadJSON: String
    public let resourceID: String
    public let resourceType: ContentResourceKind
    public let updatedAt: Date
    public let version: Int

    public init(
        createdAt: Date,
        deletedAt: Date?,
        parentID: String?,
        payloadJSON: String,
        resourceID: String,
        resourceType: ContentResourceKind,
        updatedAt: Date,
        version: Int
    ) {
        self.createdAt = createdAt
        self.deletedAt = deletedAt
        self.parentID = parentID
        self.payloadJSON = payloadJSON
        self.resourceID = resourceID
        self.resourceType = resourceType
        self.updatedAt = updatedAt
        self.version = version
    }
}

public struct PendingContentMutation: Sendable, Equatable {
    public let commandID: UUID
    public let expectedVersion: Int
    public let operation: ContentMutationOperation
    public let parentID: String?
    public let payloadJSON: String?
    public let resourceID: String
    public let resourceType: ContentResourceKind
}

@ModelActor
public actor ContentSyncStore {
    public enum SyncStoreError: Error {
        case invalidPayload
        case missingParent
        case unknownResource
    }

    public func activateOwner(userID: UUID) throws {
        if let owner = try modelContext.fetch(FetchDescriptor<ContentSyncOwnerEntity>()).first {
            guard owner.userID == userID else {
                throw SyncStoreError.invalidPayload
            }
            return
        }
        modelContext.insert(ContentSyncOwnerEntity(userID: userID))
        try modelContext.save()
    }

    public func needsBootstrap(userID: UUID) throws -> Bool {
        guard let owner = try owner(), owner.userID == userID else { return true }
        return !owner.hasBootstrapped
    }

    public func bootstrap(
        records: [RemoteContentRecord],
        syncCursor: String
    ) throws {
        guard let owner = try owner() else {
            throw SyncStoreError.invalidPayload
        }
        let serverKeys = Set(records.map { metadataKey($0.resourceType, $0.resourceID) })
        for record in records {
            try apply(record)
        }
        for local in try exportLocalRecords()
        where !serverKeys.contains(metadataKey(local.resourceType, local.resourceID)) {
            try ContentMutationJournal.upsert(
                in: modelContext,
                resourceType: local.resourceType,
                resourceID: local.resourceID,
                parentID: local.parentID,
                payloadJSON: local.payloadJSON
            )
        }
        owner.syncCursor = syncCursor
        owner.hasBootstrapped = true
        try modelContext.save()
    }

    public func apply(
        records: [RemoteContentRecord],
        nextCursor: String
    ) throws {
        for record in records {
            try apply(record)
        }
        guard let owner = try owner() else {
            throw SyncStoreError.invalidPayload
        }
        owner.syncCursor = nextCursor
        try modelContext.save()
    }

    public func syncCursor() throws -> String? {
        try owner()?.syncCursor
    }

    public func takePending(limit: Int = 50) throws -> [PendingContentMutation] {
        guard let owner = try owner() else { return [] }
        let userID = owner.userID
        var descriptor = FetchDescriptor<ContentOutboxEntity>(
            predicate: #Predicate {
                $0.ownerUserID == userID
                    && !$0.isInFlight
                    && $0.lastErrorCode == nil
            }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt)]
        descriptor.fetchLimit = max(1, min(limit, 100))
        let entities = try modelContext.fetch(descriptor)
        for entity in entities {
            entity.isInFlight = true
            entity.attemptCount += 1
        }
        try modelContext.save()
        return try entities.map(Self.pending(from:))
    }

    public func complete(commandID: UUID, record: RemoteContentRecord) throws {
        guard let command = try outbox(commandID: commandID) else { return }
        let localKey = try metadata(
            resourceType: record.resourceType,
            resourceID: record.resourceID
        )?.localKey ?? record.resourceID
        try upsertMetadata(
            record,
            localKey: localKey
        )
        modelContext.delete(command)
        try modelContext.save()
    }

    public func reject(
        commandID: UUID,
        code: String,
        current: RemoteContentRecord?
    ) throws {
        guard let failed = try outbox(commandID: commandID) else { return }
        if code == "CONTENT_VERSION_CONFLICT", let current {
            let desiredOperation = ContentMutationOperation(rawValue: failed.operationRaw)
            let desiredPayload = failed.payloadJSON
            let desiredParent = failed.parentID
            let later = try pendingForResource(
                ownerUserID: failed.ownerUserID,
                resourceTypeRaw: failed.resourceTypeRaw,
                resourceID: failed.resourceID
            ).filter { $0.commandID != failed.commandID }
            modelContext.delete(failed)
            try apply(current)
            if later.isEmpty,
               let kind = ContentResourceKind(rawValue: current.resourceType.rawValue),
               let desiredOperation
            {
                if desiredOperation == .upsert, let desiredPayload {
                    try ContentMutationJournal.upsert(
                        in: modelContext,
                        resourceType: kind,
                        resourceID: current.resourceID,
                        parentID: desiredParent,
                        payloadJSON: desiredPayload
                    )
                } else if desiredOperation == .delete {
                    try ContentMutationJournal.delete(
                        in: modelContext,
                        resourceType: kind,
                        resourceID: current.resourceID
                    )
                }
            } else {
                for (offset, pending) in later.enumerated() {
                    pending.commandID = UUID()
                    pending.expectedVersion = current.version + offset
                    pending.isInFlight = false
                    pending.lastErrorCode = nil
                }
            }
        } else {
            failed.isInFlight = false
            failed.lastErrorCode = code
        }
        try modelContext.save()
    }

    public func resetInFlight(commandIDs: [UUID]) throws {
        let ids = Set(commandIDs)
        let entities = try modelContext.fetch(FetchDescriptor<ContentOutboxEntity>())
        for entity in entities where ids.contains(entity.commandID) {
            entity.isInFlight = false
        }
        try modelContext.save()
    }

    public func unresolvedErrorCount() throws -> Int {
        try modelContext.fetchCount(
            FetchDescriptor<ContentOutboxEntity>(
                predicate: #Predicate { $0.lastErrorCode != nil }
            )
        )
    }
}
