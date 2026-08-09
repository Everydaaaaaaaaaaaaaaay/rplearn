import Foundation
import PersistenceKit

/// 面向学习难度校准的小型计算机自适应测评。
///
/// 使用固定题库、带猜测修正的 3PL IRT 和网格化贝叶斯后验估计：
/// - 自评等级只作为宽松先验，不直接决定结果；
/// - 每项能力至少取样两次，并优先切换任务形态；
/// - 以整个后验分布的期望信息量选题，且限制相邻题难度跳幅；
/// - 只有精度、等级稳定度和答案一致性同时足够时才提前停止；
/// - 最多 12 题，避免把学习校准做成长考试。
public struct AdaptivePlacementEngine: Sendable {
    public static let minimumQuestionCount = 8
    public static let maximumQuestionCount = 12
    public static let minimumQuestionsPerSkill = 2
    public static let maximumDifficultyStep = 0.85
    public static let stoppingStandardError = 0.64
    public static let stoppingLevelConfidence = 0.34

    private static let earlyStoppingStandardError = 0.5
    private static let earlyStoppingLevelConfidence = 0.52

    private static let thetaGrid: [Double] = stride(
        from: -3.0,
        through: 3.0,
        by: 0.05
    ).map { $0 }

    private var logPosterior: [Double]
    public private(set) var responses: [PlacementResponse] = []

    public init(priorLevel: DifficultyLevel) {
        let priorMean = Self.priorMean(for: priorLevel)
        let priorStandardDeviation = 1.15
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

    /// 当前推荐等级在后验分布中所占的概率质量。
    public var levelConfidence: Double {
        let selectedLevel = Self.difficultyLevel(for: ability)
        return zip(Self.thetaGrid, normalizedPosterior)
            .filter { Self.difficultyLevel(for: $0.0) == selectedLevel }
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
              inversionCount <= 1
        else {
            return false
        }

        if responses.count < 10 {
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

        // 前八题严格轮转到当前取样最少的能力，保证每项至少有两次证据。
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

        // 同一能力优先换一种任务形态，避免两次证据都依赖同一种答题方式。
        let usedFormatsBySkill = Dictionary(grouping: responses, by: \.skill)
            .mapValues { Set($0.map(\.format)) }
        let formatDiverse = candidates.filter {
            !(usedFormatsBySkill[$0.skill] ?? []).contains($0.format)
        }
        if !formatDiverse.isEmpty {
            candidates = formatDiverse
        }

        // 再从兼顾能力覆盖与题型变化的候选中限制难度跳幅。
        if let previousDifficulty {
            let smooth = candidates.filter {
                abs($0.difficulty - previousDifficulty) <= Self.maximumDifficultyStep
            }
            if !smooth.isEmpty {
                candidates = smooth
            }
        }

        let posteriorProbabilities = normalizedPosterior
        let currentAbility = zip(Self.thetaGrid, posteriorProbabilities)
            .reduce(0) { $0 + $1.0 * $1.1 }
        let targetAbility = responses.isEmpty ? currentAbility - 0.3 : currentAbility
        var best: (question: PlacementQuestion, score: Double)?
        for candidate in candidates {
            let score = selectionScore(
                candidate,
                skillCounts: skillCounts,
                minimumSkillCount: minimumSkillCount,
                previousSkill: previousSkill,
                previousFormat: previousFormat,
                targetAbility: targetAbility,
                posteriorProbabilities: posteriorProbabilities
            )
            if let currentBest = best {
                if score > currentBest.score {
                    best = (candidate, score)
                }
            } else {
                best = (candidate, score)
            }
        }
        return best?.question
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
        case ..<(-1.75): .primary3
        case ..<(-1.0): .primary6
        case ..<(-0.25): .junior3
        case ..<0.55: .senior2
        case ..<1.25: .undergraduate
        case ..<1.9: .postgraduate
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
        Int(round(((min(max(ability, -3), 3) + 3) / 6) * 100))
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
        case .primary1, .primary2, .primary3: -2.15
        case .primary4, .primary5, .primary6: -1.35
        case .junior1, .junior2, .junior3: -0.55
        case .senior1, .senior2, .senior3: 0.3
        case .undergraduate: 0.95
        case .postgraduate: 1.65
        case .advanced: 2.25
        }
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
