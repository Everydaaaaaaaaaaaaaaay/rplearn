import Foundation
import SwiftData

public actor ContentSyncSignal {
    public static let shared = ContentSyncSignal()

    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var debounceTask: Task<Void, Never>?

    public func events() -> AsyncStream<Void> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { _ in
                Task { await ContentSyncSignal.shared.remove(id) }
            }
        }
    }

    public func schedule() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            emit()
        }
    }

    private func emit() {
        for continuation in continuations.values {
            continuation.yield()
        }
    }

    private func remove(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}

enum ContentMutationJournal {
    static func encode<T: Encodable>(_ payload: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(payload), as: UTF8.self)
    }

    static func upsert(
        in context: ModelContext,
        resourceType: ContentResourceKind,
        resourceID: String,
        parentID: String?,
        payloadJSON: String
    ) throws {
        guard let owner = try owner(in: context) else { return }
        let pending = try pendingMutations(
            in: context,
            ownerUserID: owner.userID,
            resourceType: resourceType,
            resourceID: resourceID
        )
        if let coalescible = pending.last,
           !coalescible.isInFlight,
           coalescible.operationRaw == ContentMutationOperation.upsert.rawValue
        {
            coalescible.parentID = parentID
            coalescible.payloadJSON = payloadJSON
            coalescible.lastErrorCode = nil
        } else {
            context.insert(
                ContentOutboxEntity(
                    ownerUserID: owner.userID,
                    resourceType: resourceType,
                    resourceID: resourceID,
                    parentID: parentID,
                    operation: .upsert,
                    payloadJSON: payloadJSON,
                    expectedVersion: nextExpectedVersion(
                        in: context,
                        resourceType: resourceType,
                        resourceID: resourceID,
                        pending: pending
                    )
                )
            )
        }
        signal()
    }

    static func delete(
        in context: ModelContext,
        resourceType: ContentResourceKind,
        resourceID: String
    ) throws {
        guard let owner = try owner(in: context) else { return }
        let pending = try pendingMutations(
            in: context,
            ownerUserID: owner.userID,
            resourceType: resourceType,
            resourceID: resourceID
        )
        if let last = pending.last,
           !last.isInFlight,
           last.operationRaw == ContentMutationOperation.delete.rawValue
        {
            return
        }
        context.insert(
            ContentOutboxEntity(
                ownerUserID: owner.userID,
                resourceType: resourceType,
                resourceID: resourceID,
                parentID: nil,
                operation: .delete,
                payloadJSON: nil,
                expectedVersion: nextExpectedVersion(
                    in: context,
                    resourceType: resourceType,
                    resourceID: resourceID,
                    pending: pending
                )
            )
        )
        signal()
    }

    static func resourceID(
        in context: ModelContext,
        resourceType: ContentResourceKind,
        localKey: String
    ) throws -> String {
        let typeRaw = resourceType.rawValue
        let descriptor = FetchDescriptor<ContentSyncMetadataEntity>(
            predicate: #Predicate {
                $0.resourceTypeRaw == typeRaw && $0.localKey == localKey
            }
        )
        if let existing = try context.fetch(descriptor).first {
            return existing.resourceID
        }
        let resourceID = UUID().uuidString.lowercased()
        context.insert(
            ContentSyncMetadataEntity(
                resourceType: resourceType,
                resourceID: resourceID,
                localKey: localKey,
                version: 0
            )
        )
        return resourceID
    }

    static func persistentKey(_ id: PersistentIdentifier) -> String {
        String(describing: id)
    }

    private static func owner(in context: ModelContext) throws -> ContentSyncOwnerEntity? {
        try context.fetch(FetchDescriptor<ContentSyncOwnerEntity>()).first
    }

    private static func pendingMutations(
        in context: ModelContext,
        ownerUserID: UUID,
        resourceType: ContentResourceKind,
        resourceID: String
    ) throws -> [ContentOutboxEntity] {
        let typeRaw = resourceType.rawValue
        var descriptor = FetchDescriptor<ContentOutboxEntity>(
            predicate: #Predicate {
                $0.ownerUserID == ownerUserID
                    && $0.resourceTypeRaw == typeRaw
                    && $0.resourceID == resourceID
            }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt)]
        return try context.fetch(descriptor)
    }

    private static func nextExpectedVersion(
        in context: ModelContext,
        resourceType: ContentResourceKind,
        resourceID: String,
        pending: [ContentOutboxEntity]
    ) -> Int {
        if let last = pending.last {
            return last.expectedVersion + 1
        }
        let key = "\(resourceType.rawValue):\(resourceID)"
        let descriptor = FetchDescriptor<ContentSyncMetadataEntity>(
            predicate: #Predicate { $0.metadataKey == key }
        )
        return (try? context.fetch(descriptor).first?.version) ?? 0
    }

    private static func signal() {
        Task { await ContentSyncSignal.shared.schedule() }
    }
}
