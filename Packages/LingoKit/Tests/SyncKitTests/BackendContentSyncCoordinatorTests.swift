import BackendKit
import Foundation
import PersistenceKit
import Testing
@testable import SyncKit

@Suite("Backend content sync coordinator")
struct BackendContentSyncCoordinatorTests {
    private struct OfflineTransport: BackendTransport {
        func data(for request: URLRequest) async throws -> BackendTransportResponse {
            throw BackendClientError.transport("offline")
        }
    }

    private final class MemoryCredentials: AuthCredentialStore, @unchecked Sendable {
        private let credential: StoredAuthCredential

        init(userID: UUID) {
            credential = StoredAuthCredential(
                refreshToken: "refresh",
                refreshTokenExpiresAt: Date(timeIntervalSince1970: 1_893_456_000),
                sessionID: UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456789")!,
                userID: userID
            )
        }

        func load() throws -> StoredAuthCredential? { credential }
        func remove() throws {}
        func save(_ credential: StoredAuthCredential) throws {}
    }

    private actor ContentTransport: BackendTransport {
        private(set) var activityProfileAttempts: [Bool] = []
        private(set) var expectedVersions: [Int] = []
        private var fault: String
        init(fault: String = "none") { self.fault = fault }

        func data(for request: URLRequest) async throws -> BackendTransportResponse {
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/v1/auth/refresh"):
                return json(
                    [
                        "accessToken": "access",
                        "accessTokenExpiresIn": 900,
                        "refreshToken": "rotated",
                        "refreshTokenExpiresAt": "2030-01-01T00:00:00.000Z",
                        "sessionId": "019c0123-4567-789a-8bcd-ef0123456789",
                        "tokenType": "Bearer",
                        "userId": "019c0123-4567-789a-8bcd-ef0123456790",
                    ]
                )
            case ("GET", "/v1/content/records"):
                return json(
                    [
                        "hasMore": false,
                        "nextCursor": NSNull(),
                        "records": [],
                        "syncCursor": "content-sync-cursor",
                    ]
                )
            case ("POST", "/v1/content/commands"):
                let body = try #require(request.httpBody)
                let object = try #require(
                    JSONSerialization.jsonObject(with: body) as? [String: Any]
                )
                let commands = try #require(
                    object["commands"] as? [[String: Any]]
                )
                let hasActivityProfile = commands.contains { command in
                    guard let payload = command["payload"] as? [String: Any],
                          let card = payload["card"] as? [String: Any]
                    else { return false }
                    return card["activityProfile"] != nil
                }
                activityProfileAttempts.append(hasActivityProfile)
                if fault == "legacyActivityProfile", hasActivityProfile {
                    fault = "none"
                    return json(
                        [
                            "code": "INVALID_REQUEST",
                            "message": "The request is invalid.",
                            "requestId": "legacy-content-schema",
                        ],
                        status: 400
                    )
                }
                let results = commands.map { command -> [String: Any] in
                    let expected = command["expectedVersion"] as? Int ?? -1
                    expectedVersions.append(expected)
                    return [
                        "commandId": command["commandId"] as Any,
                        "record": [
                            "createdAt": "2026-07-26T00:00:00.000Z",
                            "deletedAt": NSNull(),
                            "parentId": command["parentId"] ?? NSNull(),
                            "payload": command["payload"] as Any,
                            "resourceId": command["resourceId"] as Any,
                            "resourceType": command["resourceType"] as Any,
                            "updatedAt": "2026-07-26T00:00:00.000Z",
                            "version": expected + 1,
                        ],
                        "status": "applied",
                    ]
                }
                if fault != "none", var first = results.first {
                    let mode = fault
                    fault = "none"
                    if mode == "malformed" { first["status"] = "unexpected" }
                    if mode == "wrongCommand" { first["commandId"] = UUID().uuidString }
                    if mode == "wrongResource", var record = first["record"] as? [String: Any] {
                        record["resourceId"] = UUID().uuidString
                        first["record"] = record
                    }
                    return json(["results": [first]])
                }
                return json(["results": results])
            case ("GET", "/v1/sync/changes"):
                return json(
                    [
                        "changes": [],
                        "hasMore": false,
                        "nextCursor": "content-sync-cursor",
                    ]
                )
            default:
                return json(
                    [
                        "code": "NOT_FOUND",
                        "message": "not found",
                        "requestId": "request",
                    ],
                    status: 404
                )
            }
        }

        private func json(
            _ object: Any,
            status: Int = 200
        ) -> BackendTransportResponse {
            BackendTransportResponse(
                data: try! JSONSerialization.data(withJSONObject: object),
                headers: [:],
                statusCode: status
            )
        }
    }

    @Test("同步异常回执可重试，成功后按服务器版本递增", arguments: ["none", "malformed", "wrongCommand", "wrongResource"])
    func migratesAndUpdates(fault: String) async throws {
        let userID = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456790")!
        let transport = ContentTransport(fault: fault)
        let backend = BackendClient(
            configuration: BackendConfiguration(
                baseURL: URL(string: "https://api.example.com")!
            ),
            credentialStore: MemoryCredentials(userID: userID),
            transport: transport
        )
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let roster = RosterStore(modelContainer: container)
        let syncStore = ContentSyncStore(modelContainer: container)
        let characterID = try await roster.addCharacter(
            card: CharacterCard(
                name: "Alice",
                age: 28,
                gender: .female,
                nationality: "British",
                regionID: "london",
                occupation: "Guide",
                hobbies: ["books"],
                appearance: "Brown hair",
                personality: "Warm"
            ),
            difficulty: .junior3,
            isFriend: true
        )
        let coordinator = BackendContentSyncCoordinator(
            backend: backend,
            store: syncStore
        )

        if fault == "none" {
            _ = try await coordinator.activate(userID: userID)
        } else {
            do {
                _ = try await coordinator.activate(userID: userID)
                Issue.record("Malformed receipt must not acknowledge an upload")
            } catch {
                #expect(error is BackendClientError)
            }
            try await coordinator.synchronize()
        }
        let expected = fault == "none" ? [0] : [0, 0]
        #expect(await transport.expectedVersions == expected)

        try await roster.setDifficulty(characterID: characterID, level: .advanced)
        try await coordinator.synchronize()
        #expect(await transport.expectedVersions == expected + [1])
        #expect(try await syncStore.takePending().isEmpty)
        await coordinator.deactivate()
    }

    @Test("旧服务端不识别作息字段时登录同步降级重试且保留本地设定")
    func retriesAgainstLegacyActivityProfileSchema() async throws {
        let userID = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456790")!
        let transport = ContentTransport(fault: "legacyActivityProfile")
        let backend = BackendClient(
            configuration: BackendConfiguration(
                baseURL: URL(string: "https://api.example.com")!
            ),
            credentialStore: MemoryCredentials(userID: userID),
            transport: transport
        )
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let roster = RosterStore(modelContainer: container)
        let syncStore = ContentSyncStore(modelContainer: container)
        let expectedProfile = NPCActivityProfile(
            timeZoneIdentifier: "Europe/London",
            rhythm: .earlyBird,
            focusDurationMinutes: 8
        )
        let characterID = try await roster.addCharacter(
            card: CharacterCard(
                name: "Alice",
                age: 28,
                gender: .female,
                nationality: "British",
                regionID: "london",
                occupation: "Guide",
                hobbies: ["books"],
                appearance: "Brown hair",
                personality: "Warm",
                activityProfile: expectedProfile
            ),
            difficulty: .junior3,
            isFriend: true
        )
        let coordinator = BackendContentSyncCoordinator(
            backend: backend,
            store: syncStore
        )

        _ = try await coordinator.activate(userID: userID)

        #expect(await transport.activityProfileAttempts == [true, false])
        #expect(try await syncStore.takePending().isEmpty)
        #expect(try await roster.character(id: characterID)?.card.activityProfile == expectedProfile)
        await coordinator.deactivate()
    }

    @Test("完成过内容引导的账号可在断网时使用缓存")
    func bootstrappedContentActivatesOffline() async throws {
        let userID = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456790")!
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let store = ContentSyncStore(modelContainer: container)
        try await store.activateOwner(userID: userID)
        try await store.bootstrap(records: [], syncCursor: "cached-content-cursor")
        let backend = BackendClient(
            configuration: BackendConfiguration(baseURL: URL(string: "https://api.example.com")!),
            credentialStore: MemoryCredentials(userID: userID),
            transport: OfflineTransport()
        )
        let coordinator = BackendContentSyncCoordinator(backend: backend, store: store)

        #expect(try await coordinator.activate(userID: userID) == .offlineCache)
        await coordinator.deactivate()
    }

    @Test("首次内容同步没有缓存时断网不会伪装成可用")
    func firstContentBootstrapRequiresNetwork() async throws {
        let userID = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456790")!
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let backend = BackendClient(
            configuration: BackendConfiguration(baseURL: URL(string: "https://api.example.com")!),
            credentialStore: MemoryCredentials(userID: userID),
            transport: OfflineTransport()
        )
        let coordinator = BackendContentSyncCoordinator(
            backend: backend,
            store: ContentSyncStore(modelContainer: container)
        )

        do {
            _ = try await coordinator.activate(userID: userID)
            Issue.record("首次内容同步必须联网完成")
        } catch let error as BackendClientError {
            #expect(error == .transport("offline"))
        }
        await coordinator.deactivate()
    }
}
