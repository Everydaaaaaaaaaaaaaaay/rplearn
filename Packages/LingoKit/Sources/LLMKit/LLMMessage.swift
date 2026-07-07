/// 对话消息。system 提示不在此列，由 LLMRequest.system 单独承载（Anthropic 顶层 system 语义）。
public struct LLMMessage: Sendable, Equatable, Codable {
    public enum Role: String, Sendable, Codable {
        case user
        case assistant
    }

    public var role: Role
    public var content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }

    public static func user(_ content: String) -> LLMMessage {
        LLMMessage(role: .user, content: content)
    }

    public static func assistant(_ content: String) -> LLMMessage {
        LLMMessage(role: .assistant, content: content)
    }
}
