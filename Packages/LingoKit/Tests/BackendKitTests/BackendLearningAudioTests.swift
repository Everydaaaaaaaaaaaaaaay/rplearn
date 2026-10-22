import CryptoKit
import Foundation
import Testing
@testable import BackendKit

@Suite("学习音频的受限下载")
struct BackendLearningAudioTests {
    private final class Store: AuthCredentialStore, @unchecked Sendable {
        func load() throws -> StoredAuthCredential? { nil }
        func save(_ credential: StoredAuthCredential) throws {}
        func remove() throws {}
    }
    private actor Transport: BackendTransport {
        let audio = Data(repeating: 7, count: 1200)
        var requests: [URLRequest] = []
        var corrupt = false
        var scheme = "https"
        func setCorrupt() { corrupt = true }
        func setInsecure() { scheme = "http" }
        var hash: String { SHA256.hash(data: audio).map { String(format: "%02x", $0) }.joined() }
        func data(for request: URLRequest) async throws -> BackendTransportResponse {
            requests.append(request)
            let body: Data
            if request.url?.path == "/v1/auth/login" {
                body = Data(#"{"accessToken":"test-token","accessTokenExpiresIn":900,"tokenType":"Bearer","refreshToken":"test-refresh","refreshTokenExpiresAt":"2036-01-02T00:00:00Z","sessionId":"10000000-0000-0000-0000-000000000001","userId":"20000000-0000-0000-0000-000000000001"}"#.utf8)
            } else if request.url?.path.contains("/speech/") == true {
                body = try JSONSerialization.data(withJSONObject: ["assetId": "audio.\(hash)", "segments": [["text": "Water, please.", "pauseAfterMs": corrupt ? -1 : 3000], ["text": "Question: What would the speaker like?", "pauseAfterMs": 0]]])
            } else if request.url?.host == "assets.example.com" {
                body = corrupt ? Data(repeating: 8, count: audio.count) : audio
            } else {
                body = try JSONSerialization.data(withJSONObject: ["assetId": "audio.\(hash)", "sha256": hash, "byteSize": audio.count, "durationMs": 1000, "contentType": "audio/wav", "url": "\(scheme)://assets.example.com/audio?signature=test", "expiresAt": "2036-01-01T00:00:00Z"])
            }
            return BackendTransportResponse(data: body, headers: [:], statusCode: 200)
        }
    }
    private func client(_ transport: Transport) async throws -> BackendClient {
        let client = BackendClient(configuration: BackendConfiguration(baseURL: URL(string: "https://api.example.com")!), credentialStore: Store(), transport: transport)
        _ = try await client.login(email: "audio@example.com", password: "test-only", device: BackendDevice(appVersion: "1", deviceID: "audio-test", deviceName: "工程测试"))
        return client
    }
    @Test("音频请求不转发账号令牌，长度和哈希必须吻合")
    func verifiedDownload() async throws {
        let transport = Transport(); let client = try await client(transport)
        let data = try await client.learningAudio(UUID(), questionID: "listen", assetID: "audio.\(await transport.hash)")
        #expect(data.count == 1200)
        let requests = await transport.requests
        let grant = try #require(requests.first { $0.url?.path.contains("/audio/listen") == true })
        #expect(grant.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        let query = URLComponents(url: try #require(grant.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(query == [URLQueryItem(name: "assetId", value: "audio.\(await transport.hash)")])
        let asset = try #require(requests.first { $0.url?.host == "assets.example.com" })
        #expect(asset.value(forHTTPHeaderField: "Authorization") == nil)
        await transport.setCorrupt()
        await #expect(throws: BackendClientError.self) { try await client.learningAudio(UUID(), questionID: "listen", assetID: "audio.\(await transport.hash)") }
    }
    @Test("实时听力只取鉴权脚本，校验题目资源和停顿，无媒体下载")
    func liveScript() async throws {
        let transport = Transport(); let client = try await client(transport)
        let script = try await client.learningSpeech(UUID(), questionID: "listen", assetID: "audio.\(await transport.hash)")
        #expect(script.segments.first?.pauseAfterMs == 3000)
        let requests = await transport.requests
        #expect(requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(requests.allSatisfy { $0.url?.host == "api.example.com" })
        await transport.setCorrupt()
        await #expect(throws: BackendClientError.self) { try await client.learningSpeech(UUID(), questionID: "listen", assetID: "audio.\(await transport.hash)") }
    }
    @Test("拒绝不安全资源地址和与冻结题目不一致的资源身份")
    func refusesInvalidGrant() async throws {
        let transport = Transport(); let client = try await client(transport)
        await #expect(throws: BackendClientError.self) { try await client.learningAudio(UUID(), questionID: "listen", assetID: "different") }
        await transport.setInsecure()
        await #expect(throws: BackendClientError.self) { try await client.learningAudio(UUID(), questionID: "listen", assetID: "audio.\(await transport.hash)") }
        #expect(await transport.requests.allSatisfy { $0.url?.host != "assets.example.com" })
    }
}
