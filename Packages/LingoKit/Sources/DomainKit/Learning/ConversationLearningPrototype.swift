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
    @discardableResult public mutating func apply(_ review: Review, attemptID: UUID, expectedRevision: Int) throws -> Bool {
        guard let i = attempts.firstIndex(where: { $0.id == attemptID }) else { throw Rejection.missingAttempt }
        if attempts[i].phase == .completed { return false }
        guard attempts[i].phase == .active else { throw Rejection.closed }
        guard revision == expectedRevision else { throw Rejection.stale }
        let ids = Set(review.evidenceMessageIDs)
        let turns = attempts[i].turns.filter { ids.contains($0.id) }
        guard !ids.isEmpty, turns.count == ids.count,
              review.feedback.count <= 600 else { throw Rejection.invalidEvidence }
        attempts[i].feedback = review.feedback
        if review.verdict == .complete {
            attempts[i].phase = .completed
            attempts[i].evidence = review.evidenceMessageIDs
            // Voice transcription is not proof of independent speaking competence.
            attempts[i].independent = !attempts[i].assistanceUsed && attempts[i].provenanceUnknown != true && turns.allSatisfy { !$0.assisted && !$0.voice }
            let keys = Set(turns.map { turn in
                let digest = SHA256.hash(data: Data(Self.normalize(turn.text).utf8)).map { String(format: "%02x", $0) }.joined()
                return "\(attempts[i].origin.rawValue)|\(digest)"
            })
            let dailyXP = attempts.filter { $0.day == attempts[i].day && $0.origin == attempts[i].origin }.reduce(0) { $0 + $1.awardedXP }
            let firstExpression = keys.isDisjoint(with: rewardKeys)
            rewardKeys.formUnion(keys)
            if !firstExpression { attempts[i].independent = false }
            if firstExpression && dailyXP < 30 { attempts[i].awardedXP = 10 }
        }
        revision += 1
        return true
    }
    public mutating func abandon(_ id: UUID) {
        guard let i = attempts.firstIndex(where: { $0.id == id }), attempts[i].phase == .active else { return }
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
