import BackendKit
import Foundation
import PersistenceKit

public enum ContentSyncActivation: Sendable, Equatable {
    case offlineCache
    case synchronized
}

public actor BackendContentSyncCoordinator {
    private let backend: BackendClient
    private let store: ContentSyncStore
    private var isSynchronizing = false
    private var needsAnotherPass = false
    private var listenerTask: Task<Void, Never>?
    private var userID: UUID?

    public init(
        backend: BackendClient,
        store: ContentSyncStore
    ) {
        self.backend = backend
        self.store = store
    }

    public func activate(userID: UUID) async throws -> ContentSyncActivation {
        self.userID = userID
        try await store.activateOwner(userID: userID)
        let needsBootstrap = try await store.needsBootstrap(userID: userID)
        if needsBootstrap {
            try await bootstrap()
        }
        startListener()
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
        listenerTask?.cancel()
        listenerTask = nil
        userID = nil
    }

    public func synchronize() async throws {
        guard userID != nil else { return }
        if isSynchronizing {
            needsAnotherPass = true
            return
        }
        isSynchronizing = true
        defer { isSynchronizing = false }
        repeat {
            needsAnotherPass = false
            try await flushOutbox()
            try await pullChanges()
        } while needsAnotherPass
    }

    private func bootstrap() async throws {
        var cursor: String?
        var records: [RemoteContentRecord] = []
        var syncCursor: String?
        repeat {
            let page = try await backend.contentPage(cursor: cursor, limit: 500)
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
        while true {
            let pending = try await store.takePending(limit: 50)
            guard !pending.isEmpty else { return }
            do {
                let commands = try pending.map(Self.command)
                let results: [BackendContentCommandResult]
                do {
                    results = try await backend.submitContentCommands(commands)
                } catch let error as BackendClientError {
                    // During a rolling backend upgrade, an older strict content schema rejects
                    // the newly optional activity profile before applying any command. Keep login
                    // usable by retrying that same idempotent batch without only the new field.
                    guard error.code == "INVALID_REQUEST",
                          let compatible = Self.withoutActivityProfiles(commands)
                    else { throw error }
                    results = try await backend.submitContentCommands(compatible)
                }
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
                        try await store.reject(
                            commandID: result.commandId,
                            code: error.code,
                            current: try Self.currentRecord(from: error.details)
                        )
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

    private static func withoutActivityProfiles(
        _ commands: [BackendContentCommand]
    ) -> [BackendContentCommand]? {
        var removedAny = false
        let compatible = commands.map { command in
            guard command.resourceType == ContentResourceKind.character.rawValue,
                  case .object(var payload)? = command.payload,
                  case .object(var card)? = payload["card"],
                  card.removeValue(forKey: "activityProfile") != nil
            else { return command }
            removedAny = true
            payload["card"] = .object(card)
            return BackendContentCommand(
                commandID: command.commandId,
                expectedVersion: command.expectedVersion,
                operation: command.operation,
                parentID: command.parentId,
                payload: .object(payload),
                resourceID: command.resourceId,
                resourceType: command.resourceType
            )
        }
        return removedAny ? compatible : nil
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
