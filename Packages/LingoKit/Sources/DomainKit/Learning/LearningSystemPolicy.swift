import Foundation
import CryptoKit

/// Executable v1 product thresholds, not a calibrated CEFR assessment.
public enum LearningSystemPolicy {
    public static let version = 1
    public static let ruleRevision = 4
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
        public func requirements(band: Int) -> [String] {
            switch (self, band) {
            case (.preference, 1): ["choice", "reason"]
            case (.preference, 2): ["alternatives", "comparison", "tradeoff_or_reason"]
            case (.preference, 3): ["changed_choice", "constraint", "reason"]
            case (.experience, 1): ["past_event", "detail"]
            case (.experience, 2): ["first_event", "second_event", "sequence"]
            case (.experience, 3): ["cause", "consequence", "lesson_or_adjustment"]
            case (.planning, 1): ["intended_action", "time_or_place"]
            case (.planning, 2): ["first_action", "second_action", "sequence"]
            case (.planning, 3): ["constraint", "viable_alternative"]
            case (.clarification, 1): ["unclear_point", "request"]
            case (.clarification, 2): ["original_meaning", "rephrasing"]
            case (.clarification, 3): ["misunderstanding", "correction", "understanding_check"]
            default: []
            }
        }
        public var rubric: String {
            switch self {
            case .preference: "1: choice with meaningful reason; 2: compare alternatives and explain tradeoff; 3: revise choice under changed constraints and explain"
            case .experience: "1: a past event and detail; 2: sequence at least two events; 3: explain cause and consequence plus a relevant lesson or a next-time adjustment based on that experience; an emotion is not required"
            case .planning: "1: intended action and time or place; 2: sequence two planned actions; 3: resolve a changed constraint with a viable alternative"
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
    public enum StorageCompatibilityError: Error, LocalizedError {
        case newerOrUnsupportedVersion
        public var errorDescription: String? {
            "这份学习记录使用了当前版本不支持的格式或规则，请使用更新版本打开。"
        }
    }
    public struct Ledger: Codable, Sendable, Equatable {
        public var version = LearningSystemPolicy.version
        public private(set) var ruleRevision: Int? = LearningSystemPolicy.ruleRevision
        public func validateStorageCompatibility() throws {
            guard version == LearningSystemPolicy.version,
                  (1...LearningSystemPolicy.ruleRevision).contains(ruleRevision ?? 1) else {
                throw StorageCompatibilityError.newerOrUnsupportedVersion
            }
        }
        public mutating func adoptCurrentRules() { ruleRevision = LearningSystemPolicy.ruleRevision }
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
        /// Union durable observations across devices. Deletion wins and rewards remain
        /// bounded per day; syncing is never a new learning event.
        public mutating func merge(_ other: Self) throws {
            try other.validateStorageCompatibility()
            var observations = Dictionary(evidence.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for item in other.evidence {
                if let old = observations[item.id] {
                    if item.deleted && !old.deleted { observations[item.id] = item }
                } else { observations[item.id] = item }
            }
            evidence = observations.values.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
            var awards = Dictionary(rewards.map { ($0.key, $0) }, uniquingKeysWith: { a, b in a.date <= b.date ? a : b })
            for item in other.rewards {
                if let old = awards[item.key], old.date < item.date || (old.date == item.date && old.xp >= item.xp) { continue }
                awards[item.key] = item
            }
            var totals: [Int: Int] = [:]
            rewards = awards.values.sorted { $0.date == $1.date ? $0.key < $1.key : $0.date < $1.date }.map { item in
                let day = LearningSystemPolicy.utcDay(item.date)
                let xp = min(max(0, item.xp), max(0, dailyXP - totals[day, default: 0]))
                totals[day, default: 0] += xp
                return Reward(key: item.key, date: item.date, xp: xp)
            }
            processed.formUnion(other.processed)
            latestDate = max(latestDate, other.latestDate)
            deferredUntil = [deferredUntil, other.deferredUntil].compactMap { $0 }.max()
            adoptCurrentRules()
        }
        public func independentEvidence(skill: Skill, band: Int, now: Date, maxAge: TimeInterval = 90 * LearningSystemPolicy.day, confirmation: Bool? = nil) -> [Evidence] {
            var fingerprints = Set<String>(), days = Set<Int>()
            var originalIDs: [String: UUID] = [:]
            for item in evidence where item.skill == skill && item.band == band {
                if originalIDs[item.fingerprint] == nil { originalIDs[item.fingerprint] = item.id }
            }
            // A partial attempt must not consume the day's sole evidence slot before
            // a later independently completed expression. Duplicate provenance stays unchanged.
            return evidence.sorted {
                if $0.successful != $1.successful { return $0.successful }
                return $0.date < $1.date
            }.filter { item in
                guard !item.deleted, item.independent, item.skill == skill, item.band == band,
                      confirmation == nil || item.confirmation == confirmation,
                      originalIDs[item.fingerprint] == item.id,
                      item.date <= now, now.timeIntervalSince(item.date) <= maxAge,
                      !fingerprints.contains(item.fingerprint), !days.contains(utcDay(item.date)) else { return false }
                fingerprints.insert(item.fingerprint); days.insert(utcDay(item.date)); return true
            }.sorted { $0.date < $1.date }
        }
        private func isReady(_ observations: [Evidence]) -> Bool {
            let window = observations.suffix(6)
            let successes = window.filter(\.successful)
            // Recent performance and observation duration are different requirements.
            // Six consecutive daily samples span only five days, however long a
            // learner has participated; measuring duration on that suffix locks them out.
            return window.count == 6 && successes.count >= 5 && Set(successes.map(\.topic)).count >= 3
                && (window.last?.date.timeIntervalSince(observations.first!.date) ?? 0) >= 7 * day
        }
        private func basis(skill: Skill, band: Int, before date: Date) -> [Evidence] {
            Array(independentEvidence(skill: skill, band: band, now: date, confirmation: false)
                .filter { $0.date < date })
        }
        public func status(skill: Skill, band: Int, now: Date) -> Status {
            let current = independentEvidence(skill: skill, band: band, now: now, confirmation: false)
            let confirms = independentEvidence(skill: skill, band: band, now: now, maxAge: .infinity, confirmation: true)
                .filter(\.successful)
            var confirmedAt: Date?
            var pendingConfirmation = false
            for (i, a) in confirms.enumerated() {
                let basis = basis(skill: skill, band: band, before: a.date)
                guard isReady(basis), let first = basis.first else { continue }
                if now.timeIntervalSince(first.date) <= 90 * day { pendingConfirmation = true }
                for b in confirms.dropFirst(i + 1) where b.topic != a.topic && b.date.timeIntervalSince(a.date) >= 2 * day && b.date.timeIntervalSince(first.date) >= 14 * day && b.date.timeIntervalSince(first.date) <= 90 * day {
                    confirmedAt = max(confirmedAt ?? .distantPast, b.date)
                }
            }
            if let confirmedAt, now.timeIntervalSince(confirmedAt) <= 90 * day { return .confirmed }
            if isReady(current) || pendingConfirmation { return .ready }
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
            let attempts = independentEvidence(skill: skill, band: band, now: now, confirmation: true)
            guard let last = attempts.last else { return nil }
            // Anchor the second task to the basis that actually unlocked the first.
            // Later ordinary chat must not erase either the wait or the earned basis.
            for firstConfirmation in attempts where firstConfirmation.successful {
                let basis = basis(skill: skill, band: band, before: firstConfirmation.date)
                if isReady(basis), let first = basis.first, now.timeIntervalSince(first.date) <= 90 * day {
                    return max(last.date.addingTimeInterval(2 * day), first.date.addingTimeInterval(14 * day))
                }
            }
            return last.date.addingTimeInterval(2 * day)
        }
        public func nextReview(now: Date) -> Evidence? {
            guard now >= latestDate, now >= (deferredUntil ?? .distantPast) else { return nil }
            return Skill.allCases.compactMap { skill -> Evidence? in
                // Retain the first occurrence, including deletion tombstones. Repeating
                // an expression cannot restore a deleted source or postpone retrieval.
                var fingerprints = Set<String>()
                let items = evidence.filter { item in
                    guard item.skill == skill, fingerprints.insert(item.fingerprint).inserted else { return false }
                    return !item.deleted && item.successful && item.date <= now
                }.sorted { $0.date < $1.date }
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
