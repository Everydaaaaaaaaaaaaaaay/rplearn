import BackendKit
import Foundation
@testable import LearningFeature
import Testing

private let attemptID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
private let characterID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
private let roundID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
private func learningAttemptFixture(_ overrides: [String: Any] = [:]) throws -> LearningAttempt {
    var object: [String: Any] = [
        "id": attemptID.uuidString, "characterId": characterID.uuidString, "level": "primary3", "revision": 1,
        "startedAt": "2026-09-26T00:00:00Z", "firstCompletedAt": NSNull(), "correctQuestionIds": [],
        "round": ["id": roundID.uuidString, "ordinal": 0, "questionIds": ["q1", "q2"], "completed": false, "answers": []],
        "unit": ["id": "test.unit", "version": 1, "schemaVersion": 1, "roleKey": "oliver", "level": "primary3", "title": "工程夹具", "summary": "仅验证合同", "scene": "测试环境", "estimatedMinutes": 2, "goalIds": ["test.goal"],
                 "beats": [["id": "opening", "afterQuestion": 0, "speaker": "测试", "text": "Hello.", "translation": "你好。"]],
                 "questions": ["q1", "q2"].map { ["id": $0, "type": "choice", "goalId": "test.goal", "instruction": "选择", "prompt": "工程检查", "hint": "提示", "options": [["id": "a", "text": "A"], ["id": "b", "text": "B"]]] }]
    ]
    for (key, value) in overrides { object[key] = value }
    return try JSONDecoder().decode(LearningAttempt.self, from: JSONSerialization.data(withJSONObject: object))
}
private actor ChallengeService: LearningServing {
    var attempt: LearningAttempt
    var commands: [LearningAnswerCommand] = []
    var failAfterSaving = true
    init() throws { attempt = try learningAttemptFixture() }
    func startLearning(_ characterID: UUID, requestID: UUID) async throws -> LearningStart { throw BackendClientError.invalidResponse }
    func learningCharacter(_ characterID: UUID) async throws -> BackendLearningCharacter { throw BackendClientError.invalidResponse }
    func learningJourney() async throws -> LearningJourney { throw BackendClientError.invalidResponse }
    func learningHistory(_ characterID: UUID, cursor: String?) async throws -> LearningHistory { throw BackendClientError.invalidResponse }
    func learningAttempt(_ id: UUID) async throws -> LearningAttempt { attempt }
    func answerLearning(_ id: UUID, command: LearningAnswerCommand) async throws -> LearningAnswerReceipt {
        commands.append(command)
        let result: [String: Any] = ["outcome": "correct", "explanation": "服务端解析", "solution": ["kind": "choice", "optionId": "a"]]
        let body: [String: Any] = ["id": roundID.uuidString, "ordinal": 0, "questionIds": ["q1", "q2"], "completed": false,
                                  "answers": [["questionId": "q1", "answer": ["kind": "choice", "optionId": "a"], "result": result]]]
        attempt = try learningAttemptFixture(["revision": 2, "round": body, "correctQuestionIds": ["q1"]])
        if failAfterSaving { failAfterSaving = false; throw BackendClientError.transport("响应丢失") }
        let data = try JSONSerialization.data(withJSONObject: ["result": result, "awardedPoints": 1,
            "attempt": JSONSerialization.jsonObject(with: JSONEncoder().encode(attempt)), "progress": []])
        return try JSONDecoder().decode(LearningAnswerReceipt.self, from: data)
    }
    func finishLearning(_ attempt: LearningAttempt, requestID: UUID, skipRemaining: Bool) async throws -> LearningAttempt { throw BackendClientError.invalidResponse }
    func retryLearning(_ attempt: LearningAttempt, requestID: UUID) async throws -> LearningAttempt { throw BackendClientError.invalidResponse }
}

@Suite("单元挑战恢复与交互状态") @MainActor
struct LearningChallengeTests {
    @Test("同步校验失败明确说明阶段，不误报断网或读取未同步的学习状态")
    func synchronizationValidationFailure() async throws {
        let model = CharacterLearningModel(characterID: characterID, service: try ChallengeService(), synchronize: {
            throw BackendClientError.api(code: "INVALID_REQUEST", message: "The request is invalid.", requestID: nil, status: 400)
        })
        await model.load()
        #expect(model.error == "聊天记录同步失败：请求未能通过服务器校验。")
        #expect(model.state == nil)
        #expect(!model.isBusy)
    }
    @Test("取消同步不显示失败提示")
    func synchronizationCancelled() async throws {
        let model = CharacterLearningModel(characterID: characterID, service: try ChallengeService(), synchronize: { throw CancellationError() })
        await model.load()
        #expect(model.error == nil)
        #expect(model.state == nil)
        #expect(!model.isBusy)
    }

