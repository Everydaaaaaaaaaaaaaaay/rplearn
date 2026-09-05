import Foundation
import Testing
@testable import BackendKit

@Suite("BackendClient authentication")
struct BackendClientTests {
    private struct Probe: Decodable, Sendable {
        let ok: Bool
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
            default:
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

    @Test("NPC lookup includes the user's token for their private avatar binding")
    func npcLookupAuthenticates() async throws {
        let transport = MockTransport()
        let client = BackendClient(
            configuration: BackendConfiguration(baseURL: URL(string: "https://api.example.com")!),
            credentialStore: MemoryCredentialStore(),
            transport: transport
        )
        _ = try await client.login(
            email: "traveler@example.com", password: "test-password",
            device: BackendDevice(appVersion: "1.0", deviceID: "test-device", deviceName: "Test")
        )
        // The transport intentionally returns 404; this assertion is about account scoping.
        _ = try? await client.findPublicNPC(travelerID: "12345678901")
        let requests = await transport.requests
        #expect(requests.last?.url?.path == "/v1/npcs/by-traveler-id/12345678901")
        #expect(requests.last?.value(forHTTPHeaderField: "authorization") == "Bearer login-access")
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
