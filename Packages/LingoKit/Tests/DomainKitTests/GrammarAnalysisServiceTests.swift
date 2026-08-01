import LLMKit
import Testing
@testable import DomainKit

@Suite("GrammarAnalysisService")
struct GrammarAnalysisServiceTests {
    @Test("使用独立 fast 任务并解析多个结构化语法点")
    func requestAndDecode() async throws {
        let mock = MockLLMProvider(completeHandler: { request in
            #expect(request.task == .grammarExplain)
            #expect(request.tier == .fast)
            #expect(request.temperature == 0.2)
            #expect(request.messages.first?.content.contains("B1") == true)
            if case .jsonSchema(let name, _) = request.responseFormat {
                #expect(name == "grammar_analysis")
            } else {
                Issue.record("应使用结构化 JSON 输出")
            }
            return #"{"summary_zh":"句子包含完成时和目的结构。","points":[{"title":"现在完成时","quote":"have finished","pattern":"have/has + past participle","explanation_zh":"表示已经完成。","learner_tip_zh":"注意过去分词。"},{"title":"目的不定式","quote":"to catch the bus","pattern":"to + verb","explanation_zh":"表示动作目的。","learner_tip_zh":"可回答 why。"}]}"#
        })
        let result = try await GrammarAnalysisService(llm: mock).analyze(
            sentence: "I have finished early to catch the bus.",
            learnerLevel: "B1"
        )
        #expect(result.points.count == 2)
        #expect(result.points[0].title == "现在完成时")
        #expect(result.points[1].quote == "to catch the bus")
    }

    @Test("拒绝没有语法点的模型结果")
    func rejectsEmptyPoints() async {
        let mock = MockLLMProvider(completeHandler: { _ in
            #"{"summary_zh":"没有结构。","points":[]}"#
        })
        await #expect(throws: Error.self) {
            _ = try await GrammarAnalysisService(llm: mock).analyze(
                sentence: "Hello.",
                learnerLevel: "A1"
            )
        }
    }
}
