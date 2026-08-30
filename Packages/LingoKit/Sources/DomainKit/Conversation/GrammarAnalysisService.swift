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

/// 仅用于本地规则零命中时的 AI 语法解析；调用方负责优先执行本地匹配。
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
    You are a precise, friendly English grammar tutor for Chinese learners. Analyze one sentence from \
    a role-play chat. Identify 1 to 6 meaningful grammar structures actually used in the sentence, \
    ordered by learning value. Treat the sentence as intentional natural English: explain its grammar, \
    do not rewrite it or invent errors. Keep the Chinese concise and suitable for the learner's level.

    Return JSON only:
    - summary_zh: one short Chinese sentence describing the sentence structure.
    - points: every meaningful grammar structure found, each with:
      - title: a concise Chinese grammar-point title.
      - quote: the exact fragment from the original sentence.
      - pattern: a reusable English pattern, such as "have/has + past participle".
      - explanation_zh: why and how this structure works in this sentence.
      - learner_tip_zh: one brief, practical usage or contrast tip.
    Do not list ordinary vocabulary as grammar. Do not use Markdown.
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
