import Foundation
import LLMKit

/// 本地语法库未命中时，由 AI 返回的结构化整句解析。
public struct AIGrammarAnalysis: Sendable, Codable, Equatable {
    public struct Point: Sendable, Codable, Equatable {
        public var title: String
        public var quote: String
        public var pattern: String
        public var explanationZh: String
        public var learnerTipZh: String

        public init(
            title: String,
            quote: String,
            pattern: String,
            explanationZh: String,
            learnerTipZh: String
        ) {
            self.title = title
            self.quote = quote
            self.pattern = pattern
            self.explanationZh = explanationZh
            self.learnerTipZh = learnerTipZh
        }
    }

    public var summaryZh: String
    public var points: [Point]

    public init(summaryZh: String, points: [Point]) {
        self.summaryZh = summaryZh
        self.points = points
    }
}

/// 独立的 AI 语法解析。调用方决定展示本地结果还是由用户直接请求 AI。
public struct GrammarAnalysisService: Sendable {
    private let llm: any LLMClient
    private let timeout: Duration

    public init(llm: any LLMClient, timeout: Duration = .seconds(20)) {
        self.llm = llm
        self.timeout = timeout
    }

    public func analyze(sentence: String, learnerLevel: String) async throws -> AIGrammarAnalysis {
        let primaryRequest = Self.makeRequest(
            task: .grammarExplain,
            sentence: sentence,
            learnerLevel: learnerLevel
        )
        let llm = self.llm
        let output = try await CoachService.withTimeout(timeout) {
            do {
                return try await llm.complete(primaryRequest)
            } catch {
                // 老版本生产环境可能尚未部署 grammar_explain 路由。只在路由明确不存在时
                // 借用同样支持 JSON 的 coach_review 路由；网络、鉴权与限流错误仍原样抛出。
                guard Self.isUnavailableTask(error) else { throw error }
                return try await llm.complete(
                    Self.makeRequest(
                        task: .coachReview,
                        sentence: sentence,
                        learnerLevel: learnerLevel
                    )
                )
            }
        }
        return try Self.decode(fromModelOutput: output)
    }

    private static func makeRequest(
        task: LLMTask,
        sentence: String,
        learnerLevel: String
    ) -> LLMRequest {
        LLMRequest(
            task: task,
            tier: .fast,
            system: systemPrompt,
            messages: [
                .user("学习者水平：\(learnerLevel)\n待解析句子：\(sentence)")
            ],
            maxTokens: 1_200,
            temperature: 0.2,
            responseFormat: .jsonSchema(name: "grammar_analysis", schema: schema)
        )
    }

    private static func isUnavailableTask(_ error: Error) -> Bool {
        guard let llmError = error as? LLMError,
              case .http(let status, _) = llmError else {
            return false
        }
        return status == 404
    }

    static func decode(fromModelOutput output: String) throws -> AIGrammarAnalysis {
        guard let data = JSONExtractor.extractJSONData(from: output) else {
            throw LLMError.invalidResponse("语法解析输出无合法 JSON")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(AIGrammarAnalysis.self, from: data)
        guard !result.points.isEmpty else {
            throw LLMError.invalidResponse("语法解析没有返回有效语法点")
        }
        return result
    }

    static let systemPrompt = """
    你是一位准确、友好的英语语法导师，面向中国学习者。分析角色聊天中的一个句子，找出句中实际使用、具有学习价值的 1—6 个语法结构，按学习价值排序。
    把原句视为有意使用的自然英语：解释其语法，不改写，也不凭空找错。中文讲解简洁，适合学习者水平。

    只返回 JSON：
    - summary_zh：用一句简短中文说明句子结构。
    - points：找到的有意义的语法结构，每项包含：
      - title：简洁的中文语法点名称。
      - quote：从原句逐字复制的片段。
      - pattern：可复用的英语结构，如“have/has + past participle”。
      - explanation_zh：这个结构在本句中如何使用、为什么成立。
      - learner_tip_zh：一句简短、实用的用法或对比提示。
    不要把普通词汇列为语法。不要使用 Markdown。
    """

    static let schema: JSONValue = [
        "type": "object",
        "properties": [
            "summary_zh": ["type": "string"],
            "points": [
                "type": "array",
                "minItems": 1,
                "maxItems": 6,
                "items": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "quote": ["type": "string"],
                        "pattern": ["type": "string"],
                        "explanation_zh": ["type": "string"],
                        "learner_tip_zh": ["type": "string"],
                    ],
                    "required": ["title", "quote", "pattern", "explanation_zh", "learner_tip_zh"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["summary_zh", "points"],
        "additionalProperties": false,
    ]
}
