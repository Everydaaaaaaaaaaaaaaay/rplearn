import Foundation
import LLMKit

/// 整句翻译（balanced 档、temp 0.3；结果由调用方缓存到 translationZh）。
/// 最多尝试三次（包括空响应）；耗尽后由调用方回退 Apple 本地翻译。
public struct TranslationService: Sendable {
    private let llm: any LLMClient
    private let retryDelay: Duration

    public init(llm: any LLMClient) {
        self.init(llm: llm, retryDelay: .milliseconds(500))
    }

    init(llm: any LLMClient, retryDelay: Duration) {
        self.llm = llm
        self.retryDelay = retryDelay
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
        for attempt in 0..<3 {
            try Task.checkCancellation()
            if attempt > 0 { try await Task.sleep(for: retryDelay) }
            do {
                let result = try await llm.complete(request)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !result.isEmpty else { throw TranslationFailure.emptyResponse }
                return result
            } catch {
                try Task.checkCancellation()
                if attempt == 2 { throw error }
            }
        }
        throw TranslationFailure.emptyResponse
    }
}

private enum TranslationFailure: Error { case emptyResponse }
