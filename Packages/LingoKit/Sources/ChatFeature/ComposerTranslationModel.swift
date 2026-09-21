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
        perform: @escaping @MainActor (String) async throws -> String
    ) {
        cancel()
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isOpen, !text.isEmpty else { return }
        guard text.count <= 1500 else { error = "请把这句话缩短一些再翻译"; return }
        let token = revision
        let originalDraft = readDraft()
        isWorking = true
        task = Task { [weak self] in
            do {
                if automatic { try await Task.sleep(for: .milliseconds(650)) }
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
