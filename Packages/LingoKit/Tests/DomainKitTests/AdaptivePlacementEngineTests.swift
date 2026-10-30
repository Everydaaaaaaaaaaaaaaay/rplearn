import Foundation
import Testing
@testable import DomainKit
import PersistenceKit

@Suite("自适应英语水平测评")
struct AdaptivePlacementEngineTests {
    @Test("每道听力题最多播放两次")
    func listeningPlaybackIsLimited() {
        #expect(PlacementListeningPolicy.maximumPlayCount == 2)
        #expect(PlacementListeningPolicy.canPlay(currentCount: 0))
        #expect(PlacementListeningPolicy.canPlay(currentCount: 1))
        #expect(!PlacementListeningPolicy.canPlay(currentCount: 2))
        #expect(!PlacementListeningPolicy.canPlay(currentCount: 3))
        #expect(!PlacementListeningPolicy.canPlay(currentCount: 4))
        #expect(PlacementListeningPolicy.remainingPlayCount(after: 0) == 2)
        #expect(PlacementListeningPolicy.remainingPlayCount(after: 1) == 1)
        #expect(PlacementListeningPolicy.remainingPlayCount(after: 3) == 0)
    }

    @Test("随包题库结构有效、覆盖四种能力与多种题型且题号唯一")
    func bundledQuestionBankIsValid() throws {
        let url = try #require(
            Bundle.main.url(forResource: "placement_questions", withExtension: "json")
        )
        let questions = try PlacementQuestionBank.load(from: url)
        let listeningQuestions = questions.filter { $0.skill == .listening }
        #expect(listeningQuestions.count == 24)
        #expect(
            listeningQuestions.allSatisfy {
                $0.audioAssetName == $0.id
            }
        )

        #expect(questions.count == 102)
        #expect(Set(questions.map(\.id)).count == questions.count)
        for skill in PlacementSkill.allCases {
            #expect(questions.filter { $0.skill == skill }.count >= 24)
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

    @Test("所有自评水平都从基础题开始", arguments: DifficultyLevel.allCases)
    func easyStart(_ level: DifficultyLevel) throws {
        let engine = AdaptivePlacementEngine(priorLevel: level, selectionSeed: 42)
        let question = try #require(engine.nextQuestion(in: bundledQuestions()))
        #expect(question.difficulty <= -2.75)
        #expect(question.skill != .listening)
    }

    @Test("累计三次错误立即结束，正确答案不会清零错误次数")
    func threeCumulativeMistakes() throws {
        var engine = AdaptivePlacementEngine(priorLevel: .advanced, selectionSeed: 42)
        let questions = try bundledQuestions()
        for correct in [false, true, false, true, false] {
            let question = try #require(engine.nextQuestion(in: questions))
            engine.record(question: question, selectedIndex: correct ? question.correctIndex : (question.correctIndex + 1) % 4)
        }
        #expect(engine.responses.count == 5)
        #expect(engine.mistakeCount == 3)
        #expect(engine.stopReason == .threeMistakes)
        #expect(engine.nextQuestion(in: questions) == nil)
        let count = engine.responses.count
        engine.record(question: questions[0], selectedIndex: 0)
        #expect(engine.responses.count == count)
    }

    @Test("错误、跳过和正确路径均不回退难度；听力最多两题且不在开头", arguments: [true, false])
    func progressivePath(allCorrect: Bool) throws {
        let questions = try bundledQuestions()
        for seed in 0..<24 {
            var engine = AdaptivePlacementEngine(priorLevel: .senior3, selectionSeed: UInt64(seed))
            var sequence: [PlacementQuestion] = []
            while let question = engine.nextQuestion(in: questions) {
                sequence.append(question)
                if allCorrect { engine.record(question: question, selectedIndex: question.correctIndex) }
                else if sequence.count.isMultiple(of: 3) { engine.skip(question: question) }
                else { engine.record(question: question, selectedIndex: (question.correctIndex + 1) % 4) }
            }
            #expect(sequence.count <= 20)
            #expect(Set(sequence.map(\.id)).count == sequence.count)
            #expect(sequence.filter { $0.skill == .listening }.count <= 2)
            #expect(sequence.prefix(7).allSatisfy { $0.skill != .listening })
            for (left, right) in zip(sequence, sequence.dropFirst()) {
                #expect(right.difficulty >= left.difficulty)
                #expect(right.difficulty - left.difficulty <= AdaptivePlacementEngine.maximumDifficultyStep + 0.001)
            }
            if !allCorrect { #expect(engine.mistakeCount == 3) }
        }
    }

    @Test("全错得到较低起点，全对可探测高阶；自评不掩盖三次基础题错误")
    func separatesLearners() throws {
        let questions = try bundledQuestions()
        var strong = AdaptivePlacementEngine(priorLevel: .primary3, selectionSeed: 42)
        var emerging = AdaptivePlacementEngine(priorLevel: .advanced, selectionSeed: 42)
        while let q = strong.nextQuestion(in: questions) { strong.record(question: q, selectedIndex: q.correctIndex) }
        while let q = emerging.nextQuestion(in: questions) { emerging.record(question: q, selectedIndex: (q.correctIndex + 1) % 4) }
        #expect(emerging.responses.count == 3)
        #expect(emerging.result().ability < -2.4)
        #expect(emerging.result().difficultyLevel == .kindergarten)
        #expect((-3.25...3.25).contains(emerging.result().ability))
        #expect(strong.result().ability > 1.5)
        #expect(strong.result().score - emerging.result().score >= 40)
        #expect(emerging.result().levelConfidence < 0.5)
    }

    @Test("跳过不算错误、不更新能力；全跳过不会产生可应用的定级")
    func skipsAreNotWrongOrProficiencyEvidence() throws {
        let questions = try bundledQuestions()
        var engine = AdaptivePlacementEngine(priorLevel: .advanced, selectionSeed: 42)
        let ability = engine.ability
        while let q = engine.nextQuestion(in: questions) { engine.skip(question: q) }
        #expect(engine.mistakeCount == 0)
        #expect(engine.ability == ability)
        #expect(engine.result().answeredCount == 0)
        #expect(!engine.result().hasSufficientEvidence)
        #expect(engine.responses.count <= 20)
        var partial = AdaptivePlacementEngine(priorLevel: .advanced, selectionSeed: 42)
        for _ in 0..<3 {
            let q = try #require(partial.nextQuestion(in: questions))
            partial.record(question: q, selectedIndex: q.correctIndex)
        }
        let highest = try #require(partial.responses.map(\.difficulty).max())
        while let q = partial.nextQuestion(in: questions) { partial.skip(question: q) }
        #expect(partial.result().ability <= highest + 0.35)
        #expect(partial.result().scoreRange.contains(partial.result().score))
    }

    @Test("无效答案和重复提交不增加错误或证据")
    func rejectsInvalidAndDuplicateResponses() throws {
        var engine = AdaptivePlacementEngine(priorLevel: .junior3)
        let q = try #require(engine.nextQuestion(in: bundledQuestions()))
        engine.record(question: q, selectedIndex: -1)
        #expect(engine.responses.isEmpty)
        engine.record(question: q, selectedIndex: q.correctIndex)
        engine.record(question: q, selectedIndex: (q.correctIndex + 1) % 4)
        engine.skip(question: q)
        #expect(engine.responses.count == 1)
        #expect(engine.mistakeCount == 0)
    }

    @Test("选择只更新草稿；确认后才计分且不能空提交")
    func explicitConfirmation() throws {
        var session = PlacementSession(questions: try bundledQuestions(), priorLevel: .junior3, seed: 42)
        confirm(&session, expected: false)
        let q = try #require(session.current?.question)
        session.select(q.correctIndex)
        #expect(session.engine.responses.isEmpty)
        confirm(&session)
        #expect(session.engine.responses.count == 1)
        confirm(&session, expected: false)
        #expect(!session.isComplete)
    }

    @Test("返回保留选项顺序和答案；同答不重复计分，改答移除依赖的后续证据")
    func backAndRevision() throws {
        var session = PlacementSession(questions: try bundledQuestions(), priorLevel: .junior3, seed: 42)
        let first = try #require(session.current)
        session.select(first.question.correctIndex); confirm(&session)
        let second = try #require(session.current)
        session.select(second.question.correctIndex); confirm(&session)
        session.goBack()
        #expect(session.current?.optionOrder == second.optionOrder)
        #expect(session.current?.selectedIndex == second.question.correctIndex)
        confirm(&session)
        #expect(session.engine.responses.count == 2)
        session.goBack(); session.goBack()
        #expect(session.current?.optionOrder == first.optionOrder)
        session.select((first.question.correctIndex + 1) % 4)
        confirm(&session)
        #expect(session.engine.responses.count == 1)
        #expect(session.engine.mistakeCount == 1)
        #expect(session.current?.selectedIndex == nil)
        #expect(session.entries.count == 2)
    }

    @Test("返回听力题保留播放次数；播放之前可跳过但不能确认答案")
    func listeningNavigation() throws {
        var session = PlacementSession(questions: try bundledQuestions(), priorLevel: .junior3, seed: 42)
        while let entry = session.current, entry.question.skill != .listening, !session.isComplete {
            session.select(entry.question.correctIndex); confirm(&session)
        }
        #expect(session.current?.question.skill == .listening)
        session.select(0); #expect(!session.canConfirm)
        session.recordListeningPlay()
        let entry = try #require(session.current)
        session.select(entry.question.correctIndex); confirm(&session)
        session.goBack()
        #expect(session.current?.question.id == entry.question.id)
        #expect(session.current?.listeningPlayCount == 1)
        session.recordListeningPlay(); session.recordListeningPlay()
        #expect(session.current?.listeningPlayCount == 2)
        session.skip()
        #expect(session.engine.skippedCount == 1)
        #expect(session.engine.mistakeCount == 0)
    }

    @Test("确认第三次错误才结束，选项点击和结束后的操作不重复提交")
    func sessionStopsOnThirdConfirmedMistake() throws {
        var session = PlacementSession(questions: try bundledQuestions(), priorLevel: .advanced, seed: 42)
        for index in 0..<3 {
            let q = try #require(session.current?.question)
            session.select((q.correctIndex + 1) % 4)
            #expect(!session.isComplete)
            confirm(&session)
            #expect(session.isComplete == (index == 2))
        }
        session.skip(); session.goBack()
        confirm(&session, expected: false)
        #expect(session.engine.responses.count == 3)
        #expect(session.engine.result().mistakeCount == 3)
    }

    @Test("修正旧错误后重新计数，不沿用后来题目的作答")
    func correctEarlierMistake() throws {
        var session = PlacementSession(questions: try bundledQuestions(), priorLevel: .junior3, seed: 42)
        let first = try #require(session.current)
        session.select((first.question.correctIndex + 1) % 4); confirm(&session)
        let second = try #require(session.current)
        session.select((second.question.correctIndex + 1) % 4); confirm(&session)
        #expect(session.engine.mistakeCount == 2)
        session.goBack(); session.goBack()
        session.select(first.question.correctIndex); confirm(&session)
        #expect(session.engine.mistakeCount == 0)
        #expect(session.engine.responses.count == 1)
        #expect(!session.isComplete)
        #expect(session.current?.selectedIndex == nil)
    }

    @Test("多种模拟能力下的中位建议随能力递增，且所有路径受题量和错误上限约束")
    func simulatedPopulation() throws {
        let questions = try bundledQuestions()
        let levels = [-2.8, -1.5, 0.0, 1.5, 2.8]
        var medians: [Double] = []
        for ability in levels {
            var estimates: [Double] = []
            for seed in 1...60 {
                var random = UInt64(seed)
                var engine = AdaptivePlacementEngine(priorLevel: .advanced, selectionSeed: UInt64(seed))
                while let q = engine.nextQuestion(in: questions) {
                    random = random &* 6364136223846793005 &+ 1
                    let draw = Double(random >> 11) / Double(UInt64.max >> 11)
                    let probability = 0.25 + 0.75 / (1 + exp(-q.discrimination * (ability - q.difficulty)))
                    engine.record(question: q, selectedIndex: draw < probability ? q.correctIndex : (q.correctIndex + 1) % 4)
                }
                #expect(engine.responses.count <= 20)
                #expect(engine.mistakeCount <= 3)
                estimates.append(engine.result().ability)
            }
            estimates.sort(); medians.append(estimates[estimates.count / 2])
        }
        for (lower, upper) in zip(medians, medians.dropFirst()) { #expect(lower < upper, "\(medians)") }
        #expect(medians.last! - medians.first! > 2.5)
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

    @Test("空题库不能产生题目或可应用的结果")
    func emptyBankIsSafe() {
        var session = PlacementSession(questions: [], priorLevel: .advanced)
        #expect(session.isComplete)
        #expect(session.current == nil)
        confirm(&session, expected: false)
        session.skip(); session.goBack()
        #expect(!session.engine.result().hasSufficientEvidence)
    }

    private func confirm(_ session: inout PlacementSession, expected: Bool = true) {
        let actual = session.confirm()
        #expect(actual == expected)
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
