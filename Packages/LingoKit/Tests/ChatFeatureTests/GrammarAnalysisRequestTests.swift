import DictKit
import Foundation
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
}
