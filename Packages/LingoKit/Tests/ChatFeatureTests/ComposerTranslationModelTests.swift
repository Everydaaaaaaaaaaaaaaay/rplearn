import Foundation
import Testing
@testable import ChatFeature

@Suite("输入翻译器草稿隔离") @MainActor
struct ComposerTranslationModelTests {
    private func settle(_ model: ComposerTranslationModel) async throws {
        for _ in 0..<100 where model.isWorking { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!model.isWorking)
    }

    @Test("翻译结果只进入可编辑草稿")
    func resultUpdatesDraft() async throws {
        let model = ComposerTranslationModel()
        model.isOpen = true; model.source = "你好"
        var draft = ""
        model.translate(automatic: false, readDraft: { draft }, writeDraft: { draft = $0 },
                        perform: { source in #expect(source == "你好"); return "Hello." })
        try await settle(model)
        #expect(draft == "Hello.")
        #expect(model.source == "你好")
    }

    @Test("手动编辑英文后晚到的翻译不得覆盖")
    func preservesManualEdit() async throws {
        let model = ComposerTranslationModel()
        model.isOpen = true; model.source = "你好"
        var draft = ""
        model.translate(automatic: false, readDraft: { draft }, writeDraft: { draft = $0 },
                        perform: { _ in try await Task.sleep(for: .milliseconds(30)); return "Hello." })
        draft = "My own words."
        try await settle(model)
        #expect(draft == "My own words.")
    }

    @Test("关闭或切换取消后旧结果不能写回")
    func cancellationInvalidatesResponse() async throws {
        let model = ComposerTranslationModel()
        model.isOpen = true; model.source = "你好"
        var draft = ""
        model.translate(automatic: false, readDraft: { draft }, writeDraft: { draft = $0 },
                        perform: { _ in try? await Task.sleep(for: .milliseconds(30)); return "Stale" })
        model.cancel(); model.isOpen = false
        try await Task.sleep(for: .milliseconds(60))
        #expect(draft.isEmpty)
        #expect(!model.isWorking)
    }

    @Test("空输入不请求，失败保留中英文并可重试")
    func errorKeepsDrafts() async throws {
        let model = ComposerTranslationModel()
        model.isOpen = true
        var draft = "Existing"
        model.translate(automatic: false, readDraft: { draft }, writeDraft: { draft = $0 },
                        perform: { _ in Issue.record("Empty input must not request"); return "" })
        #expect(!model.isWorking)
        model.source = "你好"
        model.translate(automatic: false, readDraft: { draft }, writeDraft: { draft = $0 },
                        perform: { _ in throw URLError(.notConnectedToInternet) })
        try await settle(model)
        #expect(model.error != nil)
        #expect(draft == "Existing")
        #expect(model.source == "你好")
    }
}
