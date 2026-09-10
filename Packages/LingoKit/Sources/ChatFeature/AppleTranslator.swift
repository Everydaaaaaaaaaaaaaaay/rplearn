import Observation
import SwiftUI
import Translation

/// Bridges SwiftUI's system-owned translation session into an on-demand local API.
/// Language resources are downloaded by Apple with system consent, never bundled.
@MainActor
@Observable
public final class AppleTranslator {
    public private(set) var configuration: TranslationSession.Configuration?
    private(set) var sessionID = UUID()
    private var isSessionRunning = false
    private var pending: [UUID: CheckedContinuation<String?, Never>] = [:]
    private var inbox: [(id: UUID, text: String)] = []
    private var deadlines: [UUID: Task<Void, Never>] = [:]

    public init() {}

    public func translate(_ text: String) async -> String? {
        #if targetEnvironment(simulator)
        // Apple's translation models are unavailable in Simulator.
        return nil
        #else
        return await enqueue(text)
        #endif
    }

    func enqueue(_ text: String) async -> String? {
        guard !Task.isCancelled, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pending[id] = continuation
                inbox.append((id, text))
                triggerSession()
                // Allow time for first-use language download and system consent.
                deadlines[id] = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(120)) }
                    catch { return }
                    cancelRequest(id)
                }
            }
        } onCancel: {
            Task { @MainActor in self.cancelRequest(id) }
        }
    }

    func takeBatch(sessionID: UUID) -> [(id: UUID, text: String)] {
        guard self.sessionID == sessionID else { return [] }
        let batch = inbox
        inbox.removeAll()
        return batch
    }

    func complete(_ id: UUID, with value: String?) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        inbox.removeAll { $0.id == id }
        deadlines.removeValue(forKey: id)?.cancel()
        continuation.resume(returning: value)
    }

    func finishSession(_ id: UUID, failed: Bool = false) {
        guard sessionID == id else { return }
        isSessionRunning = false
        if failed {
            for requestID in Array(pending.keys) { complete(requestID, with: nil) }
        }
        if !inbox.isEmpty { triggerSession() }
    }

    func cancelAll() {
        sessionID = UUID()
        configuration = nil
        isSessionRunning = false
        for id in Array(pending.keys) { complete(id, with: nil) }
    }

    private func cancelRequest(_ id: UUID) {
        guard pending[id] != nil else { return }
        complete(id, with: nil)
        // A stalled/abandoned session must not trap later retries behind it.
        if pending.isEmpty { cancelAll() }
    }

    private func triggerSession() {
        // New requests join the active session instead of invalidating each other.
        guard !isSessionRunning else { return }
        isSessionRunning = true
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
