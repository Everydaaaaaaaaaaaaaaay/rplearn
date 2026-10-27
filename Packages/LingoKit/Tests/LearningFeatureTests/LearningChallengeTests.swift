import BackendKit
import Foundation
@testable import LearningFeature
import Testing

private let attemptID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
private let characterID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
private let roundID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
private func learningAttemptFixture(_ overrides: [String: Any] = [:], beats: [[String: Any]]? = nil, questions: [[String: Any]]? = nil) throws -> LearningAttempt {
    var object: [String: Any] = [
        "id": attemptID.uuidString, "characterId": characterID.uuidString, "level": "primary3", "revision": 1,
        "startedAt": "2026-09-26T00:00:00Z", "firstCompletedAt": NSNull(), "correctQuestionIds": [],
        "round": ["id": roundID.uuidString, "ordinal": 0, "questionIds": ["q1", "q2"], "completed": false, "answers": []],
        "unit": ["id": "test.unit", "version": 1, "schemaVersion": 1, "roleKey": "oliver", "level": "primary3", "title": "工程夹具", "summary": "仅验证合同", "scene": "测试环境", "estimatedMinutes": 2, "goalIds": ["test.goal"],
                 "beats": [["id": "opening", "afterQuestion": 0, "speaker": "测试", "text": "Hello.", "translation": "你好。"]],
                 "questions": ["q1", "q2"].map { ["id": $0, "type": "choice", "goalId": "test.goal", "instruction": "选择", "prompt": "工程检查", "hint": "提示", "options": [["id": "a", "text": "A"], ["id": "b", "text": "B"]]] }]
    ]
    if let beats {
        var unit = object["unit"] as! [String: Any]
        unit["beats"] = beats
        object["unit"] = unit
    }
    if let questions {
        var unit = object["unit"] as! [String: Any]
        unit["questions"] = questions
        object["unit"] = unit
    }
    for (key, value) in overrides { object[key] = value }
    return try JSONDecoder().decode(LearningAttempt.self, from: JSONSerialization.data(withJSONObject: object))
}
private actor ChallengeService: LearningServing, LearningDirectionServing {
    var attempt: LearningAttempt
    var commands: [LearningAnswerCommand] = []
    var failAfterSaving = true
    var directionState = LearningDirections(selectedDirection: "general", revision: 0, directions: [
        .init(id: "general", title: "通用英语", status: "available"),
        .init(id: "ielts-academic", title: "雅思 Academic", status: "inReview")
    ])
    var directionReadFails = false
    var directionResponseLost = false
    var directionCommands: [(UUID, String, Int)] = []
    var directionReceipts: [UUID: LearningDirections] = [:]
    var starts = 0
    func setDirectionReadFails(_ value: Bool) { directionReadFails = value }
    func setDirectionResponseLost(_ value: Bool) { directionResponseLost = value }
    func changeDirectionOnOtherDevice(_ direction: String) {
        directionState = .init(selectedDirection: direction, revision: directionState.revision + 1, directions: directionState.directions)
    }
    func learningDirections() async throws -> LearningDirections {
        if directionReadFails { throw BackendClientError.transport("方向读取失败") }
        return directionState
    }
    func selectLearningDirection(_ direction: String, requestID: UUID, expectedRevision: Int) async throws -> LearningDirections {
        directionCommands.append((requestID, direction, expectedRevision))
        if let receipt = directionReceipts[requestID] { return receipt }
        guard expectedRevision == directionState.revision else {
            throw BackendClientError.api(code: "LEARNING_DIRECTION_CONFLICT", message: "方向已在另一设备更改", requestID: nil, status: 409)
        }
        changeDirectionOnOtherDevice(direction)
        directionReceipts[requestID] = directionState
        if directionResponseLost { directionResponseLost = false; throw BackendClientError.transport("选择已保存但响应丢失") }
        return directionState
    }
    init(attempt: LearningAttempt? = nil) throws { self.attempt = try attempt ?? learningAttemptFixture() }
    func startLearning(_ characterID: UUID, requestID: UUID) async throws -> LearningStart { starts += 1; throw BackendClientError.invalidResponse }
    var pageReads: Set<String> = []
    var pageError: (any Error)?
    func setPageError(_ error: any Error) { pageError = error }
    private func readPage<T: Decodable>(_ path: String, json: String) throws -> T {
        pageReads.insert(path)
        if let pageError { throw pageError }
        return try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
    func learningCharacter(_ characterID: UUID) async throws -> BackendLearningCharacter {
        try readPage("character", json: """
        {"characterId":"\(characterID)","roleKey":"oliver","cycleId":"\(roundID)",
         "characters":720,"threshold":1000,"revision":7,"level":"primary3","availableUnits":3}
        """)
    }
    func learningJourney() async throws -> LearningJourney {
        try readPage("journey", json: """
        {"currentLevel":"primary3","policy":{"version":1,"characterThreshold":1000,
         "pointsPerQuestion":1,"pointsPerStar":60,"starsPerLevel":9},
         "levels":[{"level":"primary3","points":61,"displayPoints":61,"targetPoints":540,
         "stars":1,"currentStarPoints":1,"pointsPerStar":60}]}
        """)
    }
    func learningHistory(_ characterID: UUID, cursor: String?) async throws -> LearningHistory {
        try readPage("history", json: """
        {"items":[{"id":"\(attemptID)","title":"工程夹具","level":"primary3",
         "startedAt":"2026-09-26T00:00:00Z","correctCount":1,"questionCount":6}],"nextCursor":"page2"}
        """)
    }
    func learningAttempt(_ id: UUID) async throws -> LearningAttempt { attempt }
    func answerLearning(_ id: UUID, command: LearningAnswerCommand) async throws -> LearningAnswerReceipt {
        commands.append(command)
        let result: [String: Any] = ["outcome": "correct", "explanation": "服务端解析", "solution": ["kind": "choice", "optionId": "a"]]
        let body: [String: Any] = ["id": roundID.uuidString, "ordinal": 0, "questionIds": ["q1", "q2"], "completed": false,
                                  "answers": [["questionId": "q1", "answer": ["kind": "choice", "optionId": "a"], "result": result]]]
        let unit = try JSONSerialization.jsonObject(with: JSONEncoder().encode(attempt.unit))
        attempt = try learningAttemptFixture(["revision": 2, "round": body, "correctQuestionIds": ["q1"], "unit": unit])
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
    @Test("声音配图保留多余候选，未完整配对不可提交，逐项结果可以解码")
    func audioMatchingContract() throws {
        let question: [String: Any] = ["id":"q1","type":"audioMatching","goalId":"test.goal","instruction":"配图","prompt":"工程检查","hint":"工程提示",
            "audioOptions":[["id":"s1","audio":["assetId":"audio.one"]],["id":"s2","audio":["assetId":"audio.two"]]],
            "right":[["id":"r1","text":"图一","imageAssetId":"image.one"],["id":"r2","text":"图二","imageAssetId":"image.two","caption":"会"],["id":"r3","text":"图三","imageAssetId":"image.three"]]]
        let attempt = try learningAttemptFixture(["firstCompletedAt":"2026-09-26T01:00:00Z"], questions:[question])
        let model = LearningChallengeModel(attempt:attempt,service:try ChallengeService())
        model.skipStory()
        #expect(model.question?.type == .audioMatching)
        #expect(model.question?.audioAssetIDs.count == 2)
        #expect(model.question?.imageAssetIDs.count == 3)
        model.selectedLeft="s1"; model.selectPair(right:"r1")
        #expect(model.answer == nil)
        model.selectedLeft="s2"; model.selectPair(right:"r2")
        #expect(model.answer?.pairs?.count == 2)
        model.selectedLeft="s2"; model.selectPair(right:"r1")
        #expect(model.answer == nil); #expect(model.pairs.count == 1)
        let grade=try JSONDecoder().decode(LearningGrade.self,from:Data(#"{"outcome":"incorrect","explanation":"工程反馈","solution":{"kind":"matching","pairs":[{"left":"s1","right":"r2"},{"left":"s2","right":"r1"}]},"pairResults":[{"left":"s1","correct":false},{"left":"s2","correct":true}]}"#.utf8))
        #expect(grade.pairResults?.map(\.correct) == [false,true])
    }

    @Test("多空共享词库支持指定空位、替换、回收和完整提交")
    func clozeInteraction() async throws {
        let q: [String: Any] = ["id": "q1", "type": "cloze", "goalId": "test.goal", "instruction": "填两空", "prompt": "工程检查", "hint": "提示",
            "passage": "One {first}.\nTwo {second}.", "tokens": [["id": "a", "text": "A"], ["id": "b", "text": "B"], ["id": "c", "text": "C"]]]
        let service = try ChallengeService()
        let model = LearningChallengeModel(attempt: try learningAttemptFixture(questions: [q]), service: service)
        model.skipStory()
        #expect(model.question?.clozeSlotIDs == ["first", "second"])
        #expect(model.activeSlot == "first")
        model.fillSlot(with: "missing")
        #expect(model.fills.isEmpty)
        model.fillSlot(with: "a")
        #expect(model.activeSlot == "second")
        #expect(model.answer == nil)
        model.selectSlot("first")
        model.fillSlot(with: "c")
        #expect(model.fills == [.init(slotId: "first", tokenId: "c")])
        model.fillSlot(with: "b")
        #expect(model.answer?.kind == .cloze)
        model.clearSlot("first")
        #expect(model.answer == nil)
        #expect(model.activeSlot == "first")
        model.fillSlot(with: "a")
        let answer = try #require(model.answer)
        #expect(try JSONDecoder().decode(LearningAnswer.self, from: JSONEncoder().encode(answer)) == answer)
        #expect(Set(model.fills.map(\.tokenId)).count == 2)
        await model.submit()
        #expect(model.hasUnconfirmedAnswer)
        let frozen = model.fills
        model.clearSlot("first"); model.selectSlot("second"); model.fillSlot(with: "c")
        #expect(model.fills == frozen)
        #expect(await service.commands.first?.answer == answer)
    }
    @Test("多空逐空反馈可解码，公开题面不含答案组合")
    func clozeFeedbackContract() throws {
        let json = #"{"outcome":"incorrect","explanation":"工程反馈","solution":{"kind":"cloze","fills":[{"slotId":"a","tokenId":"x"},{"slotId":"b","tokenId":"y"}]},"slotResults":[{"slotId":"a","correct":true},{"slotId":"b","correct":false}]}"#
        let grade = try JSONDecoder().decode(LearningGrade.self, from: Data(json.utf8))
        #expect(grade.slotResults?.map(\.correct) == [true, false])
        #expect(grade.solution.fills?.count == 2)
    }
    @Test("十八题可完整解码，听后排序按卡片标识提交而不持有原文")
    func longAudioOrderingContract() throws {
        let questions: [[String: Any]] = (0..<18).map { index in
            ["id": "q\(index)", "type": "audioArrange", "goalId": "test.goal", "instruction": "听后排序", "prompt": "工程检查", "hint": "可重听",
             "tokens": [["id": "first", "text": "1"], ["id": "second", "text": "2"]], "audio": ["assetId": "test.audio"]]
        }
        let attempt = try learningAttemptFixture([
            "firstCompletedAt": "2026-09-26T01:00:00Z",
            "round": ["id": roundID.uuidString, "ordinal": 1, "questionIds": questions.map { $0["id"] as! String }, "completed": false, "answers": []]
        ], questions: questions)
        let model = LearningChallengeModel(attempt: attempt, service: try ChallengeService())
        #expect(model.attempt.unit.questions.count == 18)
        #expect(model.question?.type == .audioArrange)
        #expect(model.question?.audio?.assetId == "test.audio")
        #expect(model.answer == nil)
        model.tokens = ["second", "first"]
        #expect(model.answer == .arrange(["second", "first"]))
        let publicQuestion = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(model.question)) as? [String: Any])
        #expect(publicQuestion["acceptedOrders"] == nil)
        #expect((publicQuestion["audio"] as? [String: Any])?["text"] == nil)
    }
    private var storyBeats: [[String: Any]] {
        [("opening", 0), ("resolution", 0), ("old_pause", 1), ("old_ending", 2)].map { id, position in
            ["id": id, "afterQuestion": position, "speaker": "旁白", "text": "A short story.", "translation": "一段短故事。"]
        }
    }
    @Test("短故事在第一题前完整播放，作答后不插入历史题间镜头")
    func openingBeforeQuestions() async throws {
        let attempt = try learningAttemptFixture(beats: storyBeats)
        let service = try ChallengeService(attempt: attempt)
        let model = LearningChallengeModel(attempt: attempt, service: service)
        model.advance(); #expect(model.stage == .story(0))
        #expect(!model.isLastOpeningBeat)
        model.advance(); #expect(model.stage == .story(1))
        #expect(model.isLastOpeningBeat)
        model.advance(); #expect(model.stage == .question("q1"))
        model.choice = "a"
        await model.submit(); await model.submit()
        model.advance(); #expect(model.stage == .question("q2"))
    }
    @Test("跳过故事一次即可开始题目，不逐镜头跳过")
    func skipEntireOpening() throws {
        let model = LearningChallengeModel(attempt: try learningAttemptFixture(beats: storyBeats), service: try ChallengeService())
        model.advance()
        model.skipStory()
        #expect(model.stage == .question("q1"))
    }
    @Test("学习页直接读取三个学习接口，展示服务端进度与补答记录")
    func loadsLearningState() async throws {
        let service = try ChallengeService()
        let model = CharacterLearningModel(characterID: characterID, service: service)
        await model.load()
        #expect(await service.pageReads == ["character", "journey", "history"])
        #expect(model.state?.characterId == characterID)
        #expect(model.state?.characters == 720)
        #expect(model.state?.revision == 7)
        #expect(model.journey?.current?.points == 61)
        #expect(model.history.first?.correctCount == 1)
        #expect(model.nextCursor == "page2")
        #expect(model.error == nil)
        #expect(!model.isBusy)
    }
    @Test("刷新失败保留已确认的学习状态，不伪造进度或清除补答记录")
    func keepsConfirmedStateOnReadFailure() async throws {
        let service = try ChallengeService()
        let model = CharacterLearningModel(characterID: characterID, service: service)
        await model.load()
        await service.setPageError(BackendClientError.api(code: "INVALID_REQUEST", message: "The request is invalid.", requestID: nil, status: 400))
        await model.load()
        #expect(model.error == "请求未能通过服务器校验。")
        #expect(model.state?.characters == 720)
        #expect(model.history.first?.correctCount == 1)
        #expect(!model.isBusy)
    }
    @Test("取消学习页读取不显示失败提示")
    func learningReadCancelled() async throws {
        let service = try ChallengeService()
        await service.setPageError(CancellationError())
        let model = CharacterLearningModel(characterID: characterID, service: service)
        await model.load()
        #expect(model.error == nil)
        #expect(model.state == nil)
        #expect(!model.isBusy)
    }

    @Test("准备中方向不新开挑战，但历史补答与普通等级保留")
    func unavailableDirectionPreservesHistory() async throws {
        let service = try ChallengeService()
        let model = CharacterLearningModel(characterID: characterID, service: service)
        await model.load()
        await model.selectDirection("ielts-academic")
        #expect(model.directions?.selectedDirection == "ielts-academic")
        #expect(!model.canStartNewChallenge)
        await model.open()
        #expect(await service.starts == 0)
        await model.open(attemptID)
        #expect(model.presentedAttempt?.id == attemptID)
        #expect(model.state?.characters == 720)
        #expect(model.journey?.current?.points == 61)
        #expect(model.history.count == 1)
    }

    @Test("方向读取失败或未知方向不能偷偷回到普通练习，历史仍可打开")
    func unavailableDirectionReadFailsClosed() async throws {
        let service = try ChallengeService()
        let model = CharacterLearningModel(characterID: characterID, service: service)
        await model.load()
        await service.setDirectionReadFails(true)
        await model.load()
        #expect(model.directions == nil)
        #expect(model.directionError != nil)
        await model.open()
        #expect(await service.starts == 0)
        await model.open(attemptID)
        #expect(model.presentedAttempt?.id == attemptID)
        await service.setDirectionReadFails(false)
        await service.changeDirectionOnOtherDevice("future-exam")
        await model.load()
        #expect(model.directions?.selectedDirection == "future-exam")
        #expect(!model.canStartNewChallenge)
    }

    @Test("切换响应丢失后刷新仍可重试，复用请求且显示最新跨设备选择")
    func lostDirectionResponseSurvivesRefresh() async throws {
        let service = try ChallengeService()
        let model = CharacterLearningModel(characterID: characterID, service: service)
        await model.load()
        await service.setDirectionResponseLost(true)
        await model.selectDirection("ielts-academic")
        #expect(model.pendingDirection == "ielts-academic")
        #expect(!model.canStartNewChallenge)
        await service.changeDirectionOnOtherDevice("general")
        await model.load()
        #expect(model.directionError != nil)
        #expect(model.pendingDirection != nil)
        await model.selectDirection("general")
        #expect(await service.directionCommands.count == 1)
        await model.selectDirection("ielts-academic")
        let commands = await service.directionCommands
        #expect(commands.count == 2)
        #expect(commands[0].0 == commands[1].0)
        #expect(commands[0].2 == commands[1].2)
        #expect(model.pendingDirection == nil)
        #expect(model.directions?.selectedDirection == "general")
        #expect(model.directions?.revision == 2)
        #expect(model.canStartNewChallenge)
    }

    @Test("跨设备冲突刷新真实方向，不覆盖其他设备的选择")
    func directionConflictRefreshesAuthority() async throws {
        let service = try ChallengeService()
        let model = CharacterLearningModel(characterID: characterID, service: service)
        await model.load()
        await service.changeDirectionOnOtherDevice("ielts-academic")
        await model.selectDirection("ielts-academic")
        #expect(model.directionError != nil)
        #expect(model.pendingDirection == nil)
        #expect(model.directions?.revision == 1)
        #expect(await service.directionCommands.count == 1)
        #expect(!model.canStartNewChallenge)
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
    @Test("听力笔记保留短答合同并阻止空白、超限或缺失词限提交")
    func listeningCompletionAnswers() throws {
        var question: [String: Any] = ["id": "q1", "type": "listeningCompletion", "goalId": "test.goal",
            "instruction": "听录音补全笔记", "prompt": "Bring ____.", "hint": "留意必需物品",
            "audio": ["assetId": "audio.test"], "wordLimit": 2]
        let attempt = try learningAttemptFixture(questions: [question])
        let model = LearningChallengeModel(attempt: attempt, service: try ChallengeService())
        model.skipStory()
        #expect(model.question?.audioAssetIDs == ["audio.test"])
        #expect(model.answer == nil)
        model.text = "sturdy shoes"
        #expect(model.answer == .text("sturdy shoes"))
        model.text = "very sturdy shoes"
        #expect(model.answer == nil)
        #expect(model.answerWordCount == 3)
        model.text = "\u{FEFF} \n"
        #expect(model.answer == nil)
        let data = try JSONEncoder().encode(attempt.unit.questions[0])
        let publicQuestion = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(publicQuestion["acceptedAnswers"] == nil)
        #expect((publicQuestion["audio"] as? [String: Any])?["text"] == nil)
        question.removeValue(forKey: "wordLimit")
        let invalid = LearningChallengeModel(attempt: try learningAttemptFixture(questions: [question]), service: try ChallengeService())
        invalid.skipStory(); invalid.text = "shoes"
        #expect(invalid.answer == nil)
    }
    @Test("短答分词与服务端共享空白集合，连字符和撇号不拆词")
    func listeningCompletionWordCount() {
        #expect(LearningQuestion.answerWordCount("  acid-free\t tissues\n") == 2)
        #expect(LearningQuestion.answerWordCount("student's book") == 2)
        #expect(LearningQuestion.answerWordCount("sturdy\u{00A0}shoes") == 2)
        #expect(LearningQuestion.answerWordCount("\u{FEFF}sturdy\u{3000}shoes\u{202F}") == 2)
        #expect(LearningQuestion.answerWordCount("sturdy\u{200B}shoes") == 1)
        #expect(LearningQuestion.answerWordCount("\t\n \u{FEFF}") == 0)
    }
    @Test("公开题目不持有答案，六种提交形式编码为严格合同")
    func answerContract() throws {
        let answers: [LearningAnswer] = [.choice("a"), .arrange(["word1", "word2"]), .text("hello"), .matching([.init(left: "l1", right: "r1")]), .cloze([.init(slotId: "s1", tokenId: "a"), .init(slotId: "s2", tokenId: "b")]), .skip]
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
    @Test("Achievement callback waits for a positive confirmed answer receipt and does not replay feedback")
    func confirmedRewardCallback() async throws {
        actor RewardFlag {
            var points = 0
            func record(_ points: Int) { self.points += points }
        }
        let flag = RewardFlag()
        let model = LearningChallengeModel(attempt: try learningAttemptFixture(), service: try ChallengeService(),
            didEarnPoints: { _, points in await flag.record(points) })
        model.skipStory(); model.choice = "a"
        await model.submit()
        #expect(await flag.points == 0)
        await model.submit()
        #expect(await flag.points == 1)
        await model.submit()
        #expect(await flag.points == 1)
    }

}
