import DictKit
import Foundation
import LLMKit
import Testing
@testable import ChatFeature

@Suite("GrammarAnalysisRequest")
struct GrammarAnalysisRequestTests {
    @Test("只有本地零命中才需要 AI 兜底")
    func fallbackPolicy() throws {
        let resourceURL = try #require(Bundle.main.url(forResource: "grammar_points", withExtension: "json"))
        let store = try GrammarPointStore(url: resourceURL)
        let point = try #require(store.point(id: "modal-verb"))
        let localItem = LocalGrammarAnalysisItem(
            id: "modal-verb-1",
            point: point,
            matchedText: "could use"
        )

        let localRequest = GrammarAnalysisRequest(
            id: UUID(),
            sentence: "I could use a break.",
            learnerLevel: "B1",
            localItems: [localItem]
        )
        let fallbackRequest = GrammarAnalysisRequest(
            id: UUID(),
            sentence: "What a lovely view.",
            learnerLevel: "B1",
            localItems: []
        )

        #expect(!localRequest.requiresAIFallback)
        #expect(fallbackRequest.requiresAIFallback)
    }

    @Test("语法解析错误提示区分网络、服务与返回格式")
    func errorPresentation() {
        #expect(
            GrammarAnalysisErrorPresentation.message(for: URLError(.notConnectedToInternet))
                == "网络连接异常，请检查网络后重试"
        )
        #expect(
            GrammarAnalysisErrorPresentation.message(for: LLMError.invalidResponse("bad json"))
                == "AI 返回的解析内容不完整，请重新解析"
        )
        #expect(
            GrammarAnalysisErrorPresentation.message(
                for: LLMError.http(status: 503, message: "busy")
            ) == "AI 解析服务暂时不可用，请稍后重试"
        )
    }
}
