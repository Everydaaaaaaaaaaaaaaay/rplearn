import Foundation
import PersistenceKit

/// 从基础题逐步探测学习起点。手工难度参数仅用于学习建议，不是考试认证。
/// 所有人从相同的低难度开始；累计三次错误即停止，跳过不更新能力估计。
public struct AdaptivePlacementEngine: Sendable {
    public static let maximumQuestionCount = 20
    public static let maximumMistakes = 3
    public static let maximumListeningQuestions = 2
    public static let maximumDifficultyStep = 0.5

    private static let thetaGrid: [Double] = stride(
        from: -3.25,
        through: 3.25,
        by: 0.05
    ).map { $0 }

    private let selectionSeed: UInt64
    private var logPosterior: [Double]
    public private(set) var responses: [PlacementResponse] = []

    public init(
        priorLevel: DifficultyLevel,
        selectionSeed: UInt64 = UInt64.random(in: 0...UInt64.max)
    ) {
        self.selectionSeed = selectionSeed
        // Self-reported schooling or exam familiarity must not force a high starting estimate.
        let priorMean = -1.5
        let priorStandardDeviation = 1.7
        logPosterior = Self.thetaGrid.map { theta in
            -0.5 * pow((theta - priorMean) / priorStandardDeviation, 2)
        }
        normalizeLogPosterior()
    }

    public var ability: Double {
        posteriorMoments.mean
    }

    public var standardError: Double {
        posteriorMoments.standardDeviation
    }

    public var mistakeCount: Int { responses.filter { !$0.wasCorrect && !$0.wasSkipped }.count }
    public var answeredCount: Int { responses.filter { !$0.wasSkipped }.count }
    public var skippedCount: Int { responses.filter(\.wasSkipped).count }
    public var stopReason: PlacementStopReason? {
        if mistakeCount >= Self.maximumMistakes { return .threeMistakes }
        if responses.count >= Self.maximumQuestionCount { return .questionLimit }
        return nil
    }
    public var shouldStop: Bool { stopReason != nil }
    public var measurementProgress: Double {
        shouldStop ? 1 : Double(responses.count) / Double(Self.maximumQuestionCount)
    }

    // A few easy successes followed by skips must not imply advanced proficiency.
    private var supportedAbility: Double {
        guard let highest = responses.filter(\.wasCorrect).map(\.difficulty).max() else {
            let attempted = responses.filter { !$0.wasSkipped }
            guard attempted.count >= 3, let easiest = attempted.map(\.difficulty).min() else { return ability }
            return max(-3.25, min(ability, easiest - 0.35))
        }
        return min(ability, highest + 0.35)
    }
    public var levelConfidence: Double {
        let ordinal = Self.difficultyLevel(for: supportedAbility).placementOrdinal
        let probability = zip(Self.thetaGrid, normalizedPosterior)
            .filter { abs(Self.difficultyLevel(for: $0.0).placementOrdinal - ordinal) <= 1 }
            .reduce(0) { $0 + $1.1 }
        return answeredCount < 8 ? min(0.49, probability) : probability
    }

    public func nextQuestion(in questions: [PlacementQuestion]) -> PlacementQuestion? {
        guard !shouldStop else { return nil }
        let used = Set(responses.map(\.questionID))
        let last = responses.last
        let floor = last?.difficulty ?? -3.0
        let target = last.map { $0.difficulty + ($0.wasCorrect ? 0.4 : 0.05) } ?? -3.0
        var candidates = questions.filter { !used.contains($0.id) && $0.difficulty >= floor - 0.0001 }
        let listeningCount = responses.filter { $0.skill == .listening }.count
        let listeningSlot = [7, 15].contains(responses.count)
            && listeningCount < Self.maximumListeningQuestions
        let listening = candidates.filter {
            $0.skill == .listening && $0.difficulty <= floor + Self.maximumDifficultyStep
        }
        if listeningSlot, !listening.isEmpty {
            candidates = listening
        } else {
            candidates = candidates.filter { $0.skill != .listening }
        }
        guard !candidates.isEmpty else { return nil }
        // Stay near the current step, including after a mistake or a skipped item.
        let smooth = candidates.filter { $0.difficulty <= floor + Self.maximumDifficultyStep }
        guard !smooth.isEmpty else { return nil }
        candidates = smooth
        let counts = Dictionary(grouping: responses, by: \.skill).mapValues(\.count)
        let ranked = candidates.sorted {
            let left = abs($0.difficulty - target) + Double(counts[$0.skill, default: 0]) * 0.025
            let right = abs($1.difficulty - target) + Double(counts[$1.skill, default: 0]) * 0.025
            if abs(left - right) < 0.0001 { return $0.id < $1.id }
            return left < right
        }
        let bestDistance = abs(ranked[0].difficulty - target)
        let pool = Array(ranked.prefix(4).filter { abs($0.difficulty - target) <= bestDistance + 0.1 })
        return pool[stableChoiceIndex(upperBound: pool.count)]
    }

    public mutating func record(question: PlacementQuestion, selectedIndex: Int) {
        guard !shouldStop, question.options.indices.contains(selectedIndex),
              !responses.contains(where: { $0.questionID == question.id }) else { return }
        let correct = selectedIndex == question.correctIndex
        for index in Self.thetaGrid.indices {
            let probability = Self.probabilityCorrect(theta: Self.thetaGrid[index], question: question)
            logPosterior[index] += log(max(correct ? probability : 1 - probability, 1e-12))
        }
        normalizeLogPosterior()
        responses.append(PlacementResponse(questionID: question.id, skill: question.skill,
            format: question.format, wasCorrect: correct, difficulty: question.difficulty))
    }

