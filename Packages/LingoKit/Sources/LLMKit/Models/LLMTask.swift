/// 客户端只声明稳定业务任务；供应商、模型和采样参数由服务端路由控制。
public enum LLMTask: String, Sendable, Codable, CaseIterable {
    case characterGeneration = "character_generation"
    case coachReview = "coach_review"
    case conversation
    case dictionaryExplain = "dictionary_explain"
    case memorySummary = "memory_summary"
    case speechFeedback = "speech_feedback"
    case translation
}
