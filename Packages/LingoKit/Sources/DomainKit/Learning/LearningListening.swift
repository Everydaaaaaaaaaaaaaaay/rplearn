import Foundation

public struct LearningListeningItem: Codable, Sendable, Identifiable, Equatable {
    public enum Skill: String, Codable, CaseIterable, Sendable { case detail, gist, intention }
    public let id: String
    public let band: Int
    public let skill: Skill
    public let script: String
    public let question: String
    public let options: [String]
    public let answer: Int
    public let explanation: String
    public var valid: Bool {
        let count = script.split(whereSeparator: \.isWhitespace).count
        let range = band == 1 ? 20...40 : band == 2 ? 41...70 : 71...100
        return (1...3).contains(band) && range.contains(count) && options.count == 3 && Set(options).count == 3
            && options.indices.contains(answer) && !question.isEmpty && !explanation.isEmpty
    }
}

public struct LearningListeningSession: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let band: Int
    public let startedAt: Date
    public let audioVersion: String
    public let items: [LearningListeningItem]
    public private(set) var answers: [String: Int] = [:]
    public private(set) var plays: [String: Int] = [:]
    public private(set) var finishedAt: Date?
    public private(set) var abandoned = false
    public init?(band: Int, bank: [LearningListeningItem], seen: Set<String>, now: Date, audioVersion: String = "supertonic3-F5-default-v1") {
        var selected: [LearningListeningItem] = []
        var ids = Set<String>(), scripts = Set<String>()
        for skill in LearningListeningItem.Skill.allCases {
            let options = bank.filter { item in
                guard item.band == band, item.skill == skill, item.valid, !seen.contains(item.id),
                      !ids.contains(item.id), !scripts.contains(LearningSystemPolicy.digest(item.script)) else { return false }
                ids.insert(item.id); scripts.insert(LearningSystemPolicy.digest(item.script)); return true
            }
            guard options.count >= 2 else { return nil }
            selected += options.prefix(2)
        }
        self.id = UUID(); self.band = band; self.startedAt = now; self.audioVersion = audioVersion
        self.items = selected.map { item in
            let order = item.options.indices.shuffled()
            return LearningListeningItem(id: item.id, band: item.band, skill: item.skill, script: item.script,
                question: item.question, options: order.map { item.options[$0] }, answer: order.firstIndex(of: item.answer)!, explanation: item.explanation)
        }.shuffled()
    }
    public var current: LearningListeningItem? { items.first { answers[$0.id] == nil } }
    public var score: Int { items.filter { answers[$0.id] == $0.answer }.count }
    public var passed: Bool { finishedAt != nil && !abandoned && score >= 5 }
    public mutating func completedPlayback(itemID: String) {
        guard finishedAt == nil, !abandoned, current?.id == itemID, (plays[itemID] ?? 0) < 2 else { return }
        plays[itemID, default: 0] += 1
    }
    @discardableResult public mutating func answer(_ choice: Int, now: Date) -> Bool {
        guard !abandoned, finishedAt == nil, now >= startedAt, let item = current,
              item.options.indices.contains(choice), (plays[item.id] ?? 0) >= 1 else { return false }
        answers[item.id] = choice
        if current == nil { finishedAt = now }
        return true
    }
    public mutating func abandon() { abandoned = true }
    public static func confirmed(band: Int, sessions: [Self], now: Date) -> Bool {
        let eligible = sessions.filter { $0.band == band && $0.passed && $0.finishedAt! <= now && now.timeIntervalSince($0.finishedAt!) <= 90 * LearningSystemPolicy.day }
        for a in eligible {
            for b in eligible where b.id != a.id {
                let distance = b.startedAt.timeIntervalSince(a.finishedAt!)
                guard a.audioVersion == b.audioVersion, distance >= 7 * LearningSystemPolicy.day, distance <= 30 * LearningSystemPolicy.day,
                      Set(a.items.map(\.id)).isDisjoint(with: b.items.map(\.id)),
                      Set(a.items.map { LearningSystemPolicy.digest($0.script) }).isDisjoint(with: b.items.map { LearningSystemPolicy.digest($0.script) }) else { continue }
                let skillsPass = LearningListeningItem.Skill.allCases.allSatisfy { skill in
                    [a, b].reduce(0) { total, session in total + session.items.filter { $0.skill == skill && session.answers[$0.id] == $0.answer }.count } >= 3
                }
                if skillsPass { return true }
            }
        }
        return false
    }
}
