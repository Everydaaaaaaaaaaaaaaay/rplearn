import Foundation
import Testing
@testable import DomainKit
import PersistenceKit

@Suite("自适应英语水平测评")
struct AdaptivePlacementEngineTests {
    @Test("随包题库结构有效、覆盖三种能力且题号唯一")
    func bundledQuestionBankIsValid() throws {
        let url = try #require(
            Bundle.main.url(forResource: "placement_questions", withExtension: "json")
        )
        let questions = try PlacementQuestionBank.load(from: url)

        #expect(questions.count == 36)
        #expect(Set(questions.map(\.id)).count == questions.count)
        for skill in PlacementSkill.allCases {
            #expect(questions.filter { $0.skill == skill }.count == 12)
        }
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

    @Test("自适应选题不重复，并会围绕当前能力兼顾能力覆盖")
    func selectionDoesNotRepeatAndBalancesSkills() throws {
        let questions = try bundledQuestions()
        var engine = AdaptivePlacementEngine(priorLevel: .junior3)
        var selectedIDs = Set<String>()

        for _ in 0..<6 {
            let question = try #require(engine.nextQuestion(in: questions))
            #expect(selectedIDs.insert(question.id).inserted)
            engine.record(question: question, selectedIndex: question.correctIndex)
        }

        #expect(Set(engine.responses.map(\.skill)).count == PlacementSkill.allCases.count)
    }

    @Test("测评达到置信度或十二题上限后停止")
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

    @Test(
        "能力值映射到稳定的七档代表等级",
        arguments: [
            (-2.0, DifficultyLevel.primary3),
            (-1.4, DifficultyLevel.primary6),
            (-0.6, DifficultyLevel.junior3),
            (0.2, DifficultyLevel.senior2),
            (0.9, DifficultyLevel.undergraduate),
            (1.5, DifficultyLevel.postgraduate),
            (2.2, DifficultyLevel.advanced),
        ]
    )
    func resultLevelMapping(ability: Double, expected: DifficultyLevel) {
        #expect(AdaptivePlacementEngine.difficultyLevel(for: ability) == expected)
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
            prompt: "Sample?",
            options: ["A", "B", "C", "D"],
            correctIndex: 0,
            difficulty: difficulty,
            discrimination: 1.3,
            explanationZh: "样题"
        )
    }
}
