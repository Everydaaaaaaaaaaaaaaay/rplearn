#if DEBUG
import BackendKit
import Foundation
@testable import LearningFeature
import PersistenceKit
import Testing

private actor TrialService: LearningServing, LearningDirectionServing {
    let characterID = UUID()
    let cycleID = UUID()
    let attemptID = UUID()
    var level = "primary3"
    var published = 2
    var activeLevel: String?
    var preparing = false
    var loseStartResponse = false
    var events: [String] = []
    var selectedDirection = "general"
    var directionRevision = 3
    func configure(published: Int = 2, active: String? = nil, preparing: Bool = false, lost: Bool = false) {
        self.published = published; activeLevel = active; self.preparing = preparing; loseStartResponse = lost
    }
    func change(_ value: DifficultyLevel) { events.append("level"); level = value.rawValue }
    func fill(_ character: UUID, cycle: UUID) throws {
        guard character == characterID, cycle == cycleID else { throw BackendClientError.invalidResponse }
        events.append("fill")
    }
    func learningJourney() async throws -> LearningJourney {
        try decode(["currentLevel":level,"policy":["version":1,"characterThreshold":1000,"pointsPerQuestion":1,"pointsPerStar":60,"starsPerLevel":9],
                    "levels":DifficultyLevel.allCases.filter { $0 != .kindergarten }.map { ["level":$0.rawValue,"points":0,"displayPoints":0,"targetPoints":540,"stars":0,"currentStarPoints":0,"pointsPerStar":60,"publishedUnitCount":published] as [String:Any] }])
    }
    func learningCharacter(_ id: UUID) async throws -> BackendLearningCharacter {
        try decode(["characterId":id.uuidString,"roleKey":"oliver","cycleId":cycleID.uuidString,"characters":0,"threshold":1000,"revision":1,"activeAttemptId":activeLevel == nil ? NSNull() : attemptID.uuidString as Any,"level":level,"availableUnits":published])
    }
    func learningAttempt(_ id: UUID) async throws -> LearningAttempt {
        try decode(["id":id.uuidString,"characterId":characterID.uuidString,"level":activeLevel ?? level,"revision":1,"startedAt":"2026-10-19T00:00:00Z","correctQuestionIds":[],
                    "round":["id":cycleID.uuidString,"ordinal":0,"questionIds":[],"completed":false,"answers":[]],
                    "unit":["id":"test.unit","version":1,"schemaVersion":1,"roleKey":"oliver","level":activeLevel ?? level,"title":"单元测试夹具","summary":"仅测试客户端流程","scene":"测试","estimatedMinutes":2,"goalIds":[],"beats":[],"questions":[]]])
    }
    func startLearning(_ id: UUID, requestID: UUID) async throws -> LearningStart {
        events.append("start")
        if !preparing { activeLevel = level }
        if loseStartResponse { throw BackendClientError.transport("测试响应丢失") }
        var json: [String: Any] = ["status":preparing ? "preparing":"started"]
        if !preparing {
            let attempt = try await learningAttempt(attemptID)
            json["attempt"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(attempt))
        }
        return try decode(json)
    }
    func learningDirections() async throws -> LearningDirections {
        .init(selectedDirection:selectedDirection,revision:directionRevision,directions:[.init(id:"general",title:"通用英语",status:"available")])
    }
    func selectLearningDirection(_ direction: String, requestID: UUID, expectedRevision: Int) async throws -> LearningDirections {
        guard expectedRevision == directionRevision else { throw BackendClientError.invalidResponse }
        events.append("direction"); selectedDirection = direction; directionRevision += 1
        return try await learningDirections()
    }
    func learningHistory(_ id: UUID, cursor: String?) async throws -> LearningHistory { throw BackendClientError.invalidResponse }
    func answerLearning(_ id: UUID, command: LearningAnswerCommand) async throws -> LearningAnswerReceipt { throw BackendClientError.invalidResponse }
    func finishLearning(_ attempt: LearningAttempt, requestID: UUID, skipRemaining: Bool) async throws -> LearningAttempt { throw BackendClientError.invalidResponse }
    func retryLearning(_ attempt: LearningAttempt, requestID: UUID) async throws -> LearningAttempt { throw BackendClientError.invalidResponse }
    private func decode<T: Decodable>(_ value: [String:Any]) throws -> T {
        try JSONDecoder().decode(T.self,from:JSONSerialization.data(withJSONObject:value))
    }
}

