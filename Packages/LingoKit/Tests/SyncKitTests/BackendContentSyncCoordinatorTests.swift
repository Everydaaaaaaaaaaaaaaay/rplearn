import CoreKit
import DomainKit
import BackendKit
import Foundation
import PersistenceKit
import Testing
@testable import SyncKit

@Suite("Backend content sync coordinator")
struct BackendContentSyncCoordinatorTests {
    private actor OfflineTransport: BackendTransport {
        private(set) var requestCount = 0
        func data(for request: URLRequest) async throws -> BackendTransportResponse {
            requestCount += 1
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
        private var learningCycle = UUID()
        private var learningRevision = 1
        private var learningUnavailable = false
        func setLearningCycle(_ cycle: UUID, revision: Int) { learningCycle = cycle; learningRevision = revision }
        func setLearningUnavailable() { learningUnavailable = true }
        private var heldPulls: [CheckedContinuation<Void, Never>] = []
        private var shouldHoldPulls = false
        private(set) var pullCount = 0
        func holdPulls() { shouldHoldPulls = true }
        func waitingPulls() -> Int { heldPulls.count }
        func releasePulls() {
            shouldHoldPulls = false
            let waiting = heldPulls; heldPulls.removeAll()
            for waiter in waiting { waiter.resume() }
        }
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
            case ("GET", .some(let path)) where path.hasPrefix("/v1/learning/characters/"):
                if learningUnavailable { throw URLError(.notConnectedToInternet) }
                return json(["characterId": String(path.split(separator: "/").last!), "roleKey":"oliver", "cycleId":learningCycle.uuidString, "characters":0, "threshold":1000, "revision":learningRevision, "activeAttemptId":NSNull(), "level":"junior1", "availableUnits":0, "generationStatus":NSNull()])
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
                pullCount += 1
                if shouldHoldPulls { await withCheckedContinuation { heldPulls.append($0) } }
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

    private actor CompletionFlag {
        private(set) var done = false
        func finish() { done = true }
    }
    @Test("需要持久化保证的调用等待进行中的同步及下一轮，不提前放行模型请求")
    func waitsForInFlightSynchronization() async throws {
        let user = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456790")!
        let transport = ContentTransport()
        let backend = BackendClient(configuration: .init(baseURL: URL(string: "https://api.example.com")!), credentialStore: MemoryCredentials(userID: user), transport: transport)
        let store = ContentSyncStore(modelContainer: try ModelContainerFactory.makeContainer(inMemory: true))
        let coordinator = BackendContentSyncCoordinator(backend: backend, store: store)
        _ = try await coordinator.activate(userID: user)
        let before = await transport.pullCount
        await transport.holdPulls()
        let initial = Task { try await coordinator.synchronize() }
        for _ in 0..<100 {
            if await transport.waitingPulls() > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await transport.waitingPulls() > 0)
        let flag = CompletionFlag()
        let waiting = Task { try await coordinator.synchronizeAndWait(); await flag.finish() }
        try await Task.sleep(for: .milliseconds(30))
        #expect(await flag.done == false)
        await transport.releasePulls()
        try await initial.value
        try await waiting.value
        #expect(await flag.done)
        #expect(await transport.pullCount >= before + 2)
        await coordinator.deactivate()
    }

    @Test("周期缓存按账号隔离，离线保留原周期，回复始终使用消息保存时的周期")
    func learningCycleIsolationAndOfflineCapture() async throws {
        let user = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456790")!
        let character = UUID(), first = UUID(), second = UUID()
        let transport = ContentTransport()
        await transport.setLearningCycle(first, revision: 1)
        let backend = BackendClient(configuration: .init(baseURL: URL(string: "https://api.example.com")!), credentialStore: MemoryCredentials(userID: user), transport: transport)
        let store = ContentSyncStore(modelContainer: try ModelContainerFactory.makeContainer(inMemory: true))
        let content = BackendContentSyncCoordinator(backend: backend, store: store)
        _ = try await content.activate(userID: user)
        let suite = "learning-tests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let learning = LearningChatCoordinator(accountID: user, backend: backend, contentSync: content, defaultsSuiteName: suite)
        await learning.refresh(characterID: character)
        let captured = try #require(await learning.userOrigin(characterID: character))
        #expect(captured == .user(cycleID: first))
        await transport.setLearningCycle(second, revision: 2)
        await learning.refresh(characterID: character)
        #expect(await learning.userOrigin(characterID: character) == .user(cycleID: second))
        let message = MessageDTO(id: UUID(), role: .user, kind: .text, text: "Offline message", orderIndex: 0, learningOrigin: captured)
        let context = try await learning.prepareReply(conversationID: UUID(), userMessage: message)
        #expect(context?.cycleId == first)
        await transport.setLearningCycle(first, revision: 1)
        await learning.refresh(characterID: character)
        #expect(await learning.userOrigin(characterID: character) == .user(cycleID: second))
        await transport.setLearningUnavailable()
        await learning.refresh(characterID: character)
        #expect(await learning.userOrigin(characterID: character) == .user(cycleID: second))
        await learning.challengeCompleted(characterID: character)
        #expect(await learning.userOrigin(characterID: character) == nil)
        let other = LearningChatCoordinator(accountID: UUID(), backend: backend, contentSync: content, defaultsSuiteName: suite)
        #expect(await other.userOrigin(characterID: character) == nil)
        await learning.deactivate()
        #expect(await learning.userOrigin(characterID: character) == nil)
        await content.deactivate()
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

    @Test("完成内容引导的账号支持离线与优先展示", arguments: [false, true])
    func bootstrappedContentActivatesOffline(preferCache: Bool) async throws {
        let userID = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456790")!
        let transport = OfflineTransport()
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let store = ContentSyncStore(modelContainer: container)
        try await store.activateOwner(userID: userID)
        try await store.bootstrap(records: [], syncCursor: "cached-content-cursor")
        let backend = BackendClient(
            configuration: BackendConfiguration(baseURL: URL(string: "https://api.example.com")!),
            credentialStore: MemoryCredentials(userID: userID),
            transport: transport
        )
        let coordinator = BackendContentSyncCoordinator(backend: backend, store: store)

        #expect(try await coordinator.activate(userID: userID, preferCache: preferCache) == (preferCache ? .cached : .offlineCache))
        #expect(await transport.requestCount == (preferCache ? 0 : 1))
        await coordinator.deactivate()
    }

    @Test("首次内容同步不能跳过联网", arguments: [false, true])
    func firstContentBootstrapRequiresNetwork(preferCache: Bool) async throws {
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
            _ = try await coordinator.activate(userID: userID, preferCache: preferCache)
            Issue.record("首次内容同步必须联网完成")
        } catch let error as BackendClientError {
            #expect(error == .transport("offline"))
        }
        await coordinator.deactivate()
    }
}
