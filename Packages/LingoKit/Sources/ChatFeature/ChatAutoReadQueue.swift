import Foundation
import SpeechKit

/// One visible chat owns a FIFO; snapshots also prevent replay after translation or reload.
@MainActor
final class ChatAutoReadQueue {
    struct Item: Equatable {
        let id: UUID
        let request: SpeechRequest
    }
    struct Snapshot: Equatable {
        let enabled: Bool
        let items: [Item]
    }

    /// Apply control and message changes together, using the previous rendered
    /// snapshot as history. A new bubble arriving in the enable frame is not history.
    func synchronize(from previous: Snapshot, to current: Snapshot) {
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

    init(speech: any SpeechService) { self.speech = speech }

    func configure(enabled: Bool, existingIDs: [UUID]) {
        if self.enabled != enabled || !enabled { seen.formUnion(existingIDs) }
        self.enabled = enabled
        if !enabled { interrupt() }
    }

    func observe(_ items: [Item]) {
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
    func interrupt() -> Task<Void, Never>? {
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