@Suite("真实学习测试入口的请求与恢复") @MainActor
struct LearningTrialTests {
    private func model(_ service: TrialService, confirmLevel: Bool = true) -> LearningTrialModel {
        LearningTrialModel(service:service,changeLevel:{ level in
            if confirmLevel { await service.change(level) }
        },fillCycle:{ id, cycle, _ in try await service.fill(id,cycle:cycle) })
    }
    @Test("只提供十五档，不恢复启蒙")
    func scope() {
        #expect(LearningTrialModel.levels.count == 15)
        #expect(!LearningTrialModel.levels.contains(.kindergarten))
    }
    @Test("无已发布内容时不改档位、不填循环、不造挑战")
    func noSupply() async {
        let service = TrialService(); await service.configure(published:0)
        let model = model(service); model.selectedLevel = .senior3
        await model.start(characterID:service.characterID)
        #expect(await service.events.isEmpty)
        #expect(model.presentedAttempt == nil)
        #expect(model.notice?.contains("没有已发布") == true)
    }
    @Test("已有其他档位挑战时不改题、不切档，可明确续做原挑战")
    func activeOtherLevel() async {
        let service = TrialService(); await service.configure(active:"primary3")
        let model = model(service); model.selectedLevel = .senior3
        await model.start(characterID:service.characterID)
        #expect(model.presentedAttempt == nil)
        #expect(model.activeAttempt?.level == "primary3")
        #expect(await service.events.isEmpty)
        await model.resume()
        #expect(model.presentedAttempt?.level == "primary3")
    }
    @Test("同档已有挑战直接续做，不制造新记录")
    func activeSameLevel() async {
        let service = TrialService(); await service.configure(active:"senior3")
        let model = model(service); model.selectedLevel = .senior3
        await model.start(characterID:service.characterID)
        #expect(model.presentedAttempt?.level == "senior3")
        #expect(await service.events.isEmpty)
    }
    @Test("先确认服务端档位，再略过等待，最后调用正式开始接口")
    func realRequestOrder() async {
        let service = TrialService(); let model = model(service); model.selectedLevel = .senior3
        await model.start(characterID:service.characterID)
        #expect(await service.events == ["level","fill","start"])
        #expect(model.presentedAttempt?.level == "senior3")
        #expect(model.journey?.currentLevel == "senior3")
    }
    @Test("未确认档位时不向旧档位开始接口继续请求")
    func levelNotConfirmed() async {
        let service = TrialService(); let model = model(service,confirmLevel:false); model.selectedLevel = .senior3
        await model.start(characterID:service.characterID)
        #expect(await service.events.isEmpty)
        #expect(model.error?.contains("尚未确认") == true)
        #expect(model.presentedAttempt == nil)
    }
    @Test("题库准备中仅显示真实状态，不生成本地题面")
    func preparing() async {
        let service = TrialService(); await service.configure(preparing:true)
        let model = model(service); await model.start(characterID:service.characterID)
        #expect(model.presentedAttempt == nil)
        #expect(model.notice?.contains("暂时没有可用") == true)
    }
    @Test("开始响应丢失后读回真实活动挑战，明确续做")
    func lostResponse() async {
        let service = TrialService(); await service.configure(lost:true)
        let model = model(service); await model.start(characterID:service.characterID)
        #expect(model.error != nil)
        #expect(model.presentedAttempt == nil)
        #expect(model.activeAttempt?.level == "primary3")
        await model.resume()
        #expect(model.presentedAttempt?.level == "primary3")
        #expect(await service.events.filter { $0 == "start" }.count == 1)
    }
}
#endif
