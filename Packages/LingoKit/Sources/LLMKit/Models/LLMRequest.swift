/// 一次 LLM 调用的全部参数，与具体供应商无关。
public struct LLMRequest: Sendable {
    public enum ResponseFormat: Sendable, Equatable {
        case text
        /// 结构化 JSON 输出。Anthropic 走 output_config.format.json_schema，
        /// OpenAI 走 response_format.json_schema；兼容端点不支持时降级为 prompt 内嵌 schema。
        case jsonSchema(name: String, schema: JSONValue)
    }

    public var tier: LLMTier
    public var system: String?
    public var messages: [LLMMessage]
    public var maxTokens: Int
    /// 采样温度。目标模型不支持采样参数时（如 claude-sonnet-5 / claude-opus-4-8）由 Provider 自动丢弃。
    public var temperature: Double?
    public var responseFormat: ResponseFormat

    public init(
        tier: LLMTier,
        system: String? = nil,
        messages: [LLMMessage],
        maxTokens: Int = 512,
        temperature: Double? = nil,
        responseFormat: ResponseFormat = .text
    ) {
        self.tier = tier
        self.system = system
        self.messages = messages
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.responseFormat = responseFormat
    }
}
