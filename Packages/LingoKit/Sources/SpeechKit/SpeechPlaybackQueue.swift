import Foundation

/// A visible screen owns a FIFO; snapshots prevent replay after translation or reload.
@MainActor
public final class SpeechPlaybackQueue {
    public struct Item: Equatable {
        public let id: UUID
        public let request: SpeechRequest
        public init(id: UUID, request: SpeechRequest) { self.id = id; self.request = request }
    }
    public struct Snapshot: Equatable {
        public let enabled: Bool
        public let items: [Item]
        public init(enabled: Bool, items: [Item]) { self.enabled = enabled; self.items = items }
    }

    /// Apply control and message changes together, using the previous rendered
    /// snapshot as history. A new bubble arriving in the enable frame is not history.
    public func synchronize(from previous: Snapshot, to current: Snapshot) {
        configure(enabled: current.enabled, existingIDs: previous.items.map(\.id))
        observe(current.items)
    }

    private let speech: any SpeechService
    private var seen: Set<UUID> = []
    private var pending: [Item] = []
    private var worker: Task<Void, Never>?
    private var stopping: Task<Void, Never>?
    private var generation = UUID()
    private var enabled = false

    public init(speech: any SpeechService) { self.speech = speech }

    public func configure(enabled: Bool, existingIDs: [UUID]) {
        if self.enabled != enabled || !enabled { seen.formUnion(existingIDs) }
        self.enabled = enabled
        if !enabled { interrupt() }
    }

    public func observe(_ items: [Item]) {
        for item in items {
            guard !item.request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(item.id).inserted, enabled else { continue }
            pending.append(item)
        }
        guard enabled, worker == nil, !pending.isEmpty else { return }
        let cycle = UUID(); generation = cycle
        let barrier = stopping
        worker = Task { [weak self] in
            await barrier?.value
            guard let self else { return }
            while !Task.isCancelled, generation == cycle, enabled, !pending.isEmpty {
                let item = pending.removeFirst()
                await speech.speakAndWait(item.request)
            }
            if generation == cycle { worker = nil }
        }
    }

    /// Explicit user audio actions take priority; discarded bubbles are not replayed later.
    @discardableResult
    public func interrupt() -> Task<Void, Never>? {
        pending.removeAll()
        generation = UUID()
        guard let worker else { return stopping }
        worker.cancel(); self.worker = nil
        let prior = stopping
        let speech = speech
        let task = Task {
            await prior?.value
            await speech.stopSpeaking()
            await worker.value
        }
        stopping = task
        return task
    }
}
