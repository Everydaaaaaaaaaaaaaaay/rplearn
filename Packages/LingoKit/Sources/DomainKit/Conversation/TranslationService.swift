import Foundation
import LLMKit

/// 整句翻译（balanced 档、temp 0.3；结果由调用方缓存到 translationZh）。
/// 云端结果比端上机器翻译明显更自然，因此是首选；失败时才由调用方回退本地翻译。
public struct TranslationService: Sendable {
    private let llm: any LLMClient

    public init(llm: any LLMClient) {
        self.llm = llm
    }

    public func translateToChinese(_ sentence: String) async throws -> String {
        let request = LLMRequest(
            task: .translation,
            tier: .balanced,
            system: """
            你是资深中英翻译。把用户给出的英文句子翻译成自然、地道的中文口语，符合原文的语气与随意程度。\
            俚语和口头语要译出对应的中文表达而不是直译。只输出译文本身，不要任何解释或引号。
            """,
            messages: [.user(sentence)],
            maxTokens: 400,
            temperature: 0.3
        )
        return try await llm.complete(request)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
