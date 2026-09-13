import Observation
import SwiftUI
import Translation

/// Reuses existing server translations first; this coordinator translates any
/// uncached sentence on device without requesting cloud generation.
@MainActor
@Observable
final class DictExampleAppleTranslator {
    private(set) var configuration: TranslationSession.Configuration?

    private var pending: [UUID: CheckedContinuation<String?, Never>] = [:]
    private var inbox: [(id: UUID, text: String)] = []
    private var isSessionRunning = false

    func translate(_ text: String, allowsDownload: Bool = false) async -> String? {
        #if targetEnvironment(simulator)
        // Apple's on-device Translation models are not available in Simulator.
        return nil
        #else
        let availability = await LanguageAvailability().status(
            from: Locale.Language(identifier: "en"), to: Locale.Language(identifier: "zh-Hans")
        )
        guard !Task.isCancelled,
              DictSystemTranslationPolicy.canStart(availability, allowsDownload: allowsDownload) else { return nil }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            pending[id] = continuation
            inbox.append((id, text))
            triggerSession()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(allowsDownload ? 120 : 20))
                complete(id, with: nil)
            }
        }
        #endif
    }

    func takeBatch() -> [(id: UUID, text: String)] {
        isSessionRunning = true
        let batch = inbox
        inbox.removeAll()
        return batch
    }

    func complete(_ id: UUID, with value: String?) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        inbox.removeAll { $0.id == id }
        continuation.resume(returning: value)
    }

    func finishBatch() {
        isSessionRunning = false
        if !inbox.isEmpty { triggerSession() }
    }

    func cancelAll() {
        let continuations = pending.values
        pending.removeAll()
        inbox.removeAll()
        isSessionRunning = false
        configuration = nil
        for continuation in continuations { continuation.resume(returning: nil) }
    }

    private func triggerSession() {
        // New examples queue behind an active translation instead of invalidating
        // and cancelling each other's system session.
        guard !isSessionRunning else { return }
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

enum DictSystemTranslationPolicy {
    static func canStart(_ status: LanguageAvailability.Status, allowsDownload: Bool) -> Bool {
        switch status {
        case .installed: true
        case .supported: allowsDownload
        case .unsupported: false
        @unknown default: false
        }
    }
}
