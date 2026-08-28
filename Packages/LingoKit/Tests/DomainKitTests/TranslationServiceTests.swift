import DictKit
import LLMKit
import Testing
@testable import DomainKit

@Suite("TranslationService")
struct TranslationServiceTests {
    @Test("翻译走 balanced 档、低温采样，输出去除首尾空白")
    func requestShape() async throws {
        let mock = MockLLMProvider(completeHandler: { request in
            #expect(request.tier == .balanced)
            #expect(request.temperature == 0.3)
            #expect(request.system?.contains("翻译") == true)
            #expect(request.messages == [.user("Fancy a pint later?")])
            return "\n待会儿去喝一杯？  "
        })
        let service = TranslationService(llm: mock)
        let result = try await service.translateToChinese("Fancy a pint later?")
        #expect(result == "待会儿去喝一杯？")
    }

    @Test("词典例句复用稳定翻译路径，句中词义使用独立纯文本增强")
    func dictionaryExampleReusesSentenceTranslation() async throws {
        let mock = MockLLMProvider(completeHandler: { request in
            #expect(request.tier == .balanced)
            #expect(request.responseFormat == .text)
            switch request.messages {
            case [.user("Fancy a proper pint sometime this week?")]:
                #expect(request.temperature == 0.3)
                return "这周找个时间喝一杯正经的啤酒怎么样？"
            case let messages where messages.first?.content.contains("目标词：proper") == true:
                #expect(request.temperature == 0.2)
                #expect(messages.first?.content.contains("marked by suitability") == true)
                return "正经的"
            default:
                Issue.record("出现了未预期的翻译请求：\(request.messages)")
                return ""
            }
        })
        let service = TranslationService(llm: mock)

        let result = try await service.translateDictionaryExample(
            DictExampleTranslationRequest(
                sentence: "Fancy a proper pint sometime this week?",
                word: "proper",
                partOfSpeechAbbreviation: "adj.",
                definitionEn: "marked by suitability",
                fallbackMeaningZh: "适当的"
            )
        )

        #expect(result.sentenceZh == "这周找个时间喝一杯正经的啤酒怎么样？")
        #expect(result.meaningZh == "正经的")
    }

    @Test("英文义项翻译失败时仍保留整句译文与本地中文词义")
    func dictionaryMeaningFailureDoesNotDiscardSentence() async throws {
        let mock = MockLLMProvider(completeHandler: { request in
            if request.messages == [.user("The tube alone is enough.")] {
                return "光是伦敦地铁就够让人头疼了。"
            }
            throw LLMError.invalidResponse("义项翻译暂不可用")
        })
        let service = TranslationService(llm: mock)

        let result = try await service.translateDictionaryExample(
            DictExampleTranslationRequest(
                sentence: "The tube alone is enough.",
                word: "tube",
                partOfSpeechAbbreviation: "n.",
                definitionEn: "an underground railway system",
                fallbackMeaningZh: "地铁"
            )
        )

        #expect(result.sentenceZh == "光是伦敦地铁就够让人头疼了。")
        #expect(result.meaningZh == "地铁")
    }
}
