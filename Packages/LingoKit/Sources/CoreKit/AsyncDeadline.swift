import Foundation

/// A bounded wait even when an underlying callback ignores task cancellation.
/// The losing task is cancelled and its late result cannot resume the caller again.
public enum AsyncDeadline {
    public static func run<Value: Sendable>(
        timeout: Duration,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let race = DeadlineRace<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.install(continuation)
                let worker = Task {
                    guard !race.isFinished else { return }
                    do {
                        try Task.checkCancellation()
                        race.resolve(.success(try await operation()))
                    } catch { race.resolve(.failure(error)) }
                }
                let timer = Task {
                    do { try await Task.sleep(for: max(.zero, timeout)) }
                    catch { return }
                    race.resolve(.failure(URLError(.timedOut)))
                }
                race.attach(worker: worker, timer: timer)
            }
        } onCancel: {
            race.resolve(.failure(CancellationError()))
        }
    }
}

private final class DeadlineRace<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var outcome: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?
    private var worker: Task<Void, Never>?
    private var timer: Task<Void, Never>?

    var isFinished: Bool { lock.withLock { outcome != nil } }

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        let resolved = lock.withLock { () -> Result<Value, Error>? in
            if let outcome { return outcome }
            self.continuation = continuation
            return nil
        }
        if let resolved { continuation.resume(with: resolved) }
    }

    func attach(worker: Task<Void, Never>, timer: Task<Void, Never>) {
        let finished = lock.withLock {
            guard outcome == nil else { return true }
            self.worker = worker; self.timer = timer
            return false
        }
        if finished { worker.cancel(); timer.cancel() }
    }

    func resolve(_ result: Result<Value, Error>) {
        let pending = lock.withLock { () -> (CheckedContinuation<Value, Error>?, Task<Void, Never>?, Task<Void, Never>?) in
            guard outcome == nil else { return (nil, nil, nil) }
            outcome = result
            let pending = (continuation, worker, timer)
            continuation = nil; worker = nil; timer = nil
            return pending
        }
        pending.0?.resume(with: result)
        pending.1?.cancel()
        pending.2?.cancel()
    }
}
