import BackendKit
import Foundation
@testable import LearningFeature
import Testing

private func achievementDecode<T: Decodable>(_ object: [String: Any]) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
}
private func achievementJourney(stars: Int, level: String = "primary3", ready: Bool = false) throws -> LearningJourney {
    try achievementDecode(["currentLevel": level,
        "policy": ["version": 1, "characterThreshold": 1000, "pointsPerQuestion": 1, "pointsPerStar": 60, "starsPerLevel": 9],
        "levels": [["level": level, "points": stars * 60, "displayPoints": stars * 60, "targetPoints": 540, "stars": stars, "currentStarPoints": 0, "pointsPerStar": 60]],
        "promotion": ["level": level, "nextLevel": "primary4", "points": stars * 60, "targetPoints": 540, "goals": [], "transferCompleted": ready, "ready": ready, "blockers": []]])
}
private func advancedJourney() throws -> LearningJourney {
    var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(achievementJourney(stars: 0, level: "primary4"))) as! [String: Any]
    var levels = object["levels"] as! [[String: Any]]
    levels += [["level": "primary3", "points": 540, "displayPoints": 540, "targetPoints": 540, "stars": 9, "currentStarPoints": 60, "pointsPerStar": 60]]
    object["levels"] = levels
    return try achievementDecode(object)
}
private actor AchievementService: LearningServing, LearningDirectionServing, LearningPromotionServing {
    let characterID = UUID(), attemptID = UUID(), roundID = UUID()
    var stars = 0
    var ready = false
    var failJourney = false
    var promotionStarts = 0
    var advanced = false
    var level = "primary3"
    func advance() { advanced = true; stars = 9 }
    func setLevel(_ value: String) { level = value }
    func set(stars: Int, ready: Bool = false, fail: Bool = false) { self.stars = stars; self.ready = ready; failJourney = fail }
    func learningJourney() throws -> LearningJourney {
        if failJourney { throw BackendClientError.invalidResponse }
        return try advanced ? advancedJourney() : achievementJourney(stars: stars, level: level, ready: ready)
    }
    func learningCharacter(_ id: UUID) throws -> BackendLearningCharacter {
        try achievementDecode(["characterId": id.uuidString, "roleKey": "oliver", "cycleId": roundID.uuidString, "characters": 1000, "threshold": 1000, "revision": 1, "activeAttemptId": attemptID.uuidString, "level": level, "availableUnits": 1])
    }
    func learningHistory(_ id: UUID, cursor: String?) throws -> LearningHistory { try achievementDecode(["items": []]) }
    func learningDirections() -> LearningDirections { .init(selectedDirection: "general", revision: 1, directions: [.init(id: "general", title: "通用英语", status: "available")]) }
    func selectLearningDirection(_ direction: String, requestID: UUID, expectedRevision: Int) -> LearningDirections { learningDirections() }
    func learningAttempt(_ id: UUID) throws -> LearningAttempt {
        try achievementDecode(["id": attemptID.uuidString, "characterId": characterID.uuidString, "level": level, "revision": 1, "startedAt": "2026-10-27T00:00:00Z", "correctQuestionIds": [],
            "round": ["id": roundID.uuidString, "ordinal": 0, "questionIds": ["q1"], "answers": [], "completed": false],
            "unit": ["id": "achievement.test", "version": 1, "schemaVersion": 1, "roleKey": "oliver", "level": "primary3", "title": "Test", "summary": "Test", "scene": "Test", "estimatedMinutes": 1, "goalIds": ["test"], "beats": [],
                "questions": [["id": "q1", "type": "choice", "goalId": "test", "instruction": "Choose.", "prompt": "Choose.", "hint": "Test", "options": [["id": "a", "text": "A"], ["id": "b", "text": "B"]]]]]])
    }
    func startLearning(_ id: UUID, requestID: UUID) throws -> LearningStart { throw BackendClientError.invalidResponse }
    func answerLearning(_ id: UUID, command: LearningAnswerCommand) throws -> LearningAnswerReceipt { throw BackendClientError.invalidResponse }
    func finishLearning(_ attempt: LearningAttempt, requestID: UUID, skipRemaining: Bool) throws -> LearningAttempt { attempt }
    func retryLearning(_ attempt: LearningAttempt, requestID: UUID) throws -> LearningAttempt { attempt }
    func beginLearningPromotion(level: String, requestID: UUID) throws -> LearningPromotion {
        promotionStarts += 1
        return try achievementDecode(["id": UUID().uuidString, "fromLevel": level, "toLevel": "primary4", "status": "started", "courseHash": String(repeating: "a", count: 64), "acknowledgedBeats": 0, "revision": 1, "profileVersion": 1, "story": ["id": "test", "title": "Next chapter", "beats": []]])
    }
    func learningPromotion(_ id: UUID) throws -> LearningPromotion { throw BackendClientError.invalidResponse }
    func advanceLearningPromotion(_ promotion: LearningPromotion, requestID: UUID) throws -> LearningPromotion { promotion }
    func completeLearningPromotion(_ id: UUID, command: LearningPromotionCommand) throws -> LearningPromotion { throw BackendClientError.invalidResponse }
}

