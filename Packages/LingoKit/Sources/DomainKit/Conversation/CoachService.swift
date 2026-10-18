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

    /// 只保留能在本条学习者消息里定位到的问题。
    /// 审阅请求带着上文语境，模型偶尔会把更早那句的旧错句重复报给当前消息，
    /// 于是同一提示会落到下一句上；这里按原文校对，丢掉对不上号的问题。
    public func grounded(inLearnerMessage message: String) -> CoachReview {
        // 模型判定「没有错误」时保持沉默，即使它顺手列了问题。
        guard hasIssues else { return CoachReview(hasIssues: false, issues: []) }
        let context = Self.matchableText(message)
        let grounded = context.isEmpty ? [] : issues.filter { issue in
            let quote = Self.matchableText(issue.quote)
            return !quote.isEmpty && context.contains(quote)
        }
        return CoachReview(hasIssues: !grounded.isEmpty, issues: grounded)
    }

    /// 比对时忽略大小写、空白和弯引号，忠实引用不会因排版差异被误删。
    static func matchableText(_ text: String) -> String {
        String(
            text.lowercased()
                .replacingOccurrences(of: "\u{2019}", with: "'")
                .replacingOccurrences(of: "\u{201C}", with: "\"")
                .replacingOccurrences(of: "\u{201D}", with: "\"")
                .filter { !$0.isWhitespace }
        )
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
            .grounded(inLearnerMessage: userText)
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
    你是一位英语教练，正在审阅中国学习者写的一条聊天消息。建议会以咕咕的友好提示呈现在应用中；咕咕是一只温暖、善于观察的旅行小鸟伙伴。讲解简短、鼓励，不责备。
    只找真实错误：用词不当、语法错误、拼写错误，或不自然到会让英语母语者困惑的表达。

    不要把正常的聊天风格标为错误：小写开头、省略末尾标点、缩写、俚语、gonna/u/lol 等简写、表情符号，以及聊天中自然的句子片段。

    只返回 JSON：
    - has_issues：是否存在真实错误。
    - issues：每个错误包含 quote（从本条消息逐字复制的错误片段）、type（wrong_word / grammar / spelling / unnatural 之一）、correction（修正后的片段）、explanation_zh（一句简短的中文讲解，说明为什么错、怎么改）。
    最多 3 处，最重要的在前。消息没有问题时返回 has_issues=false、issues=[]。
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
