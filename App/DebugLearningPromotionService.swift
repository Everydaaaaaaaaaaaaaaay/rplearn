#if DEBUG
import BackendKit
import Foundation

/// 仅用于免登录交互验收，所有剧情、分数、确认都留在进程内。
actor DebugLearningPromotionService: LearningPromotionServing {
    static let shared = DebugLearningPromotionService()
    private let id = UUID()
    private var position = 0
    private var revision = 1
    private var completed = false
    private var receipts: [UUID: LearningPromotion] = [:]
    private func snapshot() throws -> LearningPromotion {
        try decode(["id": id.uuidString, "fromLevel": "primary3", "toLevel": "primary4", "status": completed ? "completed" : "started", "courseHash": String(repeating: "a", count: 64), "acknowledgedBeats": position, "revision": revision, "profileVersion": 1, "completedProfileVersion": completed ? 2 : NSNull(), "completedAt": completed ? "2026-09-26T00:00:00Z" : NSNull(), "story": ["id": "preview.promotion", "title": "翻开下一页", "beats": [["id": "opening", "speaker": "Oliver", "text": "There is a new page in your notebook.", "translation": "你的笔记本，翻开了新的一页。"], ["id": "ending", "speaker": "Oliver", "text": "Take your time. We can read it together.", "translation": "慢慢来。我们可以一起读下去。"]]]])
    }
    func journey() throws -> LearningJourney {
        let level = completed ? "primary4" : "primary3"
        let levels: [[String: Any]] = ["primary3", "primary4"].map { key in
            let earned = key == "primary3"
            return ["level": key, "points": earned ? 540 : 0,
                    "displayPoints": earned ? 540 : 0, "targetPoints": 540,
                    "stars": earned ? 9 : 0, "currentStarPoints": earned ? 60 : 0,
                    "pointsPerStar": 60, "publishedUnitCount": 0]
        }
        let blockers: [[String: String]] = completed
            ? [["code": "points_remaining", "message": "新的学习旅程，从这里开始。"]] : []
        let promotion: [String: Any] = [
            "level": level, "nextLevel": completed ? "primary5" : "primary4",
            "points": completed ? 0 : 540, "targetPoints": 540,
            "goals": [], "transferCompleted": !completed, "courseVersion": 1,
            "courseHash": String(repeating: "a", count: 64), "ready": !completed,
            "completedPromotionId": NSNull(),
            "activePromotionId": position > 0 && !completed ? id.uuidString : NSNull(),
            "blockers": blockers
        ]
        return try decode([
            "currentLevel": level,
            "policy": ["version": 1, "characterThreshold": 1000, "pointsPerQuestion": 1,
                       "pointsPerStar": 60, "starsPerLevel": 9],
            "levels": levels, "promotion": promotion
        ])
    }
    func beginLearningPromotion(level: String, requestID: UUID) throws -> LearningPromotion { try snapshot() }
    func learningPromotion(_ id: UUID) throws -> LearningPromotion { try snapshot() }
    func advanceLearningPromotion(_ promotion: LearningPromotion, requestID: UUID) throws -> LearningPromotion {
        if let saved = receipts[requestID] { return saved }
        position = min(2, position + 1); revision += 1
        let value = try snapshot(); receipts[requestID] = value; return value
    }
    func completeLearningPromotion(_ id: UUID, command: LearningPromotionCommand) throws -> LearningPromotion {
        if let saved = receipts[command.requestId] { return saved }
        completed = true; revision += 1
        let value = try snapshot(); receipts[command.requestId] = value; return value
    }
    private func decode<T: Decodable>(_ object: [String: Any]) throws -> T { try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object)) }
}
#endif
