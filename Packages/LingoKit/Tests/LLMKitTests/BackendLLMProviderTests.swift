import BackendKit
import Foundation
import Testing
@testable import LLMKit

@Suite("Backend LLM provider")
struct BackendLLMProviderTests {
    private final class Credentials: AuthCredentialStore, @unchecked Sendable {
        func load() throws -> StoredAuthCredential? {
            StoredAuthCredential(
                refreshToken: "refresh",
                refreshTokenExpiresAt: Date(timeIntervalSince1970: 1_893_456_000),
                sessionID: UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456789")!,
                userID: UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456790")!
            )
        }

        func remove() throws {}
        func save(_ credential: StoredAuthCredential) throws {}
    }

    private actor Transport: BackendTransport {
        private(set) var aiBodies: [[String: AnySendable]] = []

        func data(for request: URLRequest) async throws -> BackendTransportResponse {
            switch request.url?.path {
            case "/v1/auth/refresh":
                return response(
                    """
                    {
                      "accessToken":"access",
                      "accessTokenExpiresIn":900,
                      "refreshToken":"rotated",
                      "refreshTokenExpiresAt":"2030-01-01T00:00:00.000Z",
                      "sessionId":"019c0123-4567-789a-8bcd-ef0123456789",
                      "tokenType":"Bearer",
                      "userId":"019c0123-4567-789a-8bcd-ef0123456790"
                    }
                    """
                )
            case "/v1/ai/completions":
                try capture(request)
                return response(
                    """
                    {
                      "content":"你好",
                      "model":"deepseek-v4-flash",
                      "requestId":"019c0123-4567-789a-8bcd-ef0123456791",
                      "usage":{"inputTokens":2,"outputTokens":2,"totalTokens":4}
                    }
                    """
                )
            case "/v1/ai/stream":
                try capture(request)
                return response(
                    """
                    event: metadata
                    data: {"model":"deepseek-v4-flash","providerRequestId":"provider"}

                    event: delta
                    data: {"text":"Hi"}

                    event: delta
                    data: {"text":"!"}

                    event: usage
                    data: {"inputTokens":2,"outputTokens":2,"totalTokens":4}

                    event: done
                    data: {}

                    """,
                    contentType: "text/event-stream"
                )
            default:
                return response(
                    #"{"code":"NOT_FOUND","message":"not found","requestId":"request"}"#,
                    status: 404
                )
            }
        }

        private func capture(_ request: URLRequest) throws {
            let object = try JSONSerialization.jsonObject(with: request.httpBody ?? Data())
            guard let dictionary = object as? [String: Any] else {
                throw LLMError.invalidResponse("test body")
            }
            aiBodies.append(dictionary.mapValues(AnySendable.init))
        }

        private func response(
            _ body: String,
            status: Int = 200,
            contentType: String = "application/json"
        ) -> BackendTransportResponse {
            BackendTransportResponse(
                data: Data(body.utf8),
                headers: ["content-type": contentType],
                statusCode: status
            )
        }
    }

    /// Test-only unchecked box around JSONSerialization values; inspected only inside the suite.
    private struct AnySendable: @unchecked Sendable {
        let value: Any

        init(_ value: Any) {
            self.value = value
        }
    }

    private func makeProvider(
        transport: Transport
    ) -> BackendLLMProvider {
        let client = BackendClient(
            configuration: BackendConfiguration(baseURL: URL(string: "https://api.example.com")!),
            credentialStore: Credentials(),
            transport: transport
        )
        return BackendLLMProvider(backend: client)
    }

    @Test("completion sends a stable task without provider configuration")
    func completion() async throws {
        let transport = Transport()
        let provider = makeProvider(transport: transport)
        let output = try await provider.complete(
            LLMRequest(
                task: .translation,
                tier: .deep,
                system: "Translate.",
                messages: [.user("hello")],
                maxTokens: 100,
                temperature: 1
            )
        )

        #expect(output == "你好")
        let body = try #require(await transport.aiBodies.last)
        #expect(body["task"]?.value as? String == "translation")
        #expect(body["maxOutputTokens"]?.value as? Int == 100)
        #expect(body["model"] == nil)
        #expect(body["temperature"] == nil)
        #expect(body["apiKey"] == nil)
    }

    @Test("JSON schema is constrained inline and stream events remain incremental")
    func schemaAndStream() async throws {
        let transport = Transport()
        let provider = makeProvider(transport: transport)
        let request = LLMRequest(
            task: .coachReview,
            tier: .fast,
            messages: [.user("check me")],
            responseFormat: .jsonSchema(
                name: "review",
                schema: ["type": "object"]
            )
        )
        _ = try await provider.complete(request)
        let completionBody = try #require(await transport.aiBodies.last)
        #expect(completionBody["responseFormat"]?.value as? String == "json_object")
        let messages = try #require(completionBody["messages"]?.value as? [[String: Any]])
        #expect((messages.first?["content"] as? String)?.contains("JSON Schema") == true)

        var events: [LLMStreamEvent] = []
        for try await event in await provider.stream(
            LLMRequest(
                task: .conversation,
                tier: .balanced,
                messages: [.user("hello")]
            )
        ) {
            events.append(event)
        }
        #expect(events == [.textDelta("Hi"), .textDelta("!"), .finished])
    }
}
