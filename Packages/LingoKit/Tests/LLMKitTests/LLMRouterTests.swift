import Foundation
import Testing
@testable import LLMKit

@Suite("LLMRouter")
struct LLMRouterTests {
    private actor FailingClient: LLMClient {
        var calls = 0
        func complete(_ request: LLMRequest) async throws -> String {
            calls += 1
            throw URLError(.timedOut)
        }
        func stream(_ request: LLMRequest) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }

    @Test("后台失败不放大请求，前台保留重试", arguments: [LLMTask.coachReview, .memorySummary, .quiz, .conversation])
    func boundedRetries(task: LLMTask) async {
        let client = FailingClient()
        let router = LLMRouter(client: client, maxRetries: 1)
        _ = try? await router.complete(LLMRequest(task: task, tier: .fast, messages: [.user("hello")]))
        #expect(await client.calls == (task == .conversation ? 2 : 1))
    }

    @Test("可重试错误判定")
    func retryability() {
        #expect(LLMRouter.isRetryable(LLMError.http(status: 429, message: "")))
        #expect(LLMRouter.isRetryable(LLMError.http(status: 500, message: "")))
        #expect(LLMRouter.isRetryable(LLMError.http(status: 529, message: "")))
        #expect(!LLMRouter.isRetryable(LLMError.http(status: 400, message: "")))
        #expect(!LLMRouter.isRetryable(LLMError.missingAPIKey))
        #expect(LLMRouter.isRetryable(URLError(.timedOut)))
        #expect(!LLMRouter.isRetryable(URLError(.badURL)))
    }

    @Test("配置缺 Key 时 complete 抛 missingAPIKey")
    func missingKeySurfaces() async {
        let router = LLMRouter { throw LLMError.missingAPIKey }
        await #expect(throws: LLMError.missingAPIKey) {
            _ = try await router.complete(
                LLMRequest(task: .conversation, tier: .fast, messages: [.user("hi")])
            )
        }
    }
}
