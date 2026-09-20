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

    @Test("首次并发例句只调度一次，运行中到达的例句随后执行")
    @MainActor
    func queuedExamplesShareScheduledSession() async throws {
        let translator = DictExampleAppleTranslator(availability: { .supported })
        let first = Task { await translator.translate("First.") }
        while translator.pendingCount < 1 { await Task.yield() }
        let scheduled = translator.sessionID
        let second = Task { await translator.translate("Second.") }
        while translator.pendingCount < 2 { await Task.yield() }
        #expect(translator.sessionID == scheduled)
        let batch = try #require(translator.takeBatch())
        #expect(batch.items.count == 2)
        let third = Task { await translator.translate("Third.") }
        while translator.pendingCount < 3 { await Task.yield() }
        #expect(translator.sessionID == scheduled)
        for item in batch.items { translator.complete(item.id, with: "译文") }
        translator.finishBatch(batch.sessionID)
        #expect(translator.sessionID != scheduled)
        let next = try #require(translator.takeBatch())
        #expect(next.items.map(\.text) == ["Third."])
        for item in next.items { translator.complete(item.id, with: "后续译文") }
        translator.finishBatch(next.sessionID)
        #expect(await first.value == "译文")
        #expect(await second.value == "译文")
        #expect(await third.value == "后续译文")
        #expect(translator.pendingCount == 0)
    }

    @Test("关闭后旧会话不能干扰重新打开，取消请求释放等待")
    @MainActor
    func cancellationAndReopening() async throws {
        let translator = DictExampleAppleTranslator(availability: { .installed })
        let old = Task { await translator.translate("Old.") }
        while translator.pendingCount < 1 { await Task.yield() }
        let batch = try #require(translator.takeBatch())
        translator.cancelAll()
        #expect(await old.value == nil)
        #expect(await translator.translate("Late server miss.") == nil)
        translator.activate()
        let reopened = Task { await translator.translate("New.") }
        while translator.pendingCount < 1 { await Task.yield() }
        let newID = translator.sessionID
        translator.finishBatch(batch.sessionID)
        #expect(translator.sessionID == newID)
        reopened.cancel()
        #expect(await reopened.value == nil)
        #expect(translator.pendingCount == 0)
        translator.cancelAll()
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

    @Test("Apple 临时兜底不冒充 LLM 缓存，下次打开重新查询云端")
    func localFallbackDoesNotPoisonCloudCache() async {
        let cache = DictExampleTranslationCache()
        let calls = FallbackCalls()
        let request = DictExampleTranslationRequest(sentence: "She opened the book.", lemma: "book")
        let offline = DictExampleTranslationActions { _ in nil }
            .fallingBackToSentenceTranslation { _ in "本地译文" }
        let first = await cache.translation(for: request, using: offline)
        #expect(first?.isSystemFallback == true)
        let recovered = DictExampleTranslationActions { request in
            await calls.record(request.sentence)
            return DictExampleTranslation(sentenceZhHans: "LLM 译文")
        }
        let second = await cache.translation(for: request, using: recovered)
        let third = await cache.translation(for: request, using: recovered)
        #expect(second?.sentenceZhHans == "LLM 译文")
        #expect(second?.isSystemFallback == false)
        #expect(third == second)
        #expect(await calls.sentences.count == 1)
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
