import Observation
import SwiftUI
import Translation

/// Server translation remains authoritative. This coordinator only supplies a
/// sentence-level, on-device fallback when the server cannot return a result.
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
