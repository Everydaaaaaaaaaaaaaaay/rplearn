import Foundation
import Testing
@testable import BackendKit

@Suite("BackendClient authentication")
struct BackendClientTests {
    private struct Probe: Decodable, Sendable {
        let ok: Bool
    }

    @Test("旧版钥匙串凭据缺少 Apple 用户标识时仍可解码")
    func legacyCredentialRemainsDecodable() throws {
        let data = Data(
            #"{"refreshToken":"legacy-refresh","refreshTokenExpiresAt":600000000,"sessionID":"019c0123-4567-789a-8bcd-ef0123456789","userID":"019c0123-4567-789a-8bcd-ef0123456790"}"#.utf8
        )
        let credential = try JSONDecoder().decode(StoredAuthCredential.self, from: data)
        #expect(credential.refreshToken == "legacy-refresh")
        #expect(credential.appleUserID == nil)
    }

    private final class MemoryCredentialStore: AuthCredentialStore, @unchecked Sendable {
        private let lock = NSLock()
        private var value: StoredAuthCredential?

        init(_ value: StoredAuthCredential? = nil) {
            self.value = value
        }

        func load() throws -> StoredAuthCredential? {
            lock.withLock { value }
        }

        func remove() throws {
            lock.withLock { value = nil }
        }

        func save(_ credential: StoredAuthCredential) throws {
            lock.withLock { value = credential }
        }
    }

