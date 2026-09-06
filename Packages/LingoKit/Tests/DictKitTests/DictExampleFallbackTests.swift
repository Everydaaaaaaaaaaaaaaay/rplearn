import Foundation
import Testing
import Translation
@testable import DictKit

@Suite("例句系统翻译兜底")
struct DictExampleFallbackTests {
    @Test("自动仅使用已装语言包；显式重试可准备语言包，不支持时不弹系统界面")
    func languagePreparationPolicy() {
        #expect(DictSystemTranslationPolicy.canStart(.installed, allowsDownload: false))
        #expect(!DictSystemTranslationPolicy.canStart(.supported, allowsDownload: false))
        #expect(DictSystemTranslationPolicy.canStart(.supported, allowsDownload: true))
        #expect(!DictSystemTranslationPolicy.canStart(.unsupported, allowsDownload: true))
    }

    @Test("服务端失败后调用句子兜底，保留失败后的重试能力")
    func fallbackAfterFailure() async {
        let calls = FallbackCalls()
        let actions = DictExampleTranslationActions { _ in nil }
            .fallingBackToSentenceTranslation { sentence in
                await calls.record(sentence)
                return "她翻开了书。"
            }
        let request = DictExampleTranslationRequest(sentence: "She opened the book.", lemma: "book")
        let result = await actions.translate(request)
        #expect(result?.sentenceZhHans == "她翻开了书。")
        #expect(await calls.sentences == ["She opened the book."])
    }

    @Test("服务端成功时不触发系统翻译")
    func successfulPrimaryDoesNotLaunchSystem() async {
        let calls = FallbackCalls()
        let actions = DictExampleTranslationActions { _ in
            DictExampleTranslation(sentenceZhHans: "她翻开了书。")
        }.fallingBackToSentenceTranslation { sentence in
            await calls.record(sentence)
            return nil
        }
        let request = DictExampleTranslationRequest(sentence: "She opened the book.", lemma: "book")
        #expect(await actions.translate(request)?.sentenceZhHans == "她翻开了书。")
        #expect(await calls.sentences.isEmpty)
    }
}

private actor FallbackCalls {
    private(set) var sentences: [String] = []
    func record(_ sentence: String) { sentences.append(sentence) }
}
