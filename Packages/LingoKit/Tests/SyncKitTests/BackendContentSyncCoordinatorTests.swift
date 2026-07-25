import BackendKit
import Foundation
import PersistenceKit
import Testing
@testable import SyncKit

@Suite("Backend content sync coordinator")
struct BackendContentSyncCoordinatorTests {
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
        private(set) var expectedVersions: [Int] = []

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

    @Test("首次迁移本地内容，后续修改按服务器版本递增")
    func migratesAndUpdates() async throws {
        let userID = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456790")!
        let transport = ContentTransport()
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

        try await coordinator.activate(userID: userID)
        #expect(await transport.expectedVersions == [0])

        try await roster.setDifficulty(characterID: characterID, level: .advanced)
        try await coordinator.synchronize()
        #expect(await transport.expectedVersions == [0, 1])
        #expect(try await syncStore.takePending().isEmpty)
        await coordinator.deactivate()
    }
}

