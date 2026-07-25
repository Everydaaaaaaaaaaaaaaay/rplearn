import Foundation

/// 供应商种类。custom = OpenAI 兼容端点（可配 baseURL）。
public enum LLMProviderKind: String, Sendable, CaseIterable, Codable {
    case anthropic
    case openai
    case custom

    public var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openai: "OpenAI"
        case .custom: "自定义（OpenAI 兼容）"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .anthropic: "https://api.anthropic.com"
        case .openai: "https://api.openai.com"
        case .custom: ""
        }
    }

    public func defaultModelID(for tier: LLMTier) -> String {
        switch self {
        case .anthropic:
            switch tier {
            case .fast: "claude-haiku-4-5"
            case .balanced: "claude-sonnet-5"
            case .deep: "claude-opus-4-8"
            }
        case .openai, .custom:
            switch tier {
            case .fast: "gpt-4o-mini"
            case .balanced: "gpt-4o"
            case .deep: "gpt-4o"
            }
        }
    }
}

/// 构建 Provider 所需的完整配置快照（Sendable，可跨 actor 传递）。
public struct LLMProviderConfig: Sendable, Equatable {
    public var kind: LLMProviderKind
    public var apiKey: String
    public var baseURL: URL
    public var models: [LLMTier: String]

    public init(kind: LLMProviderKind, apiKey: String, baseURL: URL, models: [LLMTier: String]) {
        self.kind = kind
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.models = models
    }

    public func modelID(for tier: LLMTier) -> String {
        models[tier] ?? kind.defaultModelID(for: tier)
    }

    public func makeProvider() -> any LLMProvider {
        switch kind {
        case .anthropic:
            AnthropicProvider(config: self)
        case .openai, .custom:
            OpenAIProvider(config: self)
        }
    }
}
