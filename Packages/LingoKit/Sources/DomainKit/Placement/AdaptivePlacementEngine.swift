import Foundation
import PersistenceKit

/// 面向学习难度校准的小型计算机自适应测评。
///
/// 使用固定题库、带猜测修正的 3PL IRT 和网格化贝叶斯后验估计：
/// - 自评等级只作为宽松先验，不直接决定结果；
/// - 每项能力至少取样三次，并优先切换任务形态；
/// - 从信息量相近的优质候选中随机抽题，且限制相邻题难度跳幅；
/// - 只有精度、等级稳定度和答案一致性同时足够时才提前停止；
/// - 第 14 题后动态判断，最多 20 题，避免把学习校准做成长考试。
public struct AdaptivePlacementEngine: Sendable {
    public static let minimumQuestionCount = 14
    public static let maximumQuestionCount = 20
    public static let minimumQuestionsPerSkill = 3
    public static let maximumDifficultyStep = 0.85
    public static let stoppingStandardError = 0.54
    public static let stoppingLevelConfidence = 0.58

    private static let earlyStoppingStandardError = 0.44
    private static let earlyStoppingLevelConfidence = 0.72
    private static let relaxedStoppingQuestionCount = 17

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
        let priorMean = Self.priorMean(for: priorLevel)
        let priorStandardDeviation = 1.35
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

    /// 后验落在当前推荐等级或相邻一级的概率质量。
    ///
    /// 14–20 道短测不足以把十六个窄等级当成正式考试分数精确切开，
    /// 因而以“相邻一级内稳定”控制停测，并同时给出 90% 可信区间。
    public var levelConfidence: Double {
        let selectedLevel = Self.difficultyLevel(for: ability)
        let selectedOrdinal = selectedLevel.placementOrdinal
        return zip(Self.thetaGrid, normalizedPosterior)
            .filter {
                abs(Self.difficultyLevel(for: $0.0).placementOrdinal - selectedOrdinal) <= 1
            }
            .reduce(0) { $0 + $1.1 }
    }

    public var measurementProgress: Double {
        if shouldStop { return 1 }
        let countProgress = min(
            1,
            Double(responses.count) / Double(Self.minimumQuestionCount)
        )
        let precisionProgress = min(1, Self.stoppingStandardError / max(standardError, 0.01))
        let confidenceProgress = min(
            1,
            levelConfidence / Self.stoppingLevelConfidence
        )
        return min(
            0.96,
            countProgress * 0.55 + precisionProgress * 0.25 + confidenceProgress * 0.2
        )
    }

    public var shouldStop: Bool {
        if responses.count >= Self.maximumQuestionCount {
            return true
        }
        guard responses.count >= Self.minimumQuestionCount,
              hasRequiredSkillCoverage,
              inversionCount <= 2
        else {
            return false
        }

        if responses.count < Self.relaxedStoppingQuestionCount {
            return standardError <= Self.earlyStoppingStandardError
                && levelConfidence >= Self.earlyStoppingLevelConfidence
        }
        return standardError <= Self.stoppingStandardError
            && levelConfidence >= Self.stoppingLevelConfidence
    }

    public func nextQuestion(in questions: [PlacementQuestion]) -> PlacementQuestion? {
        guard !shouldStop else { return nil }
        let answeredIDs = Set(responses.map(\.questionID))
        let skillCounts = Dictionary(grouping: responses, by: \.skill)
            .mapValues(\.count)
        let minimumSkillCount = PlacementSkill.allCases
            .map { skillCounts[$0, default: 0] }
            .min() ?? 0
        let previousSkill = responses.last?.skill
        let previousFormat = responses.last?.format
        let previousDifficulty = responses.last?.difficulty

        var candidates = questions.filter { !answeredIDs.contains($0.id) }

        // 前十二题严格轮转到当前取样最少的能力，保证每项至少有三次证据。
        if minimumSkillCount < Self.minimumQuestionsPerSkill {
            let leastSampledSkills = Set(
                PlacementSkill.allCases.filter {
                    skillCounts[$0, default: 0] == minimumSkillCount
                }
            )
            let balanced = candidates.filter { leastSampledSkills.contains($0.skill) }
            if !balanced.isEmpty {
                candidates = balanced
            }
        }

        // 能力覆盖之后优先限制难度跳幅，避免为了切换题型突然跨越多个等级。
        if let previousDifficulty {
            let smooth = candidates.filter {
                abs($0.difficulty - previousDifficulty) <= Self.maximumDifficultyStep
            }
            if !smooth.isEmpty {
                candidates = smooth
            }
        }

        // 在难度平滑的候选中优先换任务形态，避免证据依赖单一答题方式。
        let usedFormatsBySkill = Dictionary(grouping: responses, by: \.skill)
            .mapValues { Set($0.map(\.format)) }
        let formatDiverse = candidates.filter {
            !(usedFormatsBySkill[$0.skill] ?? []).contains($0.format)
        }
        if !formatDiverse.isEmpty {
            candidates = formatDiverse
        }

        let posteriorProbabilities = normalizedPosterior
        let currentAbility = zip(Self.thetaGrid, posteriorProbabilities)
            .reduce(0) { $0 + $1.0 * $1.1 }
        let targetAbility = responses.isEmpty ? currentAbility - 0.3 : currentAbility
        let ranked = candidates.map { candidate in
            (
                question: candidate,
                score: selectionScore(
                    candidate,
                    skillCounts: skillCounts,
                    minimumSkillCount: minimumSkillCount,
                    previousSkill: previousSkill,
                    previousFormat: previousFormat,
                    targetAbility: targetAbility,
                    posteriorProbabilities: posteriorProbabilities
                )
            )
        }.sorted {
            if abs($0.score - $1.score) < 1e-12 {
                return $0.question.id < $1.question.id
            }
            return $0.score > $1.score
        }
        guard let bestScore = ranked.first?.score else { return nil }

        // 在信息量接近最佳的候选中抽取，既保持测量效率，也避免每次见到同一套题。
        let competitive = Array(
            ranked.prefix(6).filter { $0.score >= bestScore * 0.9 }
        )
        let pool = competitive.isEmpty ? Array(ranked.prefix(1)) : competitive
        return pool[stableChoiceIndex(upperBound: pool.count)].question
    }

