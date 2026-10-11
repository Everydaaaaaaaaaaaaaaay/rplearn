import Foundation
import Testing
@testable import BackendKit

@Suite("备考方向的独立服务合同")
struct BackendLearningDirectionsTests {
    private final class Store: AuthCredentialStore, @unchecked Sendable {
        func load() throws -> StoredAuthCredential? { nil }
        func save(_ credential: StoredAuthCredential) throws {}
        func remove() throws {}
    }

    private actor Transport: BackendTransport {
        enum Mode: Sendable { case success, conflict, offline, malformed }
        var requests: [URLRequest] = []
        private var mode: Mode = .success

        func setMode(_ mode: Mode) { self.mode = mode }

        func data(for request: URLRequest) async throws -> BackendTransportResponse {
            requests.append(request)
            if request.url?.path == "/v1/auth/login" {
                let body = #"{"accessToken":"direction-token","accessTokenExpiresIn":900,"tokenType":"Bearer","refreshToken":"direction-refresh","refreshTokenExpiresAt":"2036-01-02T00:00:00Z","sessionId":"10000000-0000-0000-0000-000000000001","userId":"20000000-0000-0000-0000-000000000001"}"#
                return BackendTransportResponse(data: Data(body.utf8), headers: [:], statusCode: 200)
            }
            switch mode {
            case .success:
                let body = #"{"selectedDirection":"future-exam","revision":7,"directions":[{"id":"general","title":"通用英语","status":"available"},{"id":"future-exam","title":"新考试方向","status":"previewOnly"}]}"#
                return BackendTransportResponse(data: Data(body.utf8), headers: [:], statusCode: 200)
            case .conflict:
                let body = #"{"code":"LEARNING_DIRECTION_CONFLICT","message":"备考方向已在其他设备更改，请刷新后重试。","requestId":"direction-conflict"}"#
                return BackendTransportResponse(data: Data(body.utf8), headers: [:], statusCode: 409)
            case .offline:
                throw BackendClientError.transport("测试网络不可用")
            case .malformed:
                return BackendTransportResponse(data: Data(#"{"revision":7,"directions":[]}"#.utf8), headers: [:], statusCode: 200)
            }
        }
    }

    private func client(_ transport: Transport) async throws -> BackendClient {
        let client = BackendClient(
            configuration: BackendConfiguration(baseURL: URL(string: "https://api.example.com")!),
            credentialStore: Store(), transport: transport
        )
        _ = try await client.login(email: "direction@example.com", password: "test-only", device: BackendDevice(appVersion: "1", deviceID: "direction-test", deviceName: "方向合同测试"))
        return client
    }

    @Test("未知方向与状态原样解码，公开构造器不推断通用英语")
    func preservesUnknownValues() throws {
        let original = LearningDirections(selectedDirection: "future-exam", revision: 0, directions: [
            .init(id: "future-exam", title: "新考试方向", status: "previewOnly"),
            .init(id: "general", title: "通用英语", status: "available"),
            .init(id: "entrance-english-1", title: "考研英语一", status: "inReview")
        ])
        let decoded = try JSONDecoder().decode(LearningDirections.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(!decoded.directions[0].isAvailable)
        #expect(decoded.directions[1].isAvailable)
        #expect(!decoded.directions[2].isAvailable)
    }

    @Test("读取和选择使用认证方向接口，保留请求身份与预期修订")
    func authenticatedRequestContract() async throws {
        let transport = Transport()
        let backend = try await client(transport)
        let service: any LearningDirectionServing = backend
        let initial = try await service.learningDirections()
        #expect(initial.selectedDirection == "future-exam")
        #expect(initial.directions.last?.title == "新考试方向")
        let requestID = UUID()
        for _ in 0..<2 {
            let selected = try await service.selectLearningDirection("ielts-academic", requestID: requestID, expectedRevision: 6)
            #expect(selected.revision == 7)
            #expect(selected.selectedDirection == "future-exam")
        }
        let requests = await transport.requests.filter { $0.url?.path == "/v1/learning/directions" }
        #expect(requests.map(\.httpMethod) == ["GET", "POST", "POST"])
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer direction-token" })
        for request in requests.dropFirst() {
            let body = try #require(request.httpBody)
            let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(Set(object.keys) == Set(["direction", "requestId", "expectedRevision"]))
            #expect(object["direction"] as? String == "ielts-academic")
            #expect(object["expectedRevision"] as? Int == 6)
            #expect((object["requestId"] as? String).flatMap(UUID.init(uuidString:)) == requestID)
        }
    }

    @Test("并发选择冲突上抛，不自动刷新或改选通用英语")
    func conflictDoesNotFallback() async throws {
        let transport = Transport()
        let backend = try await client(transport)
        await transport.setMode(.conflict)
        do {
            _ = try await backend.selectLearningDirection("entrance-english-2", requestID: UUID(), expectedRevision: 0)
            Issue.record("并发选择冲突未上抛")
        } catch let error as BackendClientError {
            #expect(error == .api(code: "LEARNING_DIRECTION_CONFLICT", message: "备考方向已在其他设备更改，请刷新后重试。", requestID: "direction-conflict", status: 409))
        }
        let requests = await transport.requests.filter { $0.url?.path == "/v1/learning/directions" }
        #expect(requests.count == 1)
        #expect(requests.first?.httpMethod == "POST")
    }

    @Test("断网和缺失所选方向的响应均失败，不构造默认状态")
    func invalidReadsDoNotFallback() async throws {
        let transport = Transport()
        let backend = try await client(transport)
        await transport.setMode(.offline)
        await #expect(throws: BackendClientError.self) { try await backend.learningDirections() }
        await transport.setMode(.malformed)
        await #expect(throws: BackendClientError.self) { try await backend.learningDirections() }
        let requests = await transport.requests.filter { $0.url?.path == "/v1/learning/directions" }
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.httpMethod == "GET" })
    }
}
