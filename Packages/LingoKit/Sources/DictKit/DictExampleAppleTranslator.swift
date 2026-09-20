import Observation
import SwiftUI
import Translation

/// One scheduled/running session owns the queue, including the interval before
/// SwiftUI starts translationTask. Existing translations are resolved upstream.
@MainActor
@Observable
final class DictExampleAppleTranslator {
    private(set) var configuration: TranslationSession.Configuration?
    private(set) var sessionID: UUID?
    var pendingCount: Int { pending.count }
    private var generation = UUID()
    private var isActive = true
    private var pending: [UUID: CheckedContinuation<String?, Never>] = [:]
    private var inbox: [(id: UUID, text: String)] = []
    private var timeouts: [UUID: Task<Void, Never>] = [:]
    private let availability: @MainActor () async -> LanguageAvailability.Status

    init(availability: @escaping @MainActor () async -> LanguageAvailability.Status = {
        #if targetEnvironment(simulator)
        return .unsupported
        #else
        return await LanguageAvailability().status(
            from: Locale.Language(identifier: "en"), to: Locale.Language(identifier: "zh-Hans")
        )
        #endif
    }) {
        self.availability = availability
    }

    func translate(_ text: String, allowsDownload: Bool = true) async -> String? {
        guard isActive else { return nil }
        let currentGeneration = generation
        let status = await availability()
        guard currentGeneration == generation, !Task.isCancelled,
              DictSystemTranslationPolicy.canStart(status, allowsDownload: allowsDownload) else { return nil }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                pending[id] = continuation
                inbox.append((id, text))
                triggerSession()
                timeouts[id] = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(120)) }
                    catch { return }
                    complete(id, with: nil)
                }
            }
        } onCancel: {
            Task { @MainActor in self.complete(id, with: nil) }
        }
    }

    func takeBatch() -> (sessionID: UUID, items: [(id: UUID, text: String)])? {
        guard let sessionID else { return nil }
        let batch = inbox
        inbox.removeAll()
        return (sessionID, batch)
    }

    func complete(_ id: UUID, with value: String?) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        timeouts.removeValue(forKey: id)?.cancel()
        inbox.removeAll { $0.id == id }
        continuation.resume(returning: value)
    }

    func finishBatch(_ id: UUID) {
        // A disappearing card's old task must not reset a newly opened session.
        guard sessionID == id else { return }
        sessionID = nil
        if !inbox.isEmpty { triggerSession() }
    }

    func activate() { isActive = true }

    func cancelAll() {
        isActive = false
        generation = UUID()
        let continuations = Array(pending.values)
        pending.removeAll()
        inbox.removeAll()
        for timeout in timeouts.values { timeout.cancel() }
        timeouts.removeAll()
        sessionID = nil
        configuration = nil
        for continuation in continuations { continuation.resume(returning: nil) }
    }

    private func triggerSession() {
        guard sessionID == nil else { return }
        // Reserve synchronously, not in takeBatch: concurrent arrivals must not
        // invalidate the configuration before SwiftUI has even started it.
        sessionID = UUID()
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