    public mutating func skip(question: PlacementQuestion) {
        guard !shouldStop, !responses.contains(where: { $0.questionID == question.id }) else { return }
        responses.append(PlacementResponse(questionID: question.id, skill: question.skill,
            format: question.format, wasCorrect: false, difficulty: question.difficulty, wasSkipped: true))
    }

    public func result() -> PlacementResult {
        let mean = supportedAbility
        let error = standardError
        let score = Self.score(for: mean)
        let credibleRange = posteriorCredibleRange()
        let lowerScore = Self.score(for: min(mean, credibleRange.lowerBound))
        let demonstratedCeiling = responses.filter(\.wasCorrect).map(\.difficulty).max().map { $0 + 0.35 }
        let upperAbility = min(credibleRange.upperBound, demonstratedCeiling ?? credibleRange.upperBound)
        let upperScore = Self.score(for: max(mean, upperAbility))
        let skillResults = PlacementSkill.allCases.map { skill in
            let matching = responses.filter { $0.skill == skill && !$0.wasSkipped }
            return PlacementSkillResult(
                skill: skill,
                correct: matching.filter(\.wasCorrect).count,
                total: matching.count
            )
        }

        return PlacementResult(
            ability: mean,
            standardError: error,
            levelConfidence: levelConfidence,
            score: score,
            scoreRange: min(lowerScore, upperScore)...max(lowerScore, upperScore),
            difficultyLevel: Self.difficultyLevel(for: mean),
            referenceLevel: Self.referenceLevel(for: mean),
            answeredCount: answeredCount,
            skillResults: skillResults,
            skippedCount: skippedCount,
            mistakeCount: mistakeCount,
            stopReason: stopReason ?? .questionBankExhausted
        )
    }

    public static func difficultyLevel(for ability: Double) -> DifficultyLevel {
        switch ability {
        case ..<(-2.75): .kindergarten
        case ..<(-2.45): .primary1
        case ..<(-2.15): .primary2
        case ..<(-1.85): .primary3
        case ..<(-1.55): .primary4
        case ..<(-1.25): .primary5
        case ..<(-0.95): .primary6
        case ..<(-0.6): .junior1
        case ..<(-0.25): .junior2
        case ..<0.1: .junior3
        case ..<0.45: .senior1
        case ..<0.8: .senior2
        case ..<1.15: .senior3
        case ..<1.55: .undergraduate
        case ..<2.05: .postgraduate
        default: .advanced
        }
    }

    public static func referenceLevel(for ability: Double) -> PlacementReferenceLevel {
        switch ability {
        case ..<(-1.75): .preA1
        case ..<(-1.0): .a1
        case ..<(-0.25): .a2
        case ..<0.55: .b1
        case ..<1.25: .b2
        case ..<1.9: .c1
        default: .c2
        }
    }

    public static func score(for ability: Double) -> Int {
        Int(round(((min(max(ability, -3.25), 3.25) + 3.25) / 6.5) * 100))
    }

    private var posteriorMoments: (mean: Double, standardDeviation: Double) {
        let probabilities = normalizedPosterior
        let mean = zip(Self.thetaGrid, probabilities)
            .reduce(0) { $0 + $1.0 * $1.1 }
        let variance = zip(Self.thetaGrid, probabilities)
            .reduce(0) { partial, pair in
                partial + pow(pair.0 - mean, 2) * pair.1
            }
        return (mean, sqrt(max(variance, 0)))
    }

    private var normalizedPosterior: [Double] {
        let weights = logPosterior.map(exp)
        let total = weights.reduce(0, +)
        guard total > 0 else {
            return Array(
                repeating: 1 / Double(Self.thetaGrid.count),
                count: Self.thetaGrid.count
            )
        }
        return weights.map { $0 / total }
    }

    private static func probabilityCorrect(
        theta: Double,
        question: PlacementQuestion
    ) -> Double {
        let guessing = 1 / Double(question.options.count)
        let logistic = 1 / (
            1 + exp(-question.discrimination * (theta - question.difficulty))
        )
        return guessing + (1 - guessing) * logistic
    }

    private func stableChoiceIndex(upperBound: Int) -> Int {
        guard upperBound > 1 else { return 0 }
        var value = selectionSeed &+ UInt64(responses.count) &* 0x9E3779B97F4A7C15
        value ^= value >> 30
        value &*= 0xBF58476D1CE4E5B9
        value ^= value >> 27
        value &*= 0x94D049BB133111EB
        value ^= value >> 31
        return Int(value % UInt64(upperBound))
    }

    /// Internal posterior range; the user-facing result remains a provisional learning suggestion.
    private func posteriorCredibleRange() -> ClosedRange<Double> {
        posteriorQuantile(0.05)...posteriorQuantile(0.95)
    }

    private func posteriorQuantile(_ quantile: Double) -> Double {
        var cumulative = 0.0
        for (theta, probability) in zip(Self.thetaGrid, normalizedPosterior) {
            cumulative += probability
            if cumulative >= quantile {
                return theta
            }
        }
        return Self.thetaGrid.last ?? 3
    }

    private mutating func normalizeLogPosterior() {
        guard let maximum = logPosterior.max() else { return }
        for index in logPosterior.indices {
            logPosterior[index] -= maximum
        }
    }
}
