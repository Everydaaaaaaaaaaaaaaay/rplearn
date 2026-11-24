import Foundation
import Observation

/// A request owns a source revision and an English draft snapshot. Late responses
/// cannot overwrite a newer source, a manual English edit, or a closed composer.
@MainActor @Observable
final class ComposerTranslationModel {
    enum Mode: String, CaseIterable { case instant = "即时", ai = "AI" }
    var isOpen = false
    var source = ""
    var mode: Mode = .instant
    private(set) var isWorking = false
    private(set) var error: String?
    private var revision = UUID()
    private var task: Task<Void, Never>?

    func cancel() {
        revision = UUID()
        task?.cancel()
        task = nil
        isWorking = false
        error = nil
    }

    func translate(
        automatic: Bool,
        readDraft: @escaping @MainActor () -> String,
        writeDraft: @escaping @MainActor (String) -> Void,
        isComposing: @escaping @MainActor () -> Bool = { false },
        perform: @escaping @MainActor (String) async throws -> String
    ) {
        cancel()
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isOpen, !text.isEmpty else { return }
        guard text.count <= 1500 else { error = "请把这句话缩短一些再翻译"; return }
        let token = revision
        let originalDraft = readDraft()
        // 正在打拼音时不显示“正在翻译”，避免每按一个字母转圈闪一下。
        isWorking = !(automatic && isComposing())
        task = Task { [weak self] in
            do {
                if automatic {
                    try await Task.sleep(for: .milliseconds(650))
                    // 输入法还有未确认的拼音时不翻译：选字确认会改动文本并重新触发；
                    // 原样确认（文本不变）也在这里等到。等待期间不显示“正在翻译”。
                    while isComposing() {
                        if let self, self.revision == token { self.isWorking = false }
                        try await Task.sleep(for: .milliseconds(250))
                    }
                    if let self, self.revision == token { self.isWorking = true }
                }
                try Task.checkCancellation()
                let result = try await perform(text)
                try Task.checkCancellation()
                guard let self, self.revision == token, self.isOpen else { return }
                self.isWorking = false
                guard readDraft() == originalDraft else { return }
                guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.error = "暂未得到译文，请重试"; return
                }
                writeDraft(result)
            } catch {
                guard let self, self.revision == token, !Task.isCancelled else { return }
                self.isWorking = false
                self.error = self.mode == .instant ? "本地翻译暂不可用，点按重试或切换 AI" : "翻译未完成，点按重试"
            }
        }
    }
}
