import Foundation
import PersistenceKit

/// 小型计算机自适应测评。
///
/// 使用固定题库、2PL IRT 信息量选题和网格化贝叶斯后验估计：
/// - 自评等级只作为宽松先验，不直接决定结果；
/// - 每答一题重新估计能力并选择当前信息量最高的未作答题；
/// - 达到置信度或最多 12 题时停止，避免把短测包装成精确考试分数。
public struct AdaptivePlacementEngine: Sendable {
    public static let minimumQuestionCount = 8
    public static let maximumQuestionCount = 12
    public static let stoppingStandardError = 0.5

    private static let thetaGrid: [Double] = stride(
        from: -3.0,
        through: 3.0,
        by: 0.1
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

    public var shouldStop: Bool {
        responses.count >= Self.maximumQuestionCount
            || (
                responses.count >= Self.minimumQuestionCount
                    && standardError <= Self.stoppingStandardError
            )
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

        return questions
            .filter { !answeredIDs.contains($0.id) }
            .max { lhs, rhs in
                selectionScore(
                    lhs,
                    skillCounts: skillCounts,
                    minimumSkillCount: minimumSkillCount,
                    previousSkill: previousSkill
                ) < selectionScore(
                    rhs,
                    skillCounts: skillCounts,
                    minimumSkillCount: minimumSkillCount,
                    previousSkill: previousSkill
                )
            }
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
                wasCorrect: wasCorrect,
                difficulty: question.difficulty
            )
        )
    }

    public func result() -> PlacementResult {
        let mean = ability
        let error = standardError
        let score = Self.score(for: mean)
        let lowerScore = Self.score(for: mean - error)
        let upperScore = Self.score(for: mean + error)
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
            score: score,
            scoreRange: min(lowerScore, upperScore)...max(lowerScore, upperScore),
            difficultyLevel: Self.difficultyLevel(for: mean),
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
        previousSkill: PlacementSkill?
    ) -> Double {
        let information = Self.information(
            theta: ability,
            question: question
        )
        let needsSkillCoverage = skillCounts[question.skill, default: 0] == minimumSkillCount
        let coverageBoost = needsSkillCoverage ? 1.18 : 1
        let repetitionPenalty = previousSkill == question.skill ? 0.86 : 1
        return information * coverageBoost * repetitionPenalty
    }

    private static func probabilityCorrect(
        theta: Double,
        question: PlacementQuestion
    ) -> Double {
        1 / (1 + exp(-question.discrimination * (theta - question.difficulty)))
    }

    private static func information(
        theta: Double,
        question: PlacementQuestion
    ) -> Double {
        let probability = probabilityCorrect(theta: theta, question: question)
        return pow(question.discrimination, 2) * probability * (1 - probability)
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

    private mutating func normalizeLogPosterior() {
        guard let maximum = logPosterior.max() else { return }
        logPosterior = logPosterior.map { $0 - maximum }
    }
}
