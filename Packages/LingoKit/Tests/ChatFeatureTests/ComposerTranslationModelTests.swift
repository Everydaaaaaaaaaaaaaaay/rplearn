import Foundation
import Testing
import UIKit
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

    @Test("输入法还有未确认的拼音时不实时翻译，选字确认后只翻一次")
    func waitsForInputMethodComposition() async throws {
        let model = ComposerTranslationModel()
        model.isOpen = true; model.source = "你好"
        var draft = ""
        var composing = true
        var requests = 0
        model.translate(automatic: true, readDraft: { draft }, writeDraft: { draft = $0 },
                        isComposing: { composing },
                        perform: { source in requests += 1; #expect(source == "你好"); return "Hello." })
        #expect(!model.isWorking, "打拼音时不显示正在翻译")
        // 防抖结束、进入组字等待后仍不显示“正在翻译”；再多等几轮也不发起翻译。
        for _ in 0..<300 where model.isWorking { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!model.isWorking)
        try await Task.sleep(for: .milliseconds(600))
        #expect(requests == 0)
        #expect(draft.isEmpty)
        composing = false
        for _ in 0..<300 where requests == 0 { try await Task.sleep(for: .milliseconds(10)) }
        try await settle(model)
        #expect(requests == 1)
        #expect(draft == "Hello.")
    }

    @Test("能从第一响应者识别输入法未确认的标记文本")
    func detectsMarkedTextInFirstResponder() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let field = UITextView(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        window.addSubview(field)
        window.makeKeyAndVisible()
        defer {
            field.resignFirstResponder()
            window.isHidden = true
        }
        #expect(field.becomeFirstResponder())
        field.insertText("你")
        #expect(!InputMethodComposition.isComposing)
        field.setMarkedText("hao", selectedRange: NSRange(location: 3, length: 0))
        #expect(InputMethodComposition.isComposing)
        field.unmarkText()
        #expect(!InputMethodComposition.isComposing)
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
