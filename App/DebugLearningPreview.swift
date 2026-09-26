#if DEBUG
import BackendKit
import Foundation

/// 仅免登录界面预览使用，不请求后端，不写账号或题库；没有虚构挑战记录。
struct DebugLearningPreviewService: LearningServing {
    let characterID: UUID
    let roleKey: String
    func learningCharacter(_ characterID: UUID) async throws -> BackendLearningCharacter {
        try decode(["characterId": characterID.uuidString, "roleKey": roleKey, "cycleId": UUID().uuidString,
                    "characters": 720, "threshold": 1000, "revision": 1, "activeAttemptId": NSNull(), "level": "primary3",
                    "availableUnits": 0, "generationStatus": NSNull()])
    }
    func learningJourney() async throws -> LearningJourney {
        try decode(["currentLevel": "primary3", "policy": ["version": 1, "characterThreshold": 1000, "pointsPerQuestion": 1, "pointsPerStar": 60, "starsPerLevel": 9],
                    "levels": [["level": "primary3", "points": 0, "displayPoints": 0, "targetPoints": 540, "stars": 0, "currentStarPoints": 0, "pointsPerStar": 60]]])
    }
    func learningHistory(_ characterID: UUID, cursor: String?) async throws -> LearningHistory { try decode(["items": [], "nextCursor": NSNull()]) }
    func learningAttempt(_ id: UUID) async throws -> LearningAttempt { throw unavailable }
    func startLearning(_ characterID: UUID, requestID: UUID) async throws -> LearningStart { throw unavailable }
    func answerLearning(_ id: UUID, command: LearningAnswerCommand) async throws -> LearningAnswerReceipt { throw unavailable }
    func finishLearning(_ attempt: LearningAttempt, requestID: UUID, skipRemaining: Bool) async throws -> LearningAttempt { throw unavailable }
    func retryLearning(_ attempt: LearningAttempt, requestID: UUID) async throws -> LearningAttempt { throw unavailable }
    func previewAttempt(kind: String) throws -> LearningAttempt {
        let supported = ["choice", "arrange", "matching", "completion"]
        let type = supported.contains(kind) ? kind : "choice"
        let question: [String: Any] = ["id": "preview.question", "type": type, "goalId": "preview.goal",
            "instruction": "界面预览：完成这个练习", "prompt": "这是一道工程检查题，用于观察题干换行和操作区域，不计入学习记录。", "hint": "示例提示。",
            "options": [["id": "a", "text": "First option"], ["id": "b", "text": "Second option"]],
            "tokens": [["id": "i", "text": "I"], ["id": "would", "text": "would"], ["id": "like", "text": "like"], ["id": "to", "text": "to"], ["id": "read", "text": "read"], ["id": "books", "text": "books"]],
            "left": [["id": "l1", "text": "a book"], ["id": "l2", "text": "a pencil"], ["id": "l3", "text": "a bag"]],
            "right": [["id": "r1", "text": "一本书"], ["id": "r2", "text": "一个包"], ["id": "r3", "text": "一支铅笔"]]]
        return try decode(["id": UUID().uuidString, "characterId": characterID.uuidString, "level": "primary3", "revision": 1,
            "startedAt": "2026-09-26T00:00:00Z", "firstCompletedAt": "2026-09-26T00:00:00Z", "correctQuestionIds": [],
            "round": ["id": UUID().uuidString, "ordinal": 1, "questionIds": ["preview.question"], "completed": false, "answers": []],
            "unit": ["id": "preview.unit", "version": 1, "schemaVersion": 1, "roleKey": roleKey, "level": "primary3", "title": "工程界面预览", "summary": "不进入正式题库", "scene": "界面检查", "estimatedMinutes": 2, "goalIds": ["preview.goal"], "beats": [], "questions": [question]]])
    }
    private var unavailable: BackendClientError { .api(code: "PREVIEW_ONLY", message: "这是界面预览，请登录后使用真实挑战。", requestID: nil, status: 400) }
    private func decode<T: Decodable>(_ object: [String: Any]) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
#endif