    public mutating func record(
        question: PlacementQuestion,
        selectedIndex: Int
    ) {
        guard !responses.contains(where: { $0.questionID == question.id }) else { return }
        let wasCorrect = selectedIndex == question.correctIndex
        for index in Self.thetaGrid.indices {
            let probability = Self.probabilityCorrect(
                theta: Self.thetaGrid[index],
                question: question
            )
            let likelihood = wasCorrect ? probability : (1 - probability)
            logPosterior[index] += log(max(likelihood, 1e-12))
        }
        normalizeLogPosterior()
        responses.append(
            PlacementResponse(
                questionID: question.id,
                skill: question.skill,
                format: question.format,
                wasCorrect: wasCorrect,
                difficulty: question.difficulty
            )
        )
    }

    public func result() -> PlacementResult {
        let mean = ability
        let error = standardError
        let score = Self.score(for: mean)
        let credibleRange = posteriorCredibleRange()
        let lowerScore = Self.score(for: credibleRange.lowerBound)
        let upperScore = Self.score(for: credibleRange.upperBound)
        let skillResults = PlacementSkill.allCases.map { skill in
            let matching = responses.filter { $0.skill == skill }
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
            answeredCount: responses.count,
            skillResults: skillResults
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

    private func selectionScore(
        _ question: PlacementQuestion,
        skillCounts: [PlacementSkill: Int],
        minimumSkillCount: Int,
        previousSkill: PlacementSkill?,
        previousFormat: PlacementQuestionFormat?,
        targetAbility: Double,
        posteriorProbabilities: [Double]
    ) -> Double {
        let information = zip(Self.thetaGrid, posteriorProbabilities)
            .reduce(0) { partial, pair in
                partial + pair.1 * Self.information(theta: pair.0, question: question)
            }
        let needsSkillCoverage = skillCounts[question.skill, default: 0] == minimumSkillCount
        let coverageBoost = needsSkillCoverage ? 1.12 : 1
        let skillRepetitionPenalty = previousSkill == question.skill ? 0.9 : 1
        let formatRepetitionPenalty = previousFormat == question.format ? 0.88 : 1
        let distancePenalty = exp(-0.22 * abs(question.difficulty - targetAbility))
        return information
            * coverageBoost
            * skillRepetitionPenalty
            * formatRepetitionPenalty
            * distancePenalty
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

    private static func information(
        theta: Double,
        question: PlacementQuestion
    ) -> Double {
        let probability = probabilityCorrect(theta: theta, question: question)
        let guessing = 1 / Double(question.options.count)
        let adjustedProbability = (probability - guessing) / (1 - guessing)
        return pow(question.discrimination, 2)
            * (1 - probability)
            / max(probability, 1e-12)
            * pow(adjustedProbability, 2)
    }

    private static func priorMean(for level: DifficultyLevel) -> Double {
        switch level {
        case .kindergarten: -2.9
        case .primary1: -2.6
        case .primary2: -2.3
        case .primary3: -2
        case .primary4: -1.7
        case .primary5: -1.4
        case .primary6: -1.1
        case .junior1: -0.78
        case .junior2: -0.43
        case .junior3: -0.08
        case .senior1: 0.28
        case .senior2: 0.63
        case .senior3: 0.98
        case .undergraduate: 1.35
        case .postgraduate: 1.8
        case .advanced: 2.35
        }
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

    private var hasRequiredSkillCoverage: Bool {
        let counts = Dictionary(grouping: responses, by: \.skill).mapValues(\.count)
        return PlacementSkill.allCases.allSatisfy {
            counts[$0, default: 0] >= Self.minimumQuestionsPerSkill
        }
    }

    /// 同一能力中“较易题错、明显更难题对”的成对倒置数。
    /// 少量倒置很常见；多次出现时继续取样，避免幸运猜测触发提前停止。
    private var inversionCount: Int {
        Dictionary(grouping: responses, by: \.skill).values.reduce(0) { total, items in
            total + items.indices.reduce(0) { skillTotal, lhsIndex in
                skillTotal + items.indices.dropFirst(lhsIndex + 1).reduce(0) { pairTotal, rhsIndex in
                    let lhs = items[lhsIndex]
                    let rhs = items[rhsIndex]
                    let easier = lhs.difficulty <= rhs.difficulty ? lhs : rhs
                    let harder = lhs.difficulty <= rhs.difficulty ? rhs : lhs
                    let isInversion = harder.difficulty - easier.difficulty >= 0.45
                        && !easier.wasCorrect
                        && harder.wasCorrect
                    return pairTotal + (isInversion ? 1 : 0)
                }
            }
        }
    }

    /// 90% 后验可信区间，比“均值 ± 1 标准误”更诚实地表达短测不确定性。
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