    private actor MockTransport: BackendTransport {
        private(set) var refreshCount = 0
        private(set) var requests: [URLRequest] = []
        var refreshStatus = 200

        func setRefreshStatus(_ status: Int) {
            refreshStatus = status
        }

        func data(for request: URLRequest) async throws -> BackendTransportResponse {
            requests.append(request)
            switch request.url?.path {
            case "/v1/auth/guest":
                return json(Self.tokenJSON(access: "guest-access", refresh: "guest-refresh"))
            case "/v1/auth/login":
                return json(Self.tokenJSON(access: "login-access", refresh: "login-refresh"))
            case "/v1/auth/refresh":
                refreshCount += 1
                if refreshStatus == 401 {
                    return json(
                        #"{"code":"INVALID_REFRESH_TOKEN","message":"invalid","requestId":"req-1"}"#,
                        status: 401
                    )
                }
                return json(Self.tokenJSON(access: "renewed-access", refresh: "rotated-refresh"))
            case "/v1/probe":
                return json(#"{"ok":true}"#)
            case "/v1/account/identities":
                return json(
                    #"{"identities":[{"createdAt":"2026-09-08T00:00:00.000Z","displayName":null,"email":"traveler@example.com","emailVerified":true,"id":"019c0123-4567-789a-8bcd-ef0123456791","provider":"email","updatedAt":"2026-09-08T00:00:00.000Z"}]}"#
                )
            case "/v1/auth/sessions":
                return json(
                    #"{"sessions":[{"appVersion":"1.0","createdAt":"2026-09-08T00:00:00.000Z","current":true,"deviceId":"test-device-id","deviceName":"Test iPhone","id":"019c0123-4567-789a-8bcd-ef0123456789","lastSeenAt":"2026-09-08T00:00:00.000Z","platform":"ios"}]}"#
                )
            case "/v1/account":
                return json(
                    #"{"cancellationToken":null,"purgeAt":"2026-09-08T00:00:00.000Z","requestId":"019c0123-4567-789a-8bcd-ef0123456792","status":"scheduled"}"#,
                    status: 202
                )
            default:
                if request.url?.path.hasPrefix("/v1/auth/sessions/") == true ||
                    request.url?.path.hasPrefix("/v1/account/identities/") == true
                {
                    return json("", status: 204)
                }
                return json(
                    #"{"code":"NOT_FOUND","message":"not found","requestId":"req-2"}"#,
                    status: 404
                )
            }
        }

        private func json(_ string: String, status: Int = 200) -> BackendTransportResponse {
            BackendTransportResponse(
                data: Data(string.utf8),
                headers: ["x-request-id": "test-request"],
                statusCode: status
            )
        }

        private static func tokenJSON(access: String, refresh: String) -> String {
            """
            {
              "accessToken":"\(access)",
              "accessTokenExpiresIn":900,
              "refreshToken":"\(refresh)",
              "refreshTokenExpiresAt":"2030-01-01T00:00:00.000Z",
              "sessionId":"019c0123-4567-789a-8bcd-ef0123456789",
              "tokenType":"Bearer",
              "userId":"019c0123-4567-789a-8bcd-ef0123456790"
            }
            """
        }
    }

    @Test("并发游客请求只建立一个会话，匿名凭证不会变成已登录账号")
    func concurrentGuestSessionRemainsSeparate() async throws {
        let account = MemoryCredentialStore()
        let guest = MemoryCredentialStore()
        let transport = MockTransport()
        let client = BackendClient(
            configuration: BackendConfiguration(baseURL: URL(string: "https://api.example.com")!),
            credentialStore: account, transport: transport,
            guestCredentialStore: guest, guestInstallationKey: String(repeating: "a", count: 64)
        )
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    let result: Probe = try await client.sendWithGuestAccess(path: "/v1/probe", method: "POST", body: ["test": true], guestID: "legacy-device")
                    return result.ok
                }
            }
            for try await result in group { #expect(result) }
        }
        #expect(try account.load() == nil)
        #expect(try guest.load()?.refreshToken == "guest-refresh")
        #expect(try await client.cachedIdentity() == nil)
        let requests = await transport.requests
        #expect(requests.filter { $0.url?.path == "/v1/auth/guest" }.count == 1)
        #expect(requests.filter { $0.url?.path == "/v1/probe" }.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer guest-access" &&
            $0.value(forHTTPHeaderField: "x-lingotrip-guest-id") == nil
        })
    }

    @Test("过期游客会话用原安装凭据恢复，不污染账号凭证")
    func expiredGuestSessionRecovers() async throws {
        let account = MemoryCredentialStore()
        let guest = MemoryCredentialStore(StoredAuthCredential(
            refreshToken: "invalid-refresh",
            refreshTokenExpiresAt: Date(timeIntervalSince1970: 1_893_456_000),
            sessionID: UUID(), userID: UUID()
        ))
        let transport = MockTransport()
        await transport.setRefreshStatus(401)
        let installationKey = String(repeating: "b", count: 64)
        let client = BackendClient(
            configuration: BackendConfiguration(baseURL: URL(string: "https://api.example.com")!),
            credentialStore: account, transport: transport,
            guestCredentialStore: guest, guestInstallationKey: installationKey
        )
        let anonymous = try await client.anonymousClient()
        let probe: Probe = try await anonymous.get("/v1/probe")
        #expect(probe.ok)
        #expect(try account.load() == nil)
        let requests = await transport.requests
        let bootstrap = try #require(requests.first { $0.url?.path == "/v1/auth/guest" })
        let body = try #require(bootstrap.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["installationKey"] as? String == installationKey)
    }

    @Test("login stores only the refresh credential and authenticates later requests")
    func loginAndAuthenticate() async throws {
        let store = MemoryCredentialStore()
        let transport = MockTransport()
        let client = BackendClient(
            configuration: BackendConfiguration(baseURL: URL(string: "https://api.example.com")!),
            credentialStore: store,
            transport: transport
        )

        let identity = try await client.login(
            email: "traveler@example.com",
            password: "correct horse battery",
            device: BackendDevice(
                appVersion: "1.0",
                deviceID: "test-device-id",
                deviceName: "Test iPhone"
            )
        )
        #expect(identity.userID.uuidString.lowercased() == "019c0123-4567-789a-8bcd-ef0123456790")
        #expect(try store.load()?.refreshToken == "login-refresh")

        let probe: Probe = try await client.get("/v1/probe")
        #expect(probe.ok)
        let requests = await transport.requests
        #expect(requests.last?.value(forHTTPHeaderField: "authorization") == "Bearer login-access")
    }

    @Test("账号管理读取身份和设备，并在删除账号后清除本地凭据")
    func accountManagementLifecycle() async throws {
        let stored = StoredAuthCredential(
            refreshToken: "stored-refresh",
            refreshTokenExpiresAt: Date(timeIntervalSince1970: 1_893_456_000),
            sessionID: UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456789")!,
            userID: UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456790")!,
            appleUserID: "apple-user-1"
        )
        let store = MemoryCredentialStore(stored)
        let transport = MockTransport()
        let client = BackendClient(
            configuration: BackendConfiguration(baseURL: URL(string: "https://api.example.com")!),
            credentialStore: store,
            transport: transport
        )

        let identities = try await client.accountIdentities()
        let sessions = try await client.accountDeviceSessions()
        #expect(identities.map(\.provider) == ["email"])
        #expect(sessions.count == 1)
        #expect(sessions[0].current)

        try await client.unlinkIdentity(identities[0].id)
        try await client.revokeDeviceSession(sessions[0].id)
        let receipt = try await client.deleteAccount()
        #expect(receipt.status == "scheduled")
        #expect(try store.load() == nil)
    }

    @Test("concurrent requests share one refresh rotation")
    func singleFlightRefresh() async throws {
        let store = MemoryCredentialStore(
            StoredAuthCredential(
                refreshToken: "stored-refresh",
                refreshTokenExpiresAt: Date(timeIntervalSince1970: 1_893_456_000),
                sessionID: UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456789")!,
                userID: UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456790")!
            )
        )
        let transport = MockTransport()
        let client = BackendClient(
            configuration: BackendConfiguration(baseURL: URL(string: "https://api.example.com")!),
            credentialStore: store,
            transport: transport
        )

        async let first: Probe = client.get("/v1/probe")
        async let second: Probe = client.get("/v1/probe")
        let values = try await [first, second]
        let allRequestsSucceeded = values.allSatisfy { $0.ok }
        let refreshCount = await transport.refreshCount

        #expect(allRequestsSucceeded)
        #expect(refreshCount == 1)
        #expect(try store.load()?.refreshToken == "rotated-refresh")
    }

    @Test("invalid refresh removes the unusable local session")
    func invalidRefreshClearsSession() async throws {
        let store = MemoryCredentialStore(
            StoredAuthCredential(
                refreshToken: "invalid-refresh",
                refreshTokenExpiresAt: Date(timeIntervalSince1970: 1_893_456_000),
                sessionID: UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456789")!,
                userID: UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456790")!
            )
        )
        let transport = MockTransport()
        await transport.setRefreshStatus(401)
        let client = BackendClient(
            configuration: BackendConfiguration(baseURL: URL(string: "https://api.example.com")!),
            credentialStore: store,
            transport: transport
        )

        await #expect(throws: BackendClientError.self) {
            _ = try await client.restoreSession()
        }
        #expect(try store.load() == nil)
    }
}
