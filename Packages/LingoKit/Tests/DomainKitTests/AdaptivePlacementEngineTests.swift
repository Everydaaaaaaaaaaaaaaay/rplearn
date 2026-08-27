import Foundation
import Testing
@testable import DomainKit
import PersistenceKit

@Suite("自适应英语水平测评")
struct AdaptivePlacementEngineTests {
    @Test("随包题库结构有效、覆盖四种能力与多种题型且题号唯一")
    func bundledQuestionBankIsValid() throws {
        let url = try #require(
            Bundle.main.url(forResource: "placement_questions", withExtension: "json")
        )
        let questions = try PlacementQuestionBank.load(from: url)

        #expect(questions.count == 96)
        #expect(Set(questions.map(\.id)).count == questions.count)
        for skill in PlacementSkill.allCases {
            #expect(questions.filter { $0.skill == skill }.count == 24)
            #expect(Set(questions.filter { $0.skill == skill }.map(\.format)).count >= 2)
        }
        #expect(
            questions.filter { $0.skill == .listening }.allSatisfy {
                $0.audioText?.isEmpty == false && $0.audioLanguage?.hasPrefix("en-") == true
            }
        )
    }

    @Test("答对会提高能力估计，答错会降低能力估计")
    func responseDirectionChangesAbility() {
        let question = sampleQuestion(difficulty: 0)
        var correctEngine = AdaptivePlacementEngine(priorLevel: .junior3)
        var incorrectEngine = correctEngine
        let prior = correctEngine.ability

        correctEngine.record(question: question, selectedIndex: question.correctIndex)
        incorrectEngine.record(question: question, selectedIndex: 1)

        #expect(correctEngine.ability > prior)
        #expect(incorrectEngine.ability < prior)
        #expect(correctEngine.ability > incorrectEngine.ability)
    }

    @Test("前十二题覆盖四种能力，完整短测不重复且难度变化平滑")
    func selectionDoesNotRepeatAndBalancesSkills() throws {
        let questions = try bundledQuestions()
        var engine = AdaptivePlacementEngine(priorLevel: .junior3)
        var selectedIDs = Set<String>()
        var selectedQuestions: [PlacementQuestion] = []

        let requiredCoverageCount = AdaptivePlacementEngine.minimumQuestionsPerSkill
            * PlacementSkill.allCases.count
        for _ in 0..<AdaptivePlacementEngine.minimumQuestionCount {
            let question = try #require(engine.nextQuestion(in: questions))
            #expect(selectedIDs.insert(question.id).inserted)
            selectedQuestions.append(question)
            let selectedIndex = selectedQuestions.count.isMultiple(of: 2)
                ? question.correctIndex
                : (question.correctIndex + 1) % question.options.count
            engine.record(question: question, selectedIndex: selectedIndex)
        }

        #expect(Set(engine.responses.map(\.skill)).count == PlacementSkill.allCases.count)
        for skill in PlacementSkill.allCases {
            let matching = engine.responses.prefix(requiredCoverageCount).filter { $0.skill == skill }
            #expect(matching.count == AdaptivePlacementEngine.minimumQuestionsPerSkill)
            #expect(Set(matching.map(\.format)).count >= 2)
        }
        for pair in zip(selectedQuestions, selectedQuestions.dropFirst()) {
            #expect(
                abs(pair.1.difficulty - pair.0.difficulty)
                    <= AdaptivePlacementEngine.maximumDifficultyStep + 0.001
            )
        }
    }

    @Test("测评在十四至二十题之间按稳定度停止")
    func stoppingRuleIsBounded() throws {
        let questions = try bundledQuestions()
        var engine = AdaptivePlacementEngine(priorLevel: .senior2)

        while let question = engine.nextQuestion(in: questions) {
            let selectedIndex = engine.responses.count.isMultiple(of: 2)
                ? question.correctIndex
                : (question.correctIndex + 1) % question.options.count
            engine.record(question: question, selectedIndex: selectedIndex)
        }

        #expect(engine.responses.count >= AdaptivePlacementEngine.minimumQuestionCount)
        #expect(engine.responses.count <= AdaptivePlacementEngine.maximumQuestionCount)
        #expect(engine.shouldStop)
        #expect(engine.result().answeredCount == engine.responses.count)
    }

    @Test("持续答对和持续答错会得到显著不同的校准结果")
    func strongAndEmergingLearnersSeparate() throws {
        let questions = try bundledQuestions()
        var strong = AdaptivePlacementEngine(priorLevel: .junior3)
        var emerging = AdaptivePlacementEngine(priorLevel: .junior3)

        while let question = strong.nextQuestion(in: questions) {
            strong.record(question: question, selectedIndex: question.correctIndex)
        }
        while let question = emerging.nextQuestion(in: questions) {
            emerging.record(
                question: question,
                selectedIndex: (question.correctIndex + 1) % question.options.count
            )
        }

        #expect(strong.ability > 1)
        #expect(emerging.ability < -1.5)
        #expect(strong.result().score - emerging.result().score >= 40)
    }

    @Test("短测给出包含中心分数的九成可信区间与等级稳定度")
    func resultIncludesHonestUncertainty() throws {
        let questions = try bundledQuestions()
        var engine = AdaptivePlacementEngine(priorLevel: .senior2)

        while let question = engine.nextQuestion(in: questions) {
            let selectedIndex = engine.responses.count % 3 == 0
                ? (question.correctIndex + 1) % question.options.count
                : question.correctIndex
            engine.record(question: question, selectedIndex: selectedIndex)
        }

        let result = engine.result()
        #expect(result.scoreRange.contains(result.score))
        #expect((0...1).contains(result.levelConfidence))
        #expect(result.referenceLevel == AdaptivePlacementEngine.referenceLevel(for: result.ability))
        #expect(result.skillResults.allSatisfy { $0.total >= 3 })
    }

    @Test("不同真实能力的模拟作答得到单调且相互分离的估计")
    func simulatedAbilitiesRemainOrdered() throws {
        let questions = try bundledQuestions()
        let trueAbilities = [-2.85, -2.3, -1.7, -1.1, -0.45, 0.25, 0.95, 1.65, 2.4]
        let simulations = trueAbilities.enumerated().map { index, trueAbility in
            var engine = AdaptivePlacementEngine(
                priorLevel: .senior2,
                selectionSeed: UInt64(index + 100)
            )
            while let question = engine.nextQuestion(in: questions) {
                let guessing = 1 / Double(question.options.count)
                let logistic = 1 / (
                    1 + exp(-question.discrimination * (trueAbility - question.difficulty))
                )
                let probability = guessing + (1 - guessing) * logistic
                let selectedIndex = probability >= 0.625
                    ? question.correctIndex
                    : (question.correctIndex + 1) % question.options.count
                engine.record(question: question, selectedIndex: selectedIndex)
            }
            return (
                ability: engine.ability,
                count: engine.responses.count,
                confidence: engine.levelConfidence
            )
        }
        let estimates = simulations.map(\.ability)

        for pair in zip(estimates, estimates.dropFirst()) {
            #expect(pair.0 < pair.1)
        }
        #expect((estimates.last ?? 0) - (estimates.first ?? 0) >= 3.5)
        #expect(
            simulations.allSatisfy { $0.count >= AdaptivePlacementEngine.minimumQuestionCount },
            "任何作答路径都不能少于 14 题：\(simulations)"
        )
        #expect(simulations.allSatisfy { $0.count <= AdaptivePlacementEngine.maximumQuestionCount })
        #expect(
            simulations.contains { $0.count < AdaptivePlacementEngine.maximumQuestionCount },
            "稳定作答应能在 20 题前结束：\(simulations)"
        )
        #expect(Set(simulations.map(\.count)).count >= 2, "题量应随测量不确定性动态变化")
    }

    @Test(
        "能力值映射到幼儿启蒙、各学年、四六级和高阶档",
        arguments: [
            (-3.0, DifficultyLevel.kindergarten),
            (-2.6, DifficultyLevel.primary1),
            (-2.3, DifficultyLevel.primary2),
            (-2.0, DifficultyLevel.primary3),
            (-1.7, DifficultyLevel.primary4),
            (-1.4, DifficultyLevel.primary5),
            (-1.1, DifficultyLevel.primary6),
            (-0.75, DifficultyLevel.junior1),
            (-0.4, DifficultyLevel.junior2),
            (0.0, DifficultyLevel.junior3),
            (0.3, DifficultyLevel.senior1),
            (0.65, DifficultyLevel.senior2),
            (1.0, DifficultyLevel.senior3),
            (1.35, DifficultyLevel.undergraduate),
            (1.8, DifficultyLevel.postgraduate),
            (2.3, DifficultyLevel.advanced),
        ]
    )
    func resultLevelMapping(ability: Double, expected: DifficultyLevel) {
        #expect(AdaptivePlacementEngine.difficultyLevel(for: ability) == expected)
    }

    @Test("同一随机种子保持选题稳定，不同种子会从优质候选中抽到不同题")
    func seededSelectionIsStableButVaried() throws {
        let questions = try bundledQuestions()
        var first = AdaptivePlacementEngine(priorLevel: .junior3, selectionSeed: 42)
        var second = AdaptivePlacementEngine(priorLevel: .junior3, selectionSeed: 42)
        var alternateSequences = Set<[String]>()

        for _ in 0..<8 {
            let firstQuestion = try #require(first.nextQuestion(in: questions))
            let secondQuestion = try #require(second.nextQuestion(in: questions))
            #expect(firstQuestion.id == secondQuestion.id)
            first.record(question: firstQuestion, selectedIndex: firstQuestion.correctIndex)
            second.record(question: secondQuestion, selectedIndex: secondQuestion.correctIndex)
        }

        for seed in 1...8 {
            var engine = AdaptivePlacementEngine(
                priorLevel: .junior3,
                selectionSeed: UInt64(seed)
            )
            var ids: [String] = []
            for _ in 0..<4 {
                let question = try #require(engine.nextQuestion(in: questions))
                ids.append(question.id)
                engine.record(question: question, selectedIndex: question.correctIndex)
            }
            alternateSequences.insert(ids)
        }
        #expect(alternateSequences.count >= 3)
    }

    private func bundledQuestions() throws -> [PlacementQuestion] {
        let url = try #require(
            Bundle.main.url(forResource: "placement_questions", withExtension: "json")
        )
        return try PlacementQuestionBank.load(from: url)
    }

    private func sampleQuestion(difficulty: Double) -> PlacementQuestion {
        PlacementQuestion(
            id: "sample",
            skill: .grammar,
            format: .grammarForm,
            prompt: "Sample?",
            options: ["A", "B", "C", "D"],
            correctIndex: 0,
            difficulty: difficulty,
            discrimination: 1.3,
            explanationZh: "样题"
        )
    }
}
