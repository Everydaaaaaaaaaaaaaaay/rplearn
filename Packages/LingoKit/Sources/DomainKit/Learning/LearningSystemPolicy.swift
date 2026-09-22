import Foundation
import CryptoKit

/// Executable v1 product thresholds, not a calibrated CEFR assessment.
public enum LearningSystemPolicy {
    public static let version = 1
    public static let day: TimeInterval = 86_400
    public static let idleSeconds: TimeInterval = 90
    public static let batchSize = 4
    public static let dailyBatches = 6
    public static let dailyXP = 30
    public enum Skill: String, Codable, CaseIterable, Sendable {
        case preference, experience, planning, clarification
        public var title: String {
            switch self {
            case .preference: "表达选择与理由"
            case .experience: "描述经历"
            case .planning: "安排计划"
            case .clarification: "澄清误解"
            }
        }
        public var rubric: String {
            switch self {
            case .preference: "1: choice with meaningful reason; 2: compare alternatives and explain tradeoff; 3: revise choice under changed constraints and explain"
            case .experience: "1: a past event and detail; 2: sequence at least two events; 3: explain cause and consequence plus reflection"
            case .planning: "1: intended action and time or place; 2: sequence two planned actions; 3: resolve a scheduling conflict with a viable alternative"
            case .clarification: "1: identify unclear content and ask clarification; 2: rephrase own meaning; 3: correct a specific misunderstanding and check shared understanding"
            }
        }
    }
    public struct Evidence: Codable, Sendable, Equatable, Identifiable {
        public let id: UUID
        public let batchID: UUID
        public let characterID: UUID
        public let date: Date
        public let skill: Skill
        public let band: Int
        public let topic: String
        public let scores: [Int]
        public var quote: String
        public var explanation: String
        public let independent: Bool
        public let confirmation: Bool
        public let fingerprint: String
        public var deleted: Bool = false
        public init(id: UUID = UUID(), batchID: UUID, characterID: UUID, date: Date, skill: Skill, band: Int,
                    topic: String, scores: [Int], quote: String, explanation: String, independent: Bool, confirmation: Bool = false) {
            self.id = id; self.batchID = batchID; self.characterID = characterID; self.date = date
            self.skill = skill; self.band = band; self.topic = topic; self.scores = scores
            self.quote = quote; self.explanation = explanation; self.independent = independent
            self.confirmation = confirmation; self.fingerprint = LearningSystemPolicy.digest(quote)
        }
        public var valid: Bool { (1...3).contains(band) && scores.count == 4 && scores.allSatisfy { (0...2).contains($0) } && !quote.isEmpty && !topic.isEmpty }
        public var successful: Bool { valid && scores[0] == 2 && scores.allSatisfy { $0 >= 1 } && scores.reduce(0, +) >= 6 }
    }
    public enum Status: String, Sendable {
        case unseen = "尚未观察", attempted = "已有尝试", independent = "已有独立证据"
        case ready = "待确认", confirmed = "已确认", stale = "需重新确认"
    }
    public struct Reward: Codable, Sendable, Equatable {
        public let key: String
        public let date: Date
        public let xp: Int
    }
    public struct Ledger: Codable, Sendable, Equatable {
        public var version = LearningSystemPolicy.version
        public private(set) var evidence: [Evidence] = []
        public private(set) var rewards: [Reward] = []
        public private(set) var processed: Set<UUID> = []
        public private(set) var latestDate: Date = .distantPast
        public var deferredUntil: Date?
        public init() {}
        public var xp: Int { rewards.reduce(0) { $0 + $1.xp } }
        public var level: Int { 1 + xp / 100 }
        @discardableResult public mutating func record(_ items: [Evidence], batchID: UUID, now: Date) -> Bool {
            guard now >= latestDate, !processed.contains(batchID), items.allSatisfy({ $0.valid && $0.batchID == batchID && $0.date <= now }) else { return false }
            processed.insert(batchID); latestDate = now
            evidence.append(contentsOf: items)
            if let item = items.first(where: \.successful) { award(key: item.fingerprint, now: now) }
            return true
        }
        public mutating func award(key: String, now: Date) {
            guard now >= latestDate, !rewards.contains(where: { $0.key == key }) else { return }
            latestDate = now
            let total = rewards.filter { LearningSystemPolicy.utcDay($0.date) == LearningSystemPolicy.utcDay(now) }.reduce(0) { $0 + $1.xp }
            rewards.append(Reward(key: key, date: now, xp: total < dailyXP ? 10 : 0))
        }
        public mutating func delete(_ id: UUID) {
            guard let i = evidence.firstIndex(where: { $0.id == id }) else { return }
            evidence[i].quote = ""; evidence[i].explanation = ""; evidence[i].deleted = true
        }
        public func independentEvidence(skill: Skill, band: Int, now: Date, maxAge: TimeInterval = 90 * LearningSystemPolicy.day) -> [Evidence] {
            var fingerprints = Set<String>(), days = Set<Int>()
            var originalIDs: [String: UUID] = [:]
            for item in evidence where item.skill == skill && item.band == band {
                if originalIDs[item.fingerprint] == nil { originalIDs[item.fingerprint] = item.id }
            }
            return evidence.sorted { $0.date < $1.date }.filter { item in
                guard !item.deleted, item.independent, item.skill == skill, item.band == band,
                      originalIDs[item.fingerprint] == item.id,
                      item.date <= now, now.timeIntervalSince(item.date) <= maxAge,
                      !fingerprints.contains(item.fingerprint), !days.contains(utcDay(item.date)) else { return false }
                fingerprints.insert(item.fingerprint); days.insert(utcDay(item.date)); return true
            }
        }
        public func status(skill: Skill, band: Int, now: Date) -> Status {
            let current = independentEvidence(skill: skill, band: band, now: now)
            func isReady(_ window: [Evidence]) -> Bool {
                let successes = window.filter(\.successful)
                return window.count == 6 && successes.count >= 5 && Set(successes.map(\.topic)).count >= 3
                    && (window.last?.date.timeIntervalSince(window.first!.date) ?? 0) >= 7 * day
            }
            let history = independentEvidence(skill: skill, band: band, now: now, maxAge: .infinity)
            let confirms = history.filter { $0.confirmation && $0.successful }
            var confirmedAt: Date?
            for (i, a) in confirms.enumerated() {
                let basis = Array(history.filter { !$0.confirmation && $0.date < a.date && a.date.timeIntervalSince($0.date) <= 90 * day }.suffix(6))
                guard isReady(basis), let first = basis.first else { continue }
                for b in confirms.dropFirst(i + 1) where b.topic != a.topic && b.date.timeIntervalSince(a.date) >= 2 * day && b.date.timeIntervalSince(first.date) >= 14 * day && b.date.timeIntervalSince(first.date) <= 90 * day {
                    confirmedAt = max(confirmedAt ?? .distantPast, b.date)
                }
            }
            if let confirmedAt, now.timeIntervalSince(confirmedAt) <= 90 * day { return .confirmed }
            let ready = isReady(Array(current.filter { !$0.confirmation }.suffix(6)))
            if ready { return .ready }
            if confirmedAt != nil { return .stale }
            if !current.filter(\.successful).isEmpty { return .independent }
            if evidence.contains(where: { !$0.deleted && $0.skill == skill && $0.band == band }) {
                if evidence.filter({ !$0.deleted && $0.skill == skill && $0.band == band }).allSatisfy({ now.timeIntervalSince($0.date) > 90 * day }) { return .stale }
                return .attempted
            }
            return .unseen
        }
        public func nextConfirmationDate(skill: Skill, band: Int, now: Date) -> Date? {
            guard status(skill: skill, band: band, now: now) == .ready else { return nil }
            let entries = independentEvidence(skill: skill, band: band, now: now)
            let basis = Array(entries.filter { !$0.confirmation }.suffix(6))
            guard let first = basis.first, let last = basis.last,
                  let confirmation = entries.last(where: { $0.confirmation && $0.date > last.date }) else { return nil }
            return max(confirmation.date.addingTimeInterval(2 * day), first.date.addingTimeInterval(14 * day))
        }
        public func nextReview(now: Date) -> Evidence? {
            guard now >= latestDate, now >= (deferredUntil ?? .distantPast) else { return nil }
            return Skill.allCases.compactMap { skill -> Evidence? in
                let items = evidence.filter { !$0.deleted && $0.skill == skill && $0.successful }
                guard let last = items.last else { return nil }
                let interval = items.count == 1 ? 2 : items.count == 2 ? 7 : 21
                return now.timeIntervalSince(last.date) >= Double(interval) * day ? last : nil
            }.min { $0.date < $1.date }
        }
    }
    public static func utcDay(_ date: Date) -> Int { Int(floor(date.timeIntervalSince1970 / day)) }
    public static func digest(_ text: String) -> String {
        let normalized = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        return SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public extension Notification.Name {
    static let learningChallengeDidBegin = Notification.Name("LingoTripLearningChallengeDidBegin")
}
