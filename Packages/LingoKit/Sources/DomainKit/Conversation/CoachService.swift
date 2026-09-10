import Foundation
import LLMKit

/// 教练审核结果（coachReviewJSON 的结构）。
public struct CoachReview: Sendable, Codable, Equatable {
    public struct Issue: Sendable, Codable, Equatable {
        /// 原文中有问题的片段。
        public var quote: String
        /// wrong_word / grammar / spelling / unnatural
        public var type: String
        public var correction: String
        public var explanationZh: String

        public init(quote: String, type: String, correction: String, explanationZh: String) {
            self.quote = quote
            self.type = type
            self.correction = correction
            self.explanationZh = explanationZh
        }
    }

    public var hasIssues: Bool
    public var issues: [Issue]

    public init(hasIssues: Bool, issues: [Issue]) {
        self.hasIssues = hasIssues
        self.issues = issues
    }
}

/// 独立于角色的教练 AI：并行审核用户消息（fast 档、JSON 结构化输出、15s 超时静默放弃）。
public struct CoachService: Sendable {
    public struct TimeoutError: Error {}

    private let llm: any LLMClient
    private let timeout: Duration

    public init(llm: any LLMClient, timeout: Duration = .seconds(15)) {
        self.llm = llm
        self.timeout = timeout
    }

    public func review(userText: String) async throws -> CoachReview {
        let request = LLMRequest(
            task: .coachReview,
            tier: .fast,
            system: Self.systemPrompt,
            messages: [.user(userText)],
            maxTokens: 600,
            temperature: 0.2,
            responseFormat: .jsonSchema(name: "coach_review", schema: Self.schema)
        )
        let llm = self.llm
        let text = try await Self.withTimeout(timeout) {
            try await llm.complete(request)
        }
        return try Self.decodeReview(fromModelOutput: text)
    }

    // MARK: - 解析与序列化

    /// 模型输出 → CoachReview（snake_case JSON）。
    static func decodeReview(fromModelOutput text: String) throws -> CoachReview {
        guard let data = JSONExtractor.extractJSONData(from: text) else {
            throw LLMError.invalidResponse("教练输出无合法 JSON")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CoachReview.self, from: data)
    }

    /// 落库编码（camelCase，与 DTO 直接对应）。
    public static func encode(_ review: CoachReview) -> String? {
        guard let data = try? JSONEncoder().encode(review) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(fromJSON json: String?) -> CoachReview? {
        guard let json else { return nil }
        return try? JSONDecoder().decode(CoachReview.self, from: Data(json.utf8))
    }

    // MARK: - Prompt

    static let systemPrompt = """
    You are an English coach reviewing one chat message written by a Chinese learner. \
    Your suggestions appear in the app as friendly notes from Gugu, a warm, observant travel-bird \
    companion. Keep explanations concise, encouraging, and never scolding. \
    Find real mistakes only: wrong word choice, broken grammar, spelling errors, or phrasing \
    so unnatural it would confuse a native speaker.

    Do NOT flag casual texting style: lowercase starts, missing end punctuation, contractions, \
    slang, abbreviations (gonna, u, lol), emoji, or sentence fragments that are normal in chat.

    Respond with JSON only:
    - has_issues: whether any real mistake exists
    - issues: for each mistake -> quote (the exact wrong fragment from the message), \
    type (one of wrong_word / grammar / spelling / unnatural), correction (the fixed fragment), \
    explanation_zh (一句简短的中文讲解，为什么错、怎么改).
    At most 3 issues, the most important first. If the message is fine, return has_issues=false with empty issues.
    """

    static let schema: JSONValue = [
        "type": "object",
        "properties": [
            "has_issues": ["type": "boolean"],
            "issues": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "quote": ["type": "string"],
                        "type": ["type": "string", "enum": ["wrong_word", "grammar", "spelling", "unnatural"]],
                        "correction": ["type": "string"],
                        "explanation_zh": ["type": "string"],
                    ],
                    "required": ["quote", "type", "correction", "explanation_zh"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["has_issues", "issues"],
        "additionalProperties": false,
    ]

    // MARK: - 超时

    static func withTimeout<T: Sendable>(
        _ timeout: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw TimeoutError()
            }
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            group.cancelAll()
            return result
        }
    }
}
