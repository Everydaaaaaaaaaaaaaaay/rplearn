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
    public let relationshipReplayInputs: [RelationshipReplayInput]
}

@ModelActor
public actor ContentSyncStore {
    private var recoveredOwnerID: UUID?

    public enum SyncStoreError: Error {
        case invalidPayload
        case missingParent
        case unknownResource
        case relationshipReplayRequired
        case conflictRetryLimit
    }

    public nonisolated static var guestArchiveURL: URL {
        URL.applicationSupportDirectory.appending(path: "guest-journey-before-cloud-v1.json")
    }

    public func archiveGuestJourneyIfNeeded(profile: UserProfileDTO, beforeLogin: Bool = false) throws {
        guard profile.hasCompletedOnboarding || profile.hasCompletedProfileSetup || profile.coins > 0 else { return }
        let url = beforeLogin ? Self.guestArchiveURL.deletingLastPathComponent().appending(path: "guest-journey-before-login-v1.json") : Self.guestArchiveURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        struct Archive: Encodable {
            let createdAt: Date
            let profile: UserProfileDTO
            let records: [LocalContentRecord]
            let tickets: [ItemDTO]
            let ticketStubs: [TicketStubDTO]
        }
        let archive = Archive(createdAt: .now, profile: profile, records: try exportLocalRecords(),
            tickets: try modelContext.fetch(FetchDescriptor<ItemEntity>()).map(ItemStore.dto),
            ticketStubs: try modelContext.fetch(FetchDescriptor<TicketStubEntity>()).map(TicketStubStore.dto))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(archive).write(to: url, options: [.atomic, .completeFileProtection])
    }

    public func activateOwner(userID: UUID) throws {
        if let owner = try modelContext.fetch(FetchDescriptor<ContentSyncOwnerEntity>()).first {
            guard owner.userID == userID else {
                throw SyncStoreError.invalidPayload
            }
        } else {
            modelContext.insert(ContentSyncOwnerEntity(userID: userID))
        }
        if recoveredOwnerID != userID {
            // A new store instance cannot still own a request from the previous process.
            // Reuse the original command IDs so an already accepted upload is replayed safely.
            let pending = try modelContext.fetch(FetchDescriptor<ContentOutboxEntity>(
                predicate: #Predicate { $0.ownerUserID == userID && $0.isInFlight }
            ))
            for mutation in pending { mutation.isInFlight = false }
        }
        try modelContext.save()
        recoveredOwnerID = userID
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
        let localBefore = try exportLocalRecords()
        let locals = Dictionary(uniqueKeysWithValues: localBefore.map { (metadataKey($0.resourceType, $0.resourceID), $0) })
        let serverKeys = Set(records.map { metadataKey($0.resourceType, $0.resourceID) })
        var merges: [RemoteContentRecord] = []
        for record in records {
            let key = metadataKey(record.resourceType, record.resourceID)
            if let local = locals[key], let merged = try Self.mergeGuest(local: local, remote: record) {
                try apply(merged)
                merges.append(merged)
            } else { try apply(record) }
        }
        for merged in merges {
            try ContentMutationJournal.upsert(in: modelContext, resourceType: merged.resourceType,
                resourceID: merged.resourceID, parentID: merged.parentID, payloadJSON: merged.payloadJSON)
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

    /// A conversation snapshot has no global sync cursor. Preserve local pending edits
    /// while applying canonical server identity, ordering and reply coverage.
    public func applySharedChat(records: [RemoteContentRecord], coveredMessageIDs: Set<UUID>) throws {
        guard let owner = try owner() else { throw SyncStoreError.invalidPayload }
        let userID = owner.userID
        let pending = try modelContext.fetch(
            FetchDescriptor<ContentOutboxEntity>(predicate: #Predicate { $0.ownerUserID == userID }))
        let keys = Set(pending.map { $0.resourceTypeRaw + ":" + $0.resourceID })
        for record in records where !keys.contains(record.resourceType.rawValue + ":" + record.resourceID) {
            try apply(record)
        }
        for id in coveredMessageIDs {
            if let message = try message(id: id), message.roleRaw == "user" { message.isInterrupted = false }
        }
        try modelContext.save()
    }

    public func syncCursor() throws -> String? {
        try owner()?.syncCursor
    }

    public func takePending(limit: Int = 50, serialPerResource: Bool = false) throws -> [PendingContentMutation] {
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
        let batchLimit = max(1, min(limit, 100))
        let entities: [ContentOutboxEntity]
        if serialPerResource {
            // Later versions are contingent on the previous command succeeding. Sending both in one
            // batch could let the later expectedVersion match a concurrent write after the first failed.
            var all = FetchDescriptor<ContentOutboxEntity>(predicate: #Predicate { $0.ownerUserID == userID })
            all.sortBy = [SortDescriptor(\.createdAt)]
            var seen = Set<String>()
            var selected: [ContentOutboxEntity] = []
            for candidate in try modelContext.fetch(all) {
                let key = candidate.resourceTypeRaw + ":" + candidate.resourceID
                guard seen.insert(key).inserted else { continue }
                if !candidate.isInFlight && candidate.lastErrorCode == nil { selected.append(candidate) }
                if selected.count == batchLimit { break }
            }
            entities = selected
        } else {
            descriptor.fetchLimit = batchLimit
            entities = try modelContext.fetch(descriptor)
        }
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
        current: RemoteContentRecord?,
        replayRelationship: RelationshipReplayClosure? = nil
    ) throws {
        guard let failed = try outbox(commandID: commandID) else { return }
        if code == "CONTENT_VERSION_CONFLICT", let current {
            if current.resourceType == .character {
                try reconcileCharacter(failed: failed, current: current, replayRelationship: replayRelationship)
                return
            }
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

    private func reconcileCharacter(failed: ContentOutboxEntity, current: RemoteContentRecord,
                                    replayRelationship: RelationshipReplayClosure?) throws {
        let ownerID = failed.ownerUserID
        let typeRaw = failed.resourceTypeRaw
        let resourceID = failed.resourceID
        let pending = try pendingForResource(ownerUserID: ownerID,
            resourceTypeRaw: typeRaw, resourceID: resourceID)
        guard let desired = pending.last else { return }
        let desiredParent = desired.parentID
        let desiredOperation = ContentMutationOperation(rawValue: desired.operationRaw)
        if desiredOperation == .delete {
            do {
                for command in pending { modelContext.delete(command) }
                try apply(current)
                modelContext.insert(ContentOutboxEntity(ownerUserID: ownerID, resourceType: .character,
                    resourceID: resourceID, parentID: nil, operation: .delete, payloadJSON: nil,
                    expectedVersion: current.version))
                try modelContext.save()
            } catch {
                modelContext.rollback()
                throw error
            }
            return
        }
        do {
            guard current.deletedAt == nil, let desiredJSON = desired.payloadJSON else {
                throw SyncStoreError.relationshipReplayRequired
            }
            var inputs: [RelationshipReplayInput] = []
            var seen = Set<UUID>()
            for command in pending {
                for input in try RelationshipReplayInput.decodeList(command.relationshipReplayJSON)
                where seen.insert(input.messageID).inserted { inputs.append(input) }
            }
            let json = try ContentRelationshipReconciliation.reconcile(currentJSON: current.payloadJSON,
                desiredJSON: desiredJSON, inputs: inputs,
                evidenceComplete: pending.allSatisfy { $0.relationshipReplayComplete == true }, replay: replayRelationship)
            let reconciled = RemoteContentRecord(createdAt: current.createdAt, deletedAt: nil,
                parentID: desiredParent, payloadJSON: json, resourceID: current.resourceID,
                resourceType: .character, updatedAt: current.updatedAt, version: current.version)
            for command in pending { modelContext.delete(command) }
            try apply(reconciled)
            let replacement = ContentOutboxEntity(ownerUserID: ownerID, resourceType: .character,
                resourceID: resourceID, parentID: desiredParent, operation: .upsert, payloadJSON: json,
                expectedVersion: current.version)
            replacement.relationshipReplayJSON = try RelationshipReplayInput.encodeList(inputs)
            replacement.relationshipReplayComplete = true
            modelContext.insert(replacement)
            try modelContext.save()
        } catch {
            // Preserve the original exact payload and evidence for recovery; exclude it from automatic retries.
            // A legacy snapshot cannot safely be converted into invented signal deltas.
            modelContext.rollback()
            for command in try pendingForResource(ownerUserID: ownerID, resourceTypeRaw: typeRaw, resourceID: resourceID) {
                command.isInFlight = false
                command.lastErrorCode = "RELATIONSHIP_REPLAY_REQUIRED"
            }
            try modelContext.save()
            throw SyncStoreError.relationshipReplayRequired
        }
    }

    public func assertNoStalledRelationshipReplay() throws {
        let code = "RELATIONSHIP_REPLAY_REQUIRED"
        let count = try modelContext.fetchCount(FetchDescriptor<ContentOutboxEntity>(
            predicate: #Predicate { $0.lastErrorCode == code }
        ))
        if count > 0 { throw SyncStoreError.relationshipReplayRequired }
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
