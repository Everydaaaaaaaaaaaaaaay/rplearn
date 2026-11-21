import Foundation

public struct LLMDeadlinePolicy: Sendable {
    public var completion: Duration
    public var firstToken: Duration
    public var idle: Duration
    public var streamTotal: Duration

    public init(completion: Duration = .seconds(75), firstToken: Duration = .seconds(45),
                idle: Duration = .seconds(25), streamTotal: Duration = .seconds(120)) {
        self.completion = completion; self.firstToken = firstToken
        self.idle = idle; self.streamTotal = streamTotal
    }
}

final class LLMStreamProgress: @unchecked Sendable {
    private let lock = NSLock()
    private let started = ContinuousClock.now
    private var lastToken: ContinuousClock.Instant?
    private var finished = false

    func recordToken() { lock.withLock { lastToken = .now } }
    func finish() -> Bool {
        lock.withLock {
            guard !finished else { return false }
            finished = true
            return true
        }
    }
    func remaining(_ policy: LLMDeadlinePolicy) -> Duration? {
        lock.withLock {
            guard !finished else { return nil }
            let now = ContinuousClock.now
            let activity = lastToken.map { $0.advanced(by: policy.idle) }
                ?? started.advanced(by: policy.firstToken)
            return now.duration(to: min(activity, started.advanced(by: policy.streamTotal)))
        }
    }
}
