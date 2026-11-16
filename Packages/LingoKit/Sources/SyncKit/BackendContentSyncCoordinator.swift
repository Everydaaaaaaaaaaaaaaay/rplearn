import BackendKit
import CoreKit
import DomainKit
import Foundation
import PersistenceKit

public enum ContentSyncActivation: Sendable, Equatable {
    case offlineCache
    case cached
    case synchronized
}

public actor BackendContentSyncCoordinator: SharedChatGateway {
    private var sharedLastSync = Date.distantPast
    private var sharedSequences: [UUID: Int] = [:]
    private let backend: BackendClient
    private let store: ContentSyncStore
    private struct Waiter {
        let pass: Int
        let continuation: CheckedContinuation<Void, Error>
    }
    private var synchronizationWaiters: [UUID: Waiter] = [:]
    private var synchronizationPass = 0
    private var isSynchronizing = false
    private var needsAnotherPass = false
    private var listenerTask: Task<Void, Never>?
    private var waitingSynchronizationTask: Task<Void, Never>?
    private var waitingSynchronizationID = UUID()
    private var userID: UUID?

    public init(
        backend: BackendClient,
        store: ContentSyncStore
    ) {
        self.backend = backend
        self.store = store
    }

    public func activate(userID: UUID, preferCache: Bool = false) async throws -> ContentSyncActivation {
        self.userID = userID
        try await store.activateOwner(userID: userID)
        let needsBootstrap = try await store.needsBootstrap(userID: userID)
        if needsBootstrap {
            try await bootstrap()
        }
        startListener()
        if preferCache, !needsBootstrap { return .cached }
        do {
            try await synchronize()
            return .synchronized
        } catch let error as BackendClientError {
            if case .transport = error, !needsBootstrap {
                return .offlineCache
            }
            throw error
        }
    }

    public func deactivate() {
        finishWaiters(error: CancellationError())
        waitingSynchronizationTask?.cancel()
        waitingSynchronizationTask = nil
        waitingSynchronizationID = UUID()
        listenerTask?.cancel()
        listenerTask = nil
        userID = nil
        sharedSequences = [:]
    }

    public func synchronize() async throws {
        guard userID != nil else { return }
        if isSynchronizing {
            needsAnotherPass = true
            return
        }
        isSynchronizing = true
        defer { isSynchronizing = false }
        do {
            repeat {
                try Task.checkCancellation()
                synchronizationPass += 1
                needsAnotherPass = false
                try await flushOutbox()
                try await pullChanges()
                finishWaiters(error: nil, through: synchronizationPass)
            } while needsAnotherPass
            finishWaiters(error: nil)
        } catch {
            finishWaiters(error: error)
            throw error
        }
    }

    /// 模型关联需要确认正文真正保存；普通 synchronize 在已有任务时只标记再跑一次。
    public func synchronizeAndWait() async throws {
        guard userID != nil else { throw BackendClientError.signedOut }
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                synchronizationWaiters[id] = Waiter(pass: synchronizationPass + 1, continuation: continuation)
                if isSynchronizing { needsAnotherPass = true }
                else { startWaitingSynchronization() }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        synchronizationWaiters.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
    }

    private func startWaitingSynchronization() {
        guard userID != nil else { return }
        if isSynchronizing { needsAnotherPass = true; return }
        guard waitingSynchronizationTask == nil else { return }
        let id = UUID()
        waitingSynchronizationID = id
        waitingSynchronizationTask = Task {
            try? await self.synchronize()
            guard self.waitingSynchronizationID == id else { return }
            self.waitingSynchronizationTask = nil
            // A new waiter may arrive after the pass finishes but before this task resumes.
            if !self.synchronizationWaiters.isEmpty { self.startWaitingSynchronization() }
        }
    }

    private func finishWaiters(error: Error?, through pass: Int = .max) {
        let waiting = synchronizationWaiters.filter { error != nil || $0.value.pass <= pass }
        for (id, waiter) in waiting {
            synchronizationWaiters[id] = nil
            if let error { waiter.continuation.resume(throwing: error) }
            else { waiter.continuation.resume() }
        }
    }

    public func openSharedConversation(characterID: UUID) async throws -> SharedChatSnapshot {
        try await synchronizeAndWait()
        let owner = userID
        let state = try await backend.openSharedChat(characterID: characterID)
        guard owner == userID, owner != nil else { throw CancellationError() }
        return try await applySharedPages(state)
    }

    public func sharedReply(conversationID: UUID, userMessageID: UUID) async throws -> SharedChatSnapshot {
        guard let owner = userID else { throw BackendClientError.signedOut }
        let state = try await backend.sharedChatState(
            conversationID: conversationID, afterSequence: sharedSequences[conversationID] ?? 0,
            inputMessageID: userMessageID)
        guard owner == userID else { throw CancellationError() }
        return try await applySharedPages(state, inputMessageID: userMessageID)
    }

    public func uploadSharedMessages() async throws { try await synchronizeAndWait() }

    public func refreshSharedConversation(conversationID: UUID) async throws -> SharedChatSnapshot {
        guard let owner = userID else { throw BackendClientError.signedOut }
        if Date.now.timeIntervalSince(sharedLastSync) > 5 {
            try await synchronizeAndWait()
            sharedLastSync = .now
        }
        let state = try await backend.sharedChatState(
            conversationID: conversationID, afterSequence: sharedSequences[conversationID] ?? 0)
        guard owner == userID else { throw CancellationError() }
        return try await applySharedPages(state)
    }

    public func retrySharedReply(conversationID: UUID, commandID: UUID) async throws {
        guard let owner = userID else { throw BackendClientError.signedOut }
        let state = try await backend.retrySharedChat(conversationID: conversationID, commandID: commandID)
        guard owner == userID else { throw CancellationError() }
        _ = try await applySharedPages(state)
    }

    private func applySharedPages(_ initial: BackendSharedChatState, inputMessageID: UUID? = nil) async throws
        -> SharedChatSnapshot
    {
        let owner = userID
        var state = initial
        repeat {
            guard owner == userID, owner != nil else { throw CancellationError() }
            try Task.checkCancellation()
            try await store.applySharedChat(
                records: try state.records.map(Self.remote), coveredMessageIDs: Set(state.coveredMessageIds))
            sharedSequences[state.conversationId] = max(
                sharedSequences[state.conversationId] ?? 0, state.lastSequence)
            if !state.hasMore { break }
            state = try await backend.sharedChatState(
                conversationID: state.conversationId, afterSequence: state.lastSequence,
                inputMessageID: inputMessageID)
        } while true
        return SharedChatSnapshot(
            conversationID: state.conversationId, lastSequence: state.lastSequence,
            generation: state.generation.map {
                .init(
                    id: $0.id, status: $0.status, partialText: $0.partialText,
                    inputMessageIDs: $0.inputMessageIds, errorCode: $0.errorCode)
            },
            coveredMessageIDs: Set(state.coveredMessageIds))
    }

    private func bootstrap() async throws {
        var cursor: String?
        var records: [RemoteContentRecord] = []
        var syncCursor: String?
        repeat {
            let page = try await backend.contentPage(cursor: cursor, limit: 500)
            try Task.checkCancellation()
            records.append(contentsOf: try page.records.map(Self.remote))
            syncCursor = syncCursor ?? page.syncCursor
            cursor = page.nextCursor
            if !page.hasMore { break }
        } while true
        guard let syncCursor else {
            throw BackendClientError.invalidResponse
        }
        try await store.bootstrap(records: records, syncCursor: syncCursor)
    }

    private func flushOutbox() async throws {
        var conflictAttempts: [String: Int] = [:]
        while true {
            try Task.checkCancellation()
            let pending = try await store.takePending(limit: 50, serialPerResource: true)
            guard !pending.isEmpty else {
                try await store.assertNoStalledRelationshipReplay()
                return
            }
            do {
                let commands = try pending.map(Self.command)
                let results = try await backend.submitContentCommands(commands)
                try Task.checkCancellation()
                let expected = Dictionary(uniqueKeysWithValues: pending.map { ($0.commandID, $0) })
                // A matching count alone cannot prove these receipts acknowledge this batch.
                guard results.count == pending.count,
                      Set(results.map(\.commandId)) == Set(expected.keys)
                else { throw BackendClientError.invalidResponse }
                for result in results {
                    guard let mutation = expected[result.commandId] else {
                        throw BackendClientError.invalidResponse
                    }
                    if result.status == "applied", let record = result.record {
                        guard record.resourceId == mutation.resourceID,
                              record.resourceType == mutation.resourceType.rawValue
                        else { throw BackendClientError.invalidResponse }
                    } else if result.status != "rejected" || result.error == nil {
                        throw BackendClientError.invalidResponse
                    }
                }
                for result in results {
                    if result.status == "applied", let record = result.record {
                        try await store.complete(
                            commandID: result.commandId,
                            record: try Self.remote(record)
                        )
                    } else if let error = result.error {
                        if error.code == "CHAT_PREDECESSOR_PENDING" {
                            throw BackendClientError.invalidResponse
                        }
                        try await store.reject(
                            commandID: result.commandId,
                            code: error.code,
                            current: try Self.currentRecord(from: error.details),
                            replayRelationship: { inputs, snapshot in try RelationshipReplay.apply(inputs, to: snapshot) }
                        )
                        if error.code == "CONTENT_VERSION_CONFLICT", let mutation = expected[result.commandId] {
                            let key = mutation.resourceType.rawValue + ":" + mutation.resourceID
                            conflictAttempts[key, default: 0] += 1
                            if conflictAttempts[key, default: 0] >= 4 { throw ContentSyncStore.SyncStoreError.conflictRetryLimit }
                        }
                    }
                }
            } catch {
                // Transport, decoding and receipt/application failures all release pending work.
                // Already acknowledged commands are absent and are not resurrected.
                try? await store.resetInFlight(commandIDs: pending.map(\.commandID))
                throw error
            }
        }
    }

    private func pullChanges() async throws {
        guard var cursor = try await store.syncCursor() else { return }
        repeat {
            try Task.checkCancellation()
            let page: BackendSyncPage = try await backend.get(
                "/v1/sync/changes",
                queryItems: [
                    URLQueryItem(name: "cursor", value: cursor),
                    URLQueryItem(name: "limit", value: "100"),
                ]
            )
            var records: [RemoteContentRecord] = []
            for change in page.changes {
                guard change.eventType.hasPrefix("content."),
                      let payload = change.payload
                else {
                    continue
                }
                records.append(
                    try Self.remote(BackendContentRecord.decode(payload))
                )
            }
            try Task.checkCancellation()
            try await store.apply(
                records: records,
                nextCursor: page.nextCursor
            )
            cursor = page.nextCursor
            if !page.hasMore { return }
        } while true
    }

    private func startListener() {
        guard listenerTask == nil else { return }
        listenerTask = Task { [weak self] in
            let events = await ContentSyncSignal.shared.events()
            for await _ in events {
                guard !Task.isCancelled, let self else { return }
                try? await self.synchronize()
            }
        }
    }

    private static func command(
        _ mutation: PendingContentMutation
    ) throws -> BackendContentCommand {
        BackendContentCommand(
            commandID: mutation.commandID,
            expectedVersion: mutation.expectedVersion,
            operation: mutation.operation.rawValue,
            parentID: mutation.parentID,
            payload: try mutation.payloadJSON.map(BackendJSONValue.decode(json:)),
            resourceID: mutation.resourceID,
            resourceType: mutation.resourceType.rawValue
        )
    }

    private static func currentRecord(
        from details: BackendJSONValue?
    ) throws -> RemoteContentRecord? {
        guard case .object(let object) = details,
              let value = object["current"],
              value != .null
        else {
            return nil
        }
        return try remote(BackendContentRecord.decode(value))
    }

    private static func remote(
        _ record: BackendContentRecord
    ) throws -> RemoteContentRecord {
        guard let type = ContentResourceKind(rawValue: record.resourceType) else {
            throw BackendClientError.invalidResponse
        }
        return RemoteContentRecord(
            createdAt: try date(record.createdAt),
            deletedAt: try record.deletedAt.map(date),
            parentID: record.parentId,
            payloadJSON: try record.payload.encodedJSON(),
            resourceID: record.resourceId,
            resourceType: type,
            updatedAt: try date(record.updatedAt),
            version: record.version
        )
    }

    private static func date(_ value: String) throws -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        guard let date = ISO8601DateFormatter().date(from: value) else {
            throw BackendClientError.invalidResponse
        }
        return date
    }
}
