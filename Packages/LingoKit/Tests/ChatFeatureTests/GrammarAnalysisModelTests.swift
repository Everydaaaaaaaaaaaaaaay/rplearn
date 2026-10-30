import DomainKit
import Foundation
import Testing
@testable import ChatFeature

@Suite("Grammar analysis loading") @MainActor
struct GrammarAnalysisModelTests {
    private var result: AIGrammarAnalysis {
        .init(summaryZh: "完成时", points: [.init(title: "现在完成时", quote: "have finished", pattern: "have + participle",
            explanationZh: "动作已经完成", learnerTipZh: "使用过去分词", canonicalPointID: "present-perfect")])
    }
    @Test("直接选AI标签与按钮选择使用相同加载状态，并复用成功结果")
    func directSelectionAndCache() async {
        let model = GrammarAnalysisModel()
        let expected = result
        model.source = .ai
        #expect(await model.load(using: { expected }) == expected)
        #expect(model.error == nil && !model.isLoading)
        model.source = .local; model.source = .ai
        #expect(await model.load(using: { Issue.record("不能重复请求已成功的解析"); return expected }) == nil)
    }
    @Test("失败后可以重试；错误状态不会锁住后续解析")
    func retry() async {
        let model = GrammarAnalysisModel(); model.source = .ai
        _ = await model.load(using: { throw URLError(.cannotConnectToHost) })
        #expect(model.error != nil && !model.isLoading)
        let expected = result
        #expect(await model.load(using: { expected }) == expected)
        #expect(model.error == nil && model.analysis == expected)
    }
    @Test("切换来源取消请求，不将取消误报为解析失败")
    func cancellation() async {
        let model = GrammarAnalysisModel(); model.source = .ai
        let expected = result
        let task = Task { await model.load(using: { try await Task.sleep(for: .seconds(30)); return expected }) }
        await Task.yield()
        model.source = .local; task.cancel()
        _ = await task.value
        #expect(model.error == nil && model.analysis == nil && !model.isLoading)
        model.source = .ai
        #expect(await model.load(using: { expected }) == expected)
    }
}
