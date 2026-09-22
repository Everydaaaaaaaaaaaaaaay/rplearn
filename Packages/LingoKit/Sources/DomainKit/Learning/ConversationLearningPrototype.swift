import Foundation
import CryptoKit

/// Opt-in observations from the real composer. Never changes conversation behavior.
public enum ConversationLearningObservation: Sendable {
    case assistance
    case unattributed
    case sent(id: UUID, text: String, voice: Bool)
}

/// Prototype rules, not a certified assessment or production reward authority.
public struct ConversationLearningLedger: Codable, Sendable, Equatable {
    public enum Origin: String, Codable, Sendable { case replay, live }
    public enum Verdict: String, Codable, Sendable { case complete, needsSupport, uncertain }
    public enum Phase: String, Codable, Sendable { case active, completed, abandoned }
    public struct Turn: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var text: String
        public var assisted: Bool
        public var voice: Bool
    }
    public struct Attempt: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var context: String
        public var character: String
        public var day: Int
        public var origin: Origin
        public var phase: Phase = .active
        public var turns: [Turn] = []
        public var assistanceUsed = false
        public var provenanceUnknown: Bool? = nil
        public var feedback = ""
        public var evidence: [UUID] = []
        public var independent = false
        public var awardedXP = 0
        public var rewardNote: String? = nil
        /// A contiguous recent suffix; a long historical turn cannot block a new short attempt.
        public func reviewTurns(maxCount: Int = 8, maxCharacters: Int = 8000) -> [Turn] {
            guard maxCount > 0, maxCharacters > 0 else { return [] }
            var selected: [Turn] = []
            var length = 0
            for turn in turns.suffix(maxCount).reversed() {
                guard turn.text.count <= maxCharacters - length else { break }
                selected.append(turn); length += turn.text.count
            }
            return selected.reversed()
        }
    }
    public struct Review: Codable, Sendable {
        public var verdict: Verdict
        public var evidenceMessageIDs: [UUID]
        public var feedback: String
        public init(verdict: Verdict, evidenceMessageIDs: [UUID], feedback: String) {
            self.verdict = verdict; self.evidenceMessageIDs = evidenceMessageIDs; self.feedback = feedback
        }
    }
    public enum Rejection: Error { case missingAttempt, closed, stale, invalidEvidence }
    public private(set) var attempts: [Attempt] = []
    /// Reward tombstones survive evidence deletion; deleting text never enables farming it again.
    public private(set) var rewardKeys: Set<String> = []
    public private(set) var revision = 0
    private var transferDeferredUntil: Int?
    public struct TransferSuggestion: Sendable, Equatable {
        public let sourceID: UUID
        public let context: String
    }
    /// One optional invitation, after a later day; no model call, notification or extra reward.
    public func transferSuggestion(day: Int, origin: Origin) -> TransferSuggestion? {
        guard active == nil, day >= (transferDeferredUntil ?? Int.min),
              let source = attempts.last(where: { $0.origin == origin && $0.phase == .completed }),
              source.day < day, !source.evidence.isEmpty, !source.turns.isEmpty else { return nil }
        let contexts = ["周末去处", "饮料选择", "推荐一本书"]
        guard let index = contexts.firstIndex(of: source.context) else { return nil }
        // Do not nag immediately after any practice (including an abandoned/free conversation).
        guard !attempts.contains(where: { $0.origin == origin && $0.day >= day }) else { return nil }
        return TransferSuggestion(sourceID: source.id, context: contexts[(index + 1) % contexts.count])
    }
    public mutating func deferTransfer(day: Int) {
        guard day < Int.max else { return }
        transferDeferredUntil = day + 1
        revision += 1
    }
    public init() {}
    public var xp: Int { attempts.reduce(0) { $0 + $1.awardedXP } }
    public var level: Int { 1 + xp / 60 }
    public var active: Attempt? { attempts.last { $0.phase == .active } }
    public var abilityDescription: String {
        let evidence = attempts.filter { $0.origin == attempts.last?.origin && $0.phase == .completed && $0.independent && !$0.evidence.isEmpty }
        let days = Set(evidence.map(\.day)), contexts = Set(evidence.map(\.context))
        if days.count >= 3 && contexts.count >= 2 { return "多个情境下已有独立表达记录，仍需持续观察" }
        if !evidence.isEmpty { return "已有独立尝试，尚不足以确认稳定掌握" }
        return "正在积累练习证据，尚不判断英语等级"
    }
    @discardableResult public mutating func begin(context: String, character: String, day: Int, origin: Origin) -> UUID {
        if let active { return active.id }
        let id = UUID()
        attempts.append(Attempt(id: id, context: context, character: character, day: day, origin: origin))
        revision += 1
        return id
    }
    public mutating func observe(_ event: ConversationLearningObservation, attemptID: UUID) {
        guard let i = attempts.firstIndex(where: { $0.id == attemptID }), attempts[i].phase == .active else { return }
        switch event {
        case .assistance: attempts[i].assistanceUsed = true
        case .unattributed: attempts[i].provenanceUnknown = true
        case .sent(let id, let text, let voice):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !attempts[i].turns.contains(where: { $0.id == id }) else { return }
            attempts[i].turns.append(Turn(id: id, text: text, assisted: attempts[i].assistanceUsed || attempts[i].provenanceUnknown == true, voice: voice))
        }
        revision += 1
    }
    /// Caller supplies the exact reviewed revision. A late result cannot overwrite later work.
    @discardableResult public mutating func apply(_ review: Review, attemptID: UUID, expectedRevision: Int, completedDay: Int? = nil) throws -> Bool {
        guard let i = attempts.firstIndex(where: { $0.id == attemptID }) else { throw Rejection.missingAttempt }
        if attempts[i].phase == .completed { return false }
        guard attempts[i].phase == .active else { throw Rejection.closed }
        guard revision == expectedRevision else { throw Rejection.stale }
        let ids = Set(review.evidenceMessageIDs)
        let turns = attempts[i].turns.filter { ids.contains($0.id) }
        guard !ids.isEmpty, ids.count == review.evidenceMessageIDs.count, turns.count == ids.count,
              review.feedback.count <= 600 else { throw Rejection.invalidEvidence }
        attempts[i].feedback = review.feedback
        if review.verdict == .complete {
            if let completedDay { attempts[i].day = completedDay }
            attempts[i].phase = .completed
            attempts[i].evidence = review.evidenceMessageIDs
            // Voice transcription is not proof of independent speaking competence.
            attempts[i].independent = !attempts[i].assistanceUsed && attempts[i].provenanceUnknown != true && turns.allSatisfy { !$0.assisted && !$0.voice }
            let keys = Set(turns.map { turn in
                let digest = SHA256.hash(data: Data(Self.normalize(turn.text).utf8)).map { String(format: "%02x", $0) }.joined()
                return "\(attempts[i].origin.rawValue)|\(digest)"
            })
            let dailyXP = attempts.filter { $0.day == attempts[i].day && $0.origin == attempts[i].origin }.reduce(0) { $0 + $1.awardedXP }
            let firstExpression = !keys.subtracting(rewardKeys).isEmpty
            rewardKeys.formUnion(keys)
            if !firstExpression { attempts[i].independent = false }
            if firstExpression && dailyXP < 30 { attempts[i].awardedXP = 10 }
            attempts[i].rewardNote = !firstExpression
                ? "这些表达已记录过，本次保留练习记录，不重复增加经验。"
                : dailyXP >= 30 ? "今天的参与经验已达上限，新的表达仍会保留。" : nil
        } else {
            // Feedback may contain a model-written example. Future attempts are supported practice.
            attempts[i].assistanceUsed = true
        }
        revision += 1
        return true
    }
    public mutating func abandon(_ id: UUID, endedDay: Int? = nil) {
        guard let i = attempts.firstIndex(where: { $0.id == id }), attempts[i].phase == .active else { return }
        if let endedDay { attempts[i].day = endedDay }
        attempts[i].phase = .abandoned; revision += 1
    }
    public mutating func deleteEvidence(_ id: UUID) {
        guard let i = attempts.firstIndex(where: { $0.id == id }) else { return }
        attempts[i].turns = []; attempts[i].evidence = []; attempts[i].feedback = ""; attempts[i].independent = false
        revision += 1
    }
    private static func normalize(_ text: String) -> String {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