    @Test("响应丢失后冻结答案并复用请求标识，反馈来自服务端")
    func retryLostResponse() async throws {
        let service = try ChallengeService()
        let model = LearningChallengeModel(attempt: try learningAttemptFixture(), service: service)
        model.advance(); #expect(model.stage == .story(0))
        model.advance(); #expect(model.stage == .question("q1"))
        model.choice = "a"
        await model.submit()
        #expect(model.hasUnconfirmedAnswer)
        model.advance(); #expect(model.stage == .question("q1"))
        model.choice = "b" // 即使外部写入，重试仍提交冻结的 A。
        await model.submit()
        let commands = await service.commands
        #expect(commands.count == 2)
        #expect(commands[0].requestId == commands[1].requestId)
        #expect(commands[1].answer == .choice("a"))
        #expect(model.feedback?.outcome == .correct)
        #expect(model.attempt.correctQuestionIds == ["q1"])
        model.advance(); #expect(model.stage == .question("q2"))
    }
    @Test("读取已保存答案可恢复丢失的反馈，不再调用作答接口")
    func recoverSaved() async throws {
        let service = try ChallengeService()
        let model = LearningChallengeModel(attempt: try learningAttemptFixture(), service: service)
        model.skipStory(); model.choice = "a"; await model.submit()
        await model.recover()
        #expect(!model.hasUnconfirmedAnswer)
        #expect(model.feedback?.explanation == "服务端解析")
        #expect(await service.commands.count == 1)
        #expect(model.attempt.revision == 2)
    }
    @Test("补答打开时直达未答题，使用挑战冻结的年级")
    func resumeRetry() throws {
        let attempt = try learningAttemptFixture(["firstCompletedAt": "2026-09-26T01:00:00Z", "correctQuestionIds": ["q1"],
            "round": ["id": UUID().uuidString, "ordinal": 1, "questionIds": ["q2"], "completed": false, "answers": []]])
        let model = LearningChallengeModel(attempt: attempt, service: try ChallengeService())
        #expect(model.stage == .question("q2"))
        #expect(model.attempt.level == "primary3")
        #expect(model.attempt.remainingCount == 1)
    }
    @Test("全部提交但首轮尚未结束时恢复到确认结算，不提前重置周期")
    func pendingFinish() throws {
        let attempt = try learningAttemptFixture(["round": ["id": roundID.uuidString, "ordinal": 0, "questionIds": [], "completed": false, "answers": []]])
        let model = LearningChallengeModel(attempt: attempt, service: try ChallengeService())
        model.skipStory()
        #expect(model.stage == .summary)
        #expect(model.attempt.firstCompletedAt == nil)
    }
    @Test("首轮结束响应不确定时也撤销旧聊天周期")
    func uncertainFinishInvalidatesCycle() async throws {
        actor Flag {
            var calls = 0
            func mark() { calls += 1 }
        }
        let flag = Flag()
        let model = LearningChallengeModel(attempt: try learningAttemptFixture(), service: try ChallengeService(),
                                          afterFinish: { await flag.mark() })
        await model.finish(skipRemaining: true)
        #expect(model.error != nil)
        #expect(await flag.calls == 1)
        #expect(!model.isBusy)
    }
    @Test("公开题目不持有答案，六种提交形式编码为严格合同")
    func answerContract() throws {
        let answers: [LearningAnswer] = [.choice("a"), .arrange(["word1", "word2"]), .text("hello"), .matching([.init(left: "l1", right: "r1")]), .skip]
        for answer in answers {
            let data = try JSONEncoder().encode(answer)
            #expect(try JSONDecoder().decode(LearningAnswer.self, from: data) == answer)
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(object["points"] == nil)
        }
        let question = try learningAttemptFixture().unit.questions[0]
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(question)) as? [String: Any])
        #expect(object["answer"] == nil)
        #expect(object["explanation"] == nil)
    }
}
