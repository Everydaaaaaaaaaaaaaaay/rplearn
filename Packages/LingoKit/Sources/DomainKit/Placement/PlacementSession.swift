import Foundation
import PersistenceKit

/// Owns drafts, stable option order and the confirmed adaptive path.
/// Revising a confirmed answer discards dependent questions and rebuilds evidence once.
public struct PlacementSession: Sendable {
    public struct Entry: Sendable {
        public let question: PlacementQuestion
        public let optionOrder: [Int]
        public fileprivate(set) var selectedIndex: Int?
        public fileprivate(set) var listeningPlayCount = 0
        fileprivate var answer: Answer?
    }
    fileprivate enum Answer: Sendable, Equatable { case option(Int), skipped }
    private let questions: [PlacementQuestion]
    private let priorLevel: DifficultyLevel
    private let seed: UInt64
    private var listeningPlays: [String: Int] = [:]
    public private(set) var entries: [Entry] = []
    public private(set) var cursor = 0
    public private(set) var engine: AdaptivePlacementEngine
    public private(set) var isComplete = false
    public var current: Entry? { entries.indices.contains(cursor) ? entries[cursor] : nil }
    public var canGoBack: Bool { !isComplete && cursor > 0 }
    public var canConfirm: Bool {
        guard let current, let index = current.selectedIndex,
              current.question.options.indices.contains(index) else { return false }
        return !isComplete && (current.question.skill != .listening || current.listeningPlayCount > 0)
    }

    public init(questions: [PlacementQuestion], priorLevel: DifficultyLevel, seed: UInt64 = .random(in: 0...UInt64.max)) {
        self.questions = questions; self.priorLevel = priorLevel; self.seed = seed
        engine = AdaptivePlacementEngine(priorLevel: priorLevel, selectionSeed: seed)
        if let question = engine.nextQuestion(in: questions) { append(question) }
        else { isComplete = true }
    }
    public mutating func select(_ index: Int) {
        guard !isComplete, let current, current.question.options.indices.contains(index),
              current.question.skill != .listening || current.listeningPlayCount > 0 else { return }
        entries[cursor].selectedIndex = index
    }
    public mutating func recordListeningPlay() {
        guard !isComplete, current?.question.skill == .listening else { return }
        entries[cursor].listeningPlayCount = min(PlacementListeningPolicy.maximumPlayCount,
                                               entries[cursor].listeningPlayCount + 1)
        listeningPlays[entries[cursor].question.id] = entries[cursor].listeningPlayCount
    }
    public mutating func goBack() {
        guard canGoBack else { return }
        cursor -= 1
        rebuildPrefix()
    }
    @discardableResult public mutating func confirm() -> Bool {
        guard canConfirm, let index = current?.selectedIndex else { return false }
        commit(.option(index)); return true
    }
    public mutating func skip() { guard !isComplete, current != nil else { return }; commit(.skipped) }

    private mutating func commit(_ answer: Answer) {
        let changed = entries[cursor].answer != answer
        if changed { entries.removeSubrange((cursor + 1)..<entries.count) }
        entries[cursor].answer = answer
        if answer == .skipped { entries[cursor].selectedIndex = nil }
        rebuildPrefix()
        apply(answer, question: entries[cursor].question)
        if engine.shouldStop { isComplete = true; return }
        if entries.indices.contains(cursor + 1) { cursor += 1; return }
        guard let next = engine.nextQuestion(in: questions) else { isComplete = true; return }
        append(next); cursor += 1
    }
    private mutating func rebuildPrefix() {
        engine = AdaptivePlacementEngine(priorLevel: priorLevel, selectionSeed: seed)
        for entry in entries.prefix(cursor) {
            if let answer = entry.answer { apply(answer, question: entry.question) }
        }
    }
    private mutating func apply(_ answer: Answer, question: PlacementQuestion) {
        switch answer {
        case .option(let index): engine.record(question: question, selectedIndex: index)
        case .skipped: engine.skip(question: question)
        }
    }
    private mutating func append(_ question: PlacementQuestion) {
        // Deterministic per session and question, including after revisiting an unchanged path.
        var value = seed
        for byte in question.id.utf8 { value = (value ^ UInt64(byte)) &* 1099511628211 }
        var order = Array(question.options.indices)
        for index in stride(from: order.count - 1, through: 1, by: -1) {
            value = value &* 6364136223846793005 &+ 1
            order.swapAt(index, Int(value % UInt64(index + 1)))
        }
        var entry = Entry(question: question, optionOrder: order)
        entry.listeningPlayCount = listeningPlays[question.id, default: 0]
        entries.append(entry)
    }
}
