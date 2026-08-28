import DictKit
import Foundation
import LLMKit

/// 整句翻译（balanced 档、temp 0.3；结果由调用方缓存到 translationZh）。
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

    /// 同时翻译词典例句，并根据该句与精确英文义项给出目标词的简短中文词义。
    public func translateDictionaryExample(
        _ example: DictExampleTranslationRequest
    ) async throws -> DictExampleTranslation {
        async let sentenceZh = translateToChinese(example.sentence)
        async let meaningZh = translateMeaningOrFallback(example)
        return DictExampleTranslation(
            sentenceZh: try await sentenceZh,
            meaningZh: await meaningZh
        )
    }

    private func translateMeaningOrFallback(
        _ example: DictExampleTranslationRequest
    ) async -> String? {
        let request = LLMRequest(
            task: .translation,
            tier: .balanced,
            system: """
            判断目标英文词在给定例句中的确切含义。只输出简短、自然的中文词义，通常 2 到 8 个汉字；\
            不要输出词性、英文、括号、引号或解释。英文义项仅供消歧，最终必须结合例句判断。
            """,
            messages: [
                .user(
                    """
                    目标词：\(example.word)
                    词性：\(example.partOfSpeechAbbreviation)
                    英文义项：\(example.definitionEn ?? "未提供")
                    例句：\(example.sentence)
                    """
                )
            ],
            maxTokens: 80,
            temperature: 0.2
        )
        guard let translated = try? await llm.complete(request) else {
            return example.fallbackMeaningZh
        }
        let meaning = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        return meaning.isEmpty ? example.fallbackMeaningZh : meaning
    }
}
