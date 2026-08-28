import Observation
import SwiftUI
import Translation

/// 词典例句云端翻译失败时的 Apple 端上翻译兜底。
/// `TranslationSession` 只能由 SwiftUI 的 `.translationTask` 提供，
/// 因此用请求队列把它桥接为按句调用的 async 接口。
@MainActor
@Observable
final class DictExampleAppleTranslator {
    private(set) var configuration: TranslationSession.Configuration?

    private var pending: [UUID: CheckedContinuation<String?, Never>] = [:]
    private var inbox: [(id: UUID, text: String)] = []

    func translate(_ text: String) async -> String? {
        let id = UUID()
        return await withCheckedContinuation { continuation in
            pending[id] = continuation
            inbox.append((id, text))
            triggerSession()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(20))
                complete(id, with: nil)
            }
        }
    }

    func takeBatch() -> [(id: UUID, text: String)] {
        let batch = inbox
        inbox.removeAll()
        return batch
    }

    func complete(_ id: UUID, with value: String?) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(returning: value)
    }

    private func triggerSession() {
        if configuration == nil {
            configuration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: "zh-Hans")
            )
        } else {
            configuration?.invalidate()
        }
    }
}
