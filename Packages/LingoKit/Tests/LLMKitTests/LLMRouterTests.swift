import Foundation
import Testing
@testable import LLMKit

@Suite("LLMRouter")
struct LLMRouterTests {
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
