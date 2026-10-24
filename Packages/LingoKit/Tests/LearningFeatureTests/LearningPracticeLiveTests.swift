import BackendKit
import Foundation
@testable import LearningFeature
import Testing

private func formalAttempt() throws -> LearningAttempt {
    let options = (0..<7).map { ["id": "server-\($0)", "text": "\(Character(UnicodeScalar(65 + $0)!)). Sentence \($0)."] }
    let questions: [[String: Any]] = (1...5).map {
        ["id": "gap\($0)", "type": "choice", "goalId": "original.shared_insertion", "instruction": "Choose five sentences.",
         "prompt": "Gap \($0)", "hint": "Read the passage.", "material": "A complete passage\n\nIntro.\n\n" + (1...5).map { "Context ____\($0)____ continues." }.joined(separator: "\n\n"), "options": options]
    }
    let value: [String: Any] = ["id": UUID().uuidString, "characterId": UUID().uuidString, "level": "senior1", "revision": 1,
        "startedAt": "2026-10-24T00:00:00Z", "correctQuestionIds": [],
        "round": ["id": UUID().uuidString, "ordinal": 0, "questionIds": questions.map { $0["id"]! }, "completed": false, "answers": []],
        "unit": ["id": "test.formal-insertion", "version": 1, "schemaVersion": 1, "roleKey": "companion", "level": "senior1", "title": "Whole passage", "summary": "Whole task", "scene": "Practice", "estimatedMinutes": 10, "goalIds": ["original.shared_insertion"], "beats": [],
            "originalGroup": ["id": "test", "family": "shared_insertion", "label": "七选五"], "questions": questions]]
    return try JSONDecoder().decode(LearningAttempt.self, from: JSONSerialization.data(withJSONObject: value))
}

private actor FormalPracticeService: LearningServing {
    var attempt: LearningAttempt
    var commands: [LearningAnswerCommand] = []
    var receipts: [UUID: LearningAnswerReceipt] = [:]
    var loseResponse = false
    var finishCalls = 0
    init(_ attempt: LearningAttempt) { self.attempt = attempt }
    func loseNextResponse() { loseResponse = true }
    func learningAttempt(_ id: UUID) async throws -> LearningAttempt { attempt }
    func answerLearning(_ id: UUID, command: LearningAnswerCommand) async throws -> LearningAnswerReceipt {
        commands.append(command)
        if let replay = receipts[command.requestId] { return replay }
        guard command.expectedRevision == attempt.revision, command.roundId == attempt.round.id else { throw BackendClientError.invalidResponse }
        var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(attempt)) as! [String: Any]
        var round = value["round"] as! [String: Any]; var answers = round["answers"] as! [[String: Any]]
        let grade: [String: Any] = ["outcome": "correct", "explanation": "Only the server supplied this explanation.", "solution": ["kind": "choice", "optionId": command.answer.optionId!]]
        answers.append(["questionId": command.questionId, "answer": try JSONSerialization.jsonObject(with: JSONEncoder().encode(command.answer)), "result": grade])
        round["answers"] = answers; value["round"] = round; value["revision"] = attempt.revision + 1
        value["correctQuestionIds"] = answers.map { $0["questionId"]! }
        attempt = try JSONDecoder().decode(LearningAttempt.self, from: JSONSerialization.data(withJSONObject: value))
        let receipt = try JSONDecoder().decode(LearningAnswerReceipt.self, from: JSONSerialization.data(withJSONObject: ["attempt": value, "result": grade, "awardedPoints": 1, "progress": []]))
        receipts[command.requestId] = receipt
        if loseResponse { loseResponse = false; throw BackendClientError.transport("Lost response after commit") }
        return receipt
    }
    func finishLearning(_ attempt: LearningAttempt, requestID: UUID, skipRemaining: Bool) async throws -> LearningAttempt {
        finishCalls += 1; return self.attempt
    }
    func learningCharacter(_ characterID: UUID) async throws -> BackendLearningCharacter { throw BackendClientError.invalidResponse }
    func learningJourney() async throws -> LearningJourney { throw BackendClientError.invalidResponse }
    func learningHistory(_ characterID: UUID, cursor: String?) async throws -> LearningHistory { throw BackendClientError.invalidResponse }
    func startLearning(_ characterID: UUID, requestID: UUID) async throws -> LearningStart { throw BackendClientError.invalidResponse }
    func retryLearning(_ attempt: LearningAttempt, requestID: UUID) async throws -> LearningAttempt { throw BackendClientError.invalidResponse }
}