@MainActor private final class AchievementProfileSync {
    var calls = 0
    var fails = false
    func refresh() throws {
        calls += 1
        if fails { throw BackendClientError.invalidResponse }
    }
}

@Suite("Learning achievement presentation") @MainActor
struct LearningAchievementTests {
    @Test("Authoritative advancement synchronizes the profile before acknowledgement, after the ninth-star flight")
    func automaticPromotionAfterLanding() async throws {
        let service = AchievementService(), sync = AchievementProfileSync()
        let model = CharacterLearningModel(characterID: service.characterID, service: service, profileChanged: { try sync.refresh() })
        await service.set(stars: 8); await model.load(); await model.open()
        model.recordReward(level: "primary3", points: 1)
        await service.advance(); await model.challengeClosed()
        #expect(model.journey?.currentLevel == "primary4")
        #expect(sync.calls == 2)
        #expect(model.presentedAutomaticPromotion == nil)
        let award = try #require(model.starAward)
        #expect(award.from == 8 && award.to == 9)
        model.consumeStarAward(award.id)
        #expect(model.presentedAutomaticPromotion?.toLevel == "primary4")
        model.presentedAutomaticPromotion = nil
        await model.load()
        #expect(model.presentedAutomaticPromotion == nil)
        #expect(sync.calls == 2)
    }
    @Test("Profile refresh failure keeps authoritative advancement and retries without replaying its star")
    func failedProfileSyncCanRecover() async throws {
        let service = AchievementService(), sync = AchievementProfileSync()
        let model = CharacterLearningModel(characterID: service.characterID, service: service, profileChanged: { try sync.refresh() })
        await service.set(stars: 8); await model.load(); await model.open()
        model.recordReward(level: "primary3", points: 1)
        sync.fails = true
        await service.advance(); await model.challengeClosed()
        #expect(model.journey?.currentLevel == "primary4")
        #expect(model.error != nil)
        model.consumeStarAward(try #require(model.starAward).id)
        #expect(model.presentedAutomaticPromotion == nil)
        sync.fails = false; await model.load()
        #expect(model.error == nil)
        #expect(model.starAward == nil)
        #expect(model.presentedAutomaticPromotion?.toLevel == "primary4")
        #expect(sync.calls == 3)
    }
    @Test("Failed journey refresh preserves an automatic advancement for recovery")
    func failedAdvancementReadCanRecover() async throws {
        let service = AchievementService()
        let model = CharacterLearningModel(characterID: service.characterID, service: service)
        await service.set(stars: 8); await model.load(); await model.open()
        model.recordReward(level: "primary3", points: 1)
        await service.advance(); await service.set(stars: 9, fail: true); await model.challengeClosed()
        #expect(model.journey?.currentLevel == "primary3")
        await service.set(stars: 9); await model.load()
        model.consumeStarAward(try #require(model.starAward).id)
        #expect(model.presentedAutomaticPromotion?.toLevel == "primary4")
    }
    @Test("Unrelated reloads synchronize changed difficulty without replaying a local ceremony")
    func unrelatedReloadHasNoCeremony() async {
        let service = AchievementService(), sync = AchievementProfileSync()
        let model = CharacterLearningModel(characterID: service.characterID, service: service, profileChanged: { try sync.refresh() })
        await model.load(); await service.advance(); await model.load(); await model.load()
        #expect(sync.calls == 2)
        #expect(model.starAward == nil)
        #expect(model.presentedAutomaticPromotion == nil)
    }
    @Test("The highest level still receives its ninth star without another promotion")
    func highestLevelCompletes() async throws {
        let service = AchievementService()
        await service.setLevel("advanced"); await service.set(stars: 8)
        let model = CharacterLearningModel(characterID: service.characterID, service: service)
        await model.load(); await model.open(); model.recordReward(level: "advanced", points: 1)
        await service.set(stars: 9); await model.challengeClosed()
        #expect(model.journey?.currentLevel == "advanced")
        model.consumeStarAward(try #require(model.starAward).id)
        #expect(model.presentedAutomaticPromotion == nil)
    }
    @Test("Automatic advancement preserves the ninth star earned on the previous level")
    func ninthStarSurvivesLevelChange() throws {
        let award = LearningStarAward(before: try achievementJourney(stars: 8), after: try advancedJourney(), rewardedLevel: "primary3", didEarnPoints: true)
        #expect(award?.level == "primary3")
        #expect(award?.from == 8)
        #expect(award?.to == 9)
    }
    @Test("Replay commands cannot synthesize rewards on a normal learning service")
    func previewCannotChangeNormalProgress() async {
        let service = AchievementService()
        let model = CharacterLearningModel(characterID: service.characterID, service: service)
        await model.load()
        await model.previewReward(toStars: 9)
        #expect(model.journey?.current?.stars == 0)
        #expect(model.starAward == nil)
        #expect(await service.stars == 0)
    }

    @Test("Only a locally rewarded increase in the same current level creates a star display receipt")
    func authoritativeDeltaOnly() throws {
        let zero = try achievementJourney(stars: 0), one = try achievementJourney(stars: 1)
        #expect(LearningStarAward(before: zero, after: one, rewardedLevel: "primary3", didEarnPoints: true)?.to == 1)
        #expect(LearningStarAward(before: nil, after: one, rewardedLevel: "primary3", didEarnPoints: true) == nil)
        #expect(LearningStarAward(before: zero, after: one, rewardedLevel: "primary3", didEarnPoints: false) == nil)
        #expect(LearningStarAward(before: one, after: one, rewardedLevel: "primary3", didEarnPoints: true) == nil)
        #expect(LearningStarAward(before: one, after: zero, rewardedLevel: "primary3", didEarnPoints: true) == nil)
        #expect(LearningStarAward(before: zero, after: try achievementJourney(stars: 1, level: "primary4"), rewardedLevel: "primary3", didEarnPoints: true) == nil)
        #expect(LearningStarAward(before: zero, after: one, rewardedLevel: "primary2", didEarnPoints: true) == nil)
    }
    @Test("First, ninth and multiple stars land in order and finish at the clamped server total")
    func boundedTimeline() {
        let first = LearningStarAward(level: "primary3", from: 0, to: 1)
        #expect(first.landed(at: 0) == 0)
        #expect(first.landed(at: first.duration) == 1)
        let last = LearningStarAward(level: "primary3", from: 8, to: 99)
        #expect(last.to == 9 && last.count == 1)
        let multiple = LearningStarAward(level: "primary3", from: 3, to: 6)
        #expect(multiple.landed(at: 1.4) == 1)
        #expect(multiple.landed(at: multiple.duration) == 3)
        #expect(multiple.duration < 2.2)
    }
    @Test("Returning from a rewarded challenge queues one celebration; refreshing and opening history do not replay it")
    func rewardedReturnAndConsumption() async throws {
        let service = AchievementService()
        let model = CharacterLearningModel(characterID: service.characterID, service: service)
        await model.load(); #expect(model.starAward == nil)
        await model.open()
        model.recordReward(level: "primary3", points: 1)
        await service.set(stars: 1)
        #expect(model.starAward == nil)
        await model.challengeClosed()
        let award = try #require(model.starAward)
        #expect(award.from == 0 && award.to == 1)
        model.consumeStarAward(award.id); await model.load()
        #expect(model.starAward == nil)
        await model.open(); await service.set(stars: 2); await model.challengeClosed()
        #expect(model.starAward == nil)
    }
    @Test("Zero rewards and rewards for another level cannot arm a celebration")
    func noRewardNoCelebration() async {
        let service = AchievementService()
        let model = CharacterLearningModel(characterID: service.characterID, service: service)
        await model.load(); await model.open()
        model.recordReward(level: "primary3", points: 0)
        model.recordReward(level: "primary2", points: 4)
        await service.set(stars: 1); await model.challengeClosed()
        #expect(model.starAward == nil)
    }
    @Test("A failed refresh retains the reward receipt for a later authoritative read")
    func failedReadCanRecover() async throws {
        let service = AchievementService()
        let model = CharacterLearningModel(characterID: service.characterID, service: service)
        await model.load(); await model.open(); model.recordReward(level: "primary3", points: 1)
        await service.set(stars: 1, fail: true); await model.challengeClosed()
        #expect(model.starAward == nil)
        await service.set(stars: 1); await model.load()
        #expect(try #require(model.starAward).to == 1)
    }
    @Test("Nine stars do not start a special course or require manual promotion")
    func promotionEligibility() async {
        let service = AchievementService()
        let model = CharacterLearningModel(characterID: service.characterID, service: service)
        await model.load(); await model.openPromotion()
        #expect(await service.promotionStarts == 0)
        await service.set(stars: 9, ready: true); await model.load()
        #expect(!model.canOpenPromotion)
        await model.openPromotion()
        #expect(await service.promotionStarts == 0)
        #expect(model.presentedPromotion == nil)
    }
}
