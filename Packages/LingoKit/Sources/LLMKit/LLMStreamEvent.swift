/// 流式回复事件。
public enum LLMStreamEvent: Sendable, Equatable {
    case textDelta(String)
    case finished
}
