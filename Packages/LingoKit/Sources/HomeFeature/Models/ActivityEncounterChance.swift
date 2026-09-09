import Foundation

/// Soft probabilities only: identity eligibility is enforced separately.
enum ActivityEncounterChance {
    static func encounterProbability(misses: Int) -> Double {
        0.90 - 0.25 * pow(0.65, Double(max(0, misses)))
    }

    static func personWeight(encounters: Int, lastSeen: Date?, now: Date) -> Double {
        let days = lastSeen.map { max(0, now.timeIntervalSince($0)) / 86_400 } ?? 30
        let recent = exp(-days / 7)
        return max(0.02, 1 / (1 + Double(max(0, encounters)) * recent))
    }

    static func chooseIndex(weights: [Double], roll: Double) -> Int? {
        guard !weights.isEmpty else { return nil }
        let safe = weights.map { $0.isFinite ? max(0.02, $0) : 0.02 }
        var remaining = min(max(roll, 0), 1.nextDown) * safe.reduce(0, +)
        for (index, weight) in safe.enumerated() {
            remaining -= weight
            if remaining < 0 { return index }
        }
        return safe.count - 1
    }
}

/// Local activity history, scoped like ActivityJournal. Failed decoding never overwrites data.
struct ActivityEncounterHistory {
    struct Receipt: Codable, Equatable {
        let runID: UUID
        let encountersPerson: Bool
        var characterID: UUID?
        var completedAt: Date?
    }
    private struct Archive: Codable { let version: Int; var receipts: [Receipt] }
    let defaults: UserDefaults
    let key: String
    init(namespace: String, city: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = "lingotrip.encounter-chance.v1." + Data("\(namespace.utf8.count):\(namespace)\(city)".utf8).base64EncodedString()
    }
    func receipts() throws -> [Receipt] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        guard archive.version == 1 else { throw ActivityJournal.JournalError.unsupportedVersion }
        return archive.receipts
    }
    func reserve(runID: UUID, roll: Double) throws -> Receipt {
        var items = try receipts()
        if let saved = items.first(where: { $0.runID == runID }) { return saved }
        let misses = items.filter { $0.completedAt != nil }.reversed().prefix { !$0.encountersPerson }.count
        let saved = Receipt(runID: runID, encountersPerson: roll < ActivityEncounterChance.encounterProbability(misses: misses))
        items.append(saved)
        try save(items)
        return saved
    }
    func complete(runID: UUID, characterID: UUID?, now: Date = Date()) throws {
        var items = try receipts()
        guard let index = items.firstIndex(where: { $0.runID == runID }), items[index].completedAt == nil else { return }
        guard items[index].encountersPerson == (characterID != nil) else { throw ActivityJournal.JournalError.invalidCompletion }
        items[index].characterID = characterID
        items[index].completedAt = now
        try save(items)
    }
    private func save(_ items: [Receipt]) throws {
        defaults.set(try JSONEncoder().encode(Archive(version: 1, receipts: items)), forKey: key)
    }
}
