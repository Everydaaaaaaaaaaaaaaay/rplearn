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

    @Test("专用任务未部署时降级到支持结构化输出的既有任务")
    func fallsBackWhenGrammarTaskIsUnavailable() async throws {
        let recorder = GrammarRequestRecorder()
        let mock = MockLLMProvider(completeHandler: { request in
            try await recorder.complete(request)
        })

        let result = try await GrammarAnalysisService(llm: mock).analyze(
            sentence: "Hey, random question: what small part of your day do you really enjoy?",
            learnerLevel: "幼儿启蒙"
        )

        #expect(result.points.first?.quote == "what small part of your day do you really enjoy")
        #expect(await recorder.tasks == [.grammarExplain, .coachReview])
    }

    @Test("非路由缺失错误不会被兼容降级掩盖")
    func doesNotFallbackForTransientFailures() async {
        let recorder = GrammarRequestRecorder(primaryError: .http(status: 503, message: "busy"))
        let mock = MockLLMProvider(completeHandler: { request in
            try await recorder.complete(request)
        })

        await #expect(throws: LLMError.http(status: 503, message: "busy")) {
            _ = try await GrammarAnalysisService(llm: mock).analyze(
                sentence: "How does this work?",
                learnerLevel: "B1"
            )
        }
        #expect(await recorder.tasks == [.grammarExplain])
    }
}

private actor GrammarRequestRecorder {
    private(set) var tasks: [LLMTask] = []
    private let primaryError: LLMError

    init(primaryError: LLMError = .http(status: 404, message: "task unavailable")) {
        self.primaryError = primaryError
    }

    func complete(_ request: LLMRequest) throws -> String {
        tasks.append(request.task)
        if request.task == .grammarExplain {
            throw primaryError
        }
        return #"{"summary_zh":"句子先引出话题，再使用特殊疑问句。","points":[{"title":"特殊疑问句","quote":"what small part of your day do you really enjoy","pattern":"what + noun phrase + do/does + subject + verb","explanation_zh":"what 修饰名词短语并引导疑问句。","learner_tip_zh":"助动词后使用动词原形。"}]}"#
    }
}