@Suite("Formal whole-passage practice") @MainActor
struct LearningPracticeLiveTests {
    @Test("The actual published fifteen-question public fixture projects to five insertion gaps and ten grammar gaps")
    func publishedPublicProjection() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appending(path: "Tests/LingoTripUITests/Fixtures/learning-senior1-formal-practice.json"))
        let unit = try JSONDecoder().decode(LearningUnit.self, from: data)
        let projection = try #require(LearningPracticeProjection(unit: unit))
        #expect(projection.task.sections.map(\.kind) == [.insertion, .grammar])
        #expect(projection.task.sections.map { $0.questions.count } == [5, 10])
        #expect(projection.task.sections.flatMap(\.questions).map(\.id) == unit.questions.map(\.id))
        #expect(projection.task.sections[0].questions.allSatisfy { $0.options.count == 7 })
        #expect(projection.task.sections[0].questions[0].options[0].text.hasPrefix("Make a short list of essentials"))
        #expect(projection.task.sections[1].questions.allSatisfy { $0.options.isEmpty })
        #expect(projection.task.sections.flatMap(\.questions).allSatisfy { $0.correctOption == nil && $0.acceptedAnswers.isEmpty })
    }

    @Test("A retry round keeps the complete article but submits only the required gap")
    func retryWholeContext() async throws {
        let original = try formalAttempt()
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        var round = object["round"] as! [String: Any]
        round["ordinal"] = 1; round["questionIds"] = ["gap3"]; object["round"] = round
        object["firstCompletedAt"] = "2026-10-24T01:00:00Z"
        let attempt = try JSONDecoder().decode(LearningAttempt.self, from: JSONSerialization.data(withJSONObject: object))
        let service = FormalPracticeService(attempt)
        let model = try #require(LearningPracticeModel(attempt: attempt, service: service, defaults: UserDefaults(suiteName: UUID().uuidString)!))
        #expect(model.section.questions.count == 5)
        #expect(model.question.id == "gap3")
        #expect(model.questionCount == 1)
        model.setAnswer("C"); await model.submitSection()
        #expect(await service.commands.map(\.questionId) == ["gap3"])
        #expect(model.correctCount == 1)
        await model.finishReview()
        #expect(model.page == .summary)
        #expect(await service.finishCalls == 0)
    }

    @Test("Five gaps share one bank and submit public server option IDs only after the whole passage")
    func realSubmissionBoundary() async throws {
        let attempt = try formalAttempt(); let service = FormalPracticeService(attempt)
        let model = try #require(LearningPracticeModel(attempt: attempt, service: service,
            defaults: UserDefaults(suiteName: UUID().uuidString)!))
        model.start()
        #expect(model.isProduction)
        #expect(model.section.questions.count == 5)
        #expect(model.section.questions.allSatisfy { $0.correctOption == nil && $0.explanation.isEmpty })
        for index in 0..<4 { model.selectQuestion(index); model.setAnswer(String(UnicodeScalar(65 + index)!)) }
        await model.submitSection()
        #expect(await service.commands.isEmpty)
        model.selectQuestion(4); model.setAnswer("E")
        #expect(model.result(for: model.question) == nil)
        await model.submitSection()
        let commands = await service.commands
        #expect(commands.map(\.answer.optionId) == ["server-0", "server-1", "server-2", "server-3", "server-4"])
        #expect(commands.map(\.expectedRevision) == [1, 2, 3, 4, 5])
        #expect(model.draft.isReviewing)
        #expect(model.correctCount == 5)
        #expect(model.explanation(for: model.question) == "Only the server supplied this explanation.")
        await model.finishReview()
        #expect(await service.finishCalls == 1)
        #expect(model.page == .summary)
    }

    @Test("An uncertain committed answer survives relaunch and reuses the exact request without revealing partial feedback")
    func lostResponseAndResume() async throws {
        let attempt = try formalAttempt(); let service = FormalPracticeService(attempt)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = try #require(LearningPracticeModel(attempt: attempt, service: service, defaults: defaults))
        model.start()
        for index in 0..<5 { model.selectQuestion(index); model.setAnswer(String(UnicodeScalar(65 + index)!)) }
        await service.loseNextResponse(); await model.submitSection()
        #expect(model.hasUnconfirmedAnswer)
        #expect(!model.draft.isReviewing)
        #expect(model.result(for: model.section.questions[0]) == nil)
        let reloaded = try #require(LearningPracticeModel(attempt: attempt, service: service, defaults: defaults))
        #expect(reloaded.hasUnconfirmedAnswer)
        await reloaded.submitSection()
        let commands = await service.commands
        #expect(commands[0].requestId == commands[1].requestId)
        #expect(commands[0].expectedRevision == commands[1].expectedRevision)
        #expect(await service.receipts.count == 5)
        #expect(reloaded.correctCount == 5)
        #expect(!reloaded.hasUnconfirmedAnswer)
    }
}
