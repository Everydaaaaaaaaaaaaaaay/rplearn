import BackendKit
import DomainKit
import Foundation
import LLMKit
import Testing

/// 显式设置 RUN_LIVE_GRAMMAR_EVAL=1 时才访问生产 AI 网关。
@Suite("真实 AI 语法解析评测")
struct LiveGrammarAnalysisEvaluationTests {
    private final class EmptyCredentials: AuthCredentialStore, @unchecked Sendable {
        func load() throws -> StoredAuthCredential? { nil }
        func remove() throws {}
        func save(_ credential: StoredAuthCredential) throws {}
    }

    @Test("线上失败样句可以返回结构化语法点")
    func analyzesReportedSentence() async throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_GRAMMAR_EVAL"] == "1" else {
            return
        }

        let llm = BackendLLMProvider(
            backend: BackendClient(
                configuration: .live,
                credentialStore: EmptyCredentials()
            ),
            guestID: "codex-live-grammar-eval-v1"
        )
        let result = try await GrammarAnalysisService(llm: llm, timeout: .seconds(30)).analyze(
            sentence: "Hey, random question: what small part of your day do you really enjoy?",
            learnerLevel: "幼儿启蒙"
        )

        #expect(!result.summaryZh.isEmpty)
        #expect(!result.points.isEmpty)
        #expect(result.points.allSatisfy { !$0.quote.isEmpty && !$0.explanationZh.isEmpty })
        print("LIVE_GRAMMAR_EVAL|summary|\(result.summaryZh)")
        for point in result.points {
            print("LIVE_GRAMMAR_EVAL|point|\(point.title)|\(point.quote)|\(point.pattern)")
        }
    }
}
