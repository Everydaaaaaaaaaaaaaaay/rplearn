import BackendKit
import CoreKit
import Foundation
import Testing
@testable import LLMKit

@Suite("Backend stream completion boundary")
struct BackendLLMCompletionBoundaryTests {
    private struct Credentials: AuthCredentialStore {
        func load() throws -> StoredAuthCredential? { nil }
        func save(_ value: StoredAuthCredential) throws {}
        func remove() throws {}
    }
    private actor Transport: BackendTransport {
        var pending: AsyncThrowingStream<String, Error>.Continuation?
        func data(for request: URLRequest) async throws -> BackendTransportResponse { throw URLError(.badServerResponse) }
        func lines(for request: URLRequest) async throws -> BackendLineStreamResponse {
            let stream = AsyncThrowingStream<String, Error> { continuation in
                pending = continuation
                for line in ["event: delta", #"data: {"text":"Hello"}"#, "", "event: done", "data: {}", ""] {
                    continuation.yield(line)
                }
                // A proxy keeps the connection open after the terminal protocol event.
            }
            return .init(headers: ["content-type":"text/event-stream"], lines: stream, statusCode: 200)
        }
        func finish() { pending?.finish(); pending = nil }
    }
    @Test("终止事件立即结束回复，不依赖 HTTP EOF")
    func doneEndsWithoutEOF() async throws {
        let transport = Transport()
        let backend = BackendClient(configuration: .init(baseURL: URL(string: "https://api.example.com")!),
            credentialStore: Credentials(), transport: transport)
        let provider = BackendLLMProvider(backend: backend, guestID: "fixture-device-123")
        do {
            let events = try await AsyncDeadline.run(timeout: .milliseconds(500)) {
                var result = [LLMStreamEvent]()
                for try await event in await provider.stream(.init(task: .conversation, tier: .fast, messages: [.user("Hi")])) {
                    result.append(event)
                }
                return result
            }
            #expect(events == [.textDelta("Hello"), .finished])
        } catch { await transport.finish(); throw error }
        await transport.finish()
    }
}
