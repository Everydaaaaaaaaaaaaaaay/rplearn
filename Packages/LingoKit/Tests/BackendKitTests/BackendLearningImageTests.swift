import CryptoKit
import Foundation
import Testing
@testable import BackendKit

@Suite("学习图片的受限下载")
struct BackendLearningImageTests {
    private final class Store: AuthCredentialStore, @unchecked Sendable {
        func load() throws -> StoredAuthCredential? { nil }
        func save(_ credential: StoredAuthCredential) throws {}
        func remove() throws {}
    }
    private actor Transport: BackendTransport {
        let image: Data = {
            var bytes = [UInt8](repeating: 0, count: 1200)
            bytes.replaceSubrange(0..<8, with: [137, 80, 78, 71, 13, 10, 26, 10])
            bytes.replaceSubrange(12..<16, with: Array("IHDR".utf8))
            bytes[19] = 128; bytes[23] = 128
            return Data(bytes)
        }()
        var requests: [URLRequest] = []
        var corrupt = false
        var scheme = "https"
        func setCorrupt() { corrupt = true }
        func setInsecure() { scheme = "http" }
        var hash: String { SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined() }
        func data(for request: URLRequest) async throws -> BackendTransportResponse {
            requests.append(request)
            let body: Data
            if request.url?.path == "/v1/auth/login" {
                body = Data(#"{"accessToken":"test-token","accessTokenExpiresIn":900,"tokenType":"Bearer","refreshToken":"test-refresh","refreshTokenExpiresAt":"2036-01-02T00:00:00Z","sessionId":"10000000-0000-0000-0000-000000000001","userId":"20000000-0000-0000-0000-000000000001"}"#.utf8)
            } else if request.url?.host == "assets.example.com" {
                body = corrupt ? Data(repeating: 8, count: image.count) : image
            } else {
                body = try JSONSerialization.data(withJSONObject: ["assetId": "image.\(hash)", "sha256": hash, "byteSize": image.count, "width": 128, "height": 128, "contentType": "image/png", "url": "\(scheme)://assets.example.com/image?signature=test", "expiresAt": "2036-01-01T00:00:00Z"])
            }
            return BackendTransportResponse(data: body, headers: [:], statusCode: 200)
        }
    }
    private func client(_ transport: Transport) async throws -> BackendClient {
        let client = BackendClient(configuration: BackendConfiguration(baseURL: URL(string: "https://api.example.com")!), credentialStore: Store(), transport: transport)
        _ = try await client.login(email: "image@example.com", password: "test-only", device: BackendDevice(appVersion: "1", deviceID: "image-test", deviceName: "工程测试"))
        return client
    }
    @Test("图片请求不转发账号令牌，长度和哈希必须吻合")
    func verifiedDownload() async throws {
        let transport = Transport(); let client = try await client(transport)
        let data = try await client.learningImage(UUID(), questionID: "listen", assetID: "image.\(await transport.hash)")
        #expect(data.count == 1200)
        let requests = await transport.requests
        let grant = try #require(requests.first { $0.url?.path.contains("/images/listen") == true })
        #expect(grant.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        let asset = try #require(requests.first { $0.url?.host == "assets.example.com" })
        #expect(asset.value(forHTTPHeaderField: "Authorization") == nil)
        await transport.setCorrupt()
        await #expect(throws: BackendClientError.self) { try await client.learningImage(UUID(), questionID: "listen", assetID: "image.\(await transport.hash)") }
    }
    @Test("拒绝不安全资源地址和与冻结题目不一致的资源身份")
    func refusesInvalidGrant() async throws {
        let transport = Transport(); let client = try await client(transport)
        await #expect(throws: BackendClientError.self) { try await client.learningImage(UUID(), questionID: "listen", assetID: "different") }
        await transport.setInsecure()
        await #expect(throws: BackendClientError.self) { try await client.learningImage(UUID(), questionID: "listen", assetID: "image.\(await transport.hash)") }
        #expect(await transport.requests.allSatisfy { $0.url?.host != "assets.example.com" })
    }
}
