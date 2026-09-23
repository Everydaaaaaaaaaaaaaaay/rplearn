import Foundation

/// Shared by foreground recovery, the idle timer and explicit retry.
public enum LearningReviewQueue {
    /// Reserve against the date of this attempt, including a retry after UTC midnight.
    /// Persist the updated counts before contacting the provider.
    @discardableResult
    public static func reserveCall(_ calls: inout [Int: Int], now: Date) -> Bool {
        let day = LearningSystemPolicy.utcDay(now)
        guard calls[day, default: 0] < LearningSystemPolicy.dailyBatches * 2 else { return false }
        calls[day, default: 0] += 1
        return true
    }

    public struct Candidate: Sendable {
        public let id: UUID
        public let count: Int
        public let lastDate: Date
        public let idleSeconds: TimeInterval
        public let waitForIdleWhenFull: Bool
        public let blocked: Bool
        public init(id: UUID, count: Int, lastDate: Date, blocked: Bool = false, idleSeconds: TimeInterval = LearningSystemPolicy.idleSeconds, waitForIdleWhenFull: Bool = false) {
            self.id = id; self.count = count; self.lastDate = lastDate; self.blocked = blocked
            self.idleSeconds = max(0, idleSeconds); self.waitForIdleWhenFull = waitForIdleWhenFull
        }
        public func delay(now: Date) -> TimeInterval? {
            guard count > 0, !blocked else { return nil }
            return count >= LearningSystemPolicy.batchSize && !waitForIdleWhenFull
                ? 0 : max(0, idleSeconds - now.timeIntervalSince(lastDate))
        }
    }
    public static func next(_ candidates: [Candidate], now: Date, force: Bool = false) -> UUID? {
        candidates.first { candidate in
            if force { return candidate.count > 0 }
            guard let delay = candidate.delay(now: now) else { return false }
            return force || delay == 0
        }?.id
    }
    /// Preserve arrival order. Overflow remains queued, never silently discarded.
    public static func prefixCount(_ texts: [String], limit: Int = 4000) -> Int {
        var remaining = limit, count = 0
        for text in texts.prefix(8) {
            guard text.count <= remaining else { break }
            remaining -= text.count; count += 1
        }
        return count
    }
    public static func endsChallenge(paused: Bool, assessments: [LearningSystemReviewer.Assessment]) -> Bool {
        paused || assessments.contains { item in
            item.scores.count == 4 && item.scores[0] == 2 && item.scores.allSatisfy { (1...2).contains($0) } && item.scores.reduce(0,+) >= 6
        }
    }
}
