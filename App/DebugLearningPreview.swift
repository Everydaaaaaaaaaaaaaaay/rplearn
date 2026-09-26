#if DEBUG
import BackendKit
import CryptoKit
import Foundation
import PersistenceKit
import UIKit

/// 仅免登录界面预览使用，不请求后端，不写账号或题库；没有虚构挑战记录。
struct DebugLearningPreviewService: LearningServing, MainlineServing {
    let characterID: UUID
    let roleKey: String
    var profile: EconomyStore? = nil
    func learningCharacter(_ characterID: UUID) async throws -> BackendLearningCharacter {
        try decode(["characterId": characterID.uuidString, "roleKey": roleKey, "cycleId": UUID().uuidString,
                    "characters": 720, "threshold": 1000, "revision": 1, "activeAttemptId": NSNull(), "level": "primary3",
                    "availableUnits": 0, "generationStatus": NSNull()])
    }
    func learningJourney() async throws -> LearningJourney {
        if ProcessInfo.processInfo.environment["UI_TEST_LEARNING_PROMOTION"] == "1" { return try await DebugLearningPromotionService.shared.journey() }
        let level = try await profile?.profile().difficultyLevel.rawValue ?? "primary3"
        return try decode(["currentLevel": level, "promotion": ["level": level, "nextLevel": NSNull(), "points": 0, "targetPoints": 540, "goals": [], "transferCompleted": false, "courseVersion": NSNull(), "courseHash": NSNull(), "ready": false, "completedPromotionId": NSNull(), "activePromotionId": NSNull(), "blockers": [["code": "course_unpublished", "message": "本级完整课程与进阶标准尚在准备，现有学习进度会保留。"]]], "policy": ["version": 1, "characterThreshold": 1000, "pointsPerQuestion": 1, "pointsPerStar": 60, "starsPerLevel": 9],
                    "levels": DifficultyLevel.allCases.map { ["level": $0.rawValue, "points": 0, "displayPoints": 0, "targetPoints": 540, "stars": 0, "currentStarPoints": 0, "pointsPerStar": 60, "publishedUnitCount": 0] as [String: Any] }])
    }
    func mainlineProgress() async throws -> BackendMainlineProgress {
        let cities = ["london", "capetown", "newyork", "melbourne", "singapore"]
        let thresholds = [0, 3, 9, 18, 27]
        return try decode(["earnedStars": 0, "chapters": cities.enumerated().map { index, city in
            ["storyId": "mainline_\(city)", "regionId": city, "sequence": index + 1,
             "requiredStars": thresholds[index], "missingStars": thresholds[index],
             "previousStoryId": index == 0 ? NSNull() : "mainline_\(cities[index - 1])",
             "state": index == 0 ? "available" : "locked", "lockReason": index == 0 ? NSNull() : "previousChapter"] as [String: Any]
        }])
    }
    func learningHistory(_ characterID: UUID, cursor: String?) async throws -> LearningHistory { try decode(["items": [], "nextCursor": NSNull()]) }
    func learningAttempt(_ id: UUID) async throws -> LearningAttempt { throw unavailable }
    func startLearning(_ characterID: UUID, requestID: UUID) async throws -> LearningStart { throw unavailable }
    func answerLearning(_ id: UUID, command: LearningAnswerCommand) async throws -> LearningAnswerReceipt { throw unavailable }
    func finishLearning(_ attempt: LearningAttempt, requestID: UUID, skipRemaining: Bool) async throws -> LearningAttempt { throw unavailable }
    func retryLearning(_ attempt: LearningAttempt, requestID: UUID) async throws -> LearningAttempt { throw unavailable }
    func learningImage(_ attemptID: UUID, questionID: String, assetID: String) async throws -> Data {
        if let data = try localMedia(questionID: questionID, assetID: assetID, kind: "image", extension: "png") { return data }
        guard ProcessInfo.processInfo.environment["UI_TEST_LEARNING_IMAGES"] == "1",
              ["preview.red", "preview.blue"].contains(assetID) else { throw unavailable }
        if ProcessInfo.processInfo.environment["UI_TEST_LEARNING_IMAGE_FAILURE"] == "1",
           await DebugImageDownloadGate.shared.shouldFail(assetID) { throw unavailable }
        return await MainActor.run {
            UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).pngData { context in
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
                (assetID == "preview.red" ? UIColor.systemRed : UIColor.systemBlue).setFill()
                let rect = CGRect(x: 44, y: 44, width: 168, height: 168)
                if assetID == "preview.red" { context.cgContext.fillEllipse(in: rect) }
                else { context.fill(rect) }
            }
        }
    }
    func learningAudio(_ attemptID: UUID, questionID: String, assetID: String) async throws -> Data {
        if let data = try localMedia(questionID: questionID, assetID: assetID, kind: "audio", extension: "wav") { return data }
        guard assetID == "preview.audio",
              let url = Bundle.main.url(forResource: "learning-preview", withExtension: "wav") else { throw unavailable }
        if ProcessInfo.processInfo.environment["UI_TEST_LEARNING_AUDIO_FAILURE"] == "1" { throw unavailable }
        return try Data(contentsOf: url)
    }
    /// 仅离线 Debug：读取显式指定目录或应用文档目录，公开题面必须引用此内容摘要。
    private func localMedia(questionID: String, assetID: String, kind: String, extension suffix: String) throws -> Data? {
        guard ProcessInfo.processInfo.environment["UI_TEST_LEARNING_LOCAL_MEDIA"] == "1" else { return nil }
        guard let json = ProcessInfo.processInfo.environment["UI_TEST_LEARNING_UNIT_JSON"],
              assetID.range(of: "^" + kind + "\\.[a-f0-9]{64}$", options: .regularExpression) != nil else { throw unavailable }
        let unit = try JSONDecoder().decode(LearningUnit.self, from: Data(json.utf8))
        guard let question = unit.questions.first(where: { $0.id == questionID }),
              kind == "image" ? question.imageAssetIDs.contains(assetID) : question.audio?.assetId == assetID else { throw unavailable }
        let directory: URL
        if let path = ProcessInfo.processInfo.environment["UI_TEST_LEARNING_MEDIA_DIRECTORY"], path.hasPrefix("/") {
            directory = URL(fileURLWithPath: path, isDirectory: true).appending(path: kind == "image" ? "images" : "audio")
        } else {
            directory = URL.documentsDirectory.appending(path: "LearningPreviewMedia")
        }
        let url = directory.appending(path: assetID + "." + suffix)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= (kind == "image" ? 2_000_000 : 3_000_000) else { throw unavailable }
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard assetID == kind + "." + digest else { throw unavailable }
        return data
    }
    func previewAttempt(kind: String) throws -> LearningAttempt {
        if let json = ProcessInfo.processInfo.environment["UI_TEST_LEARNING_UNIT_JSON"] {
            // 只在免登录 Debug 预览中接收公开题面；不提供答案、不提交到服务端。
            let unit = try JSONDecoder().decode(LearningUnit.self, from: Data(json.utf8))
            let questionID = ProcessInfo.processInfo.environment["UI_TEST_LEARNING_QUESTION_ID"]
            guard let question = unit.questions.first(where: { question in
                if let questionID { return question.id == questionID }
                return question.type.rawValue == kind
            }) else { throw unavailable }
            let publicUnit = try JSONSerialization.jsonObject(with: JSONEncoder().encode(unit))
            return try decode(["id": UUID().uuidString, "characterId": characterID.uuidString,
                "level": unit.level, "revision": 1, "startedAt": "2026-09-26T00:00:00Z",
                "firstCompletedAt": "2026-09-26T00:00:00Z", "correctQuestionIds": [],
                "round": ["id": UUID().uuidString, "ordinal": 1, "questionIds": [question.id], "completed": false, "answers": []],
                "unit": publicUnit])
        }
        let supported = ["choice", "arrange", "matching", "completion", "listeningChoice", "dictation"]
        let type = supported.contains(kind) ? kind : "choice"
        var question: [String: Any] = ["id": "preview.question", "type": type, "goalId": "preview.goal",
            "instruction": "界面预览：完成这个练习", "prompt": "这是一道工程检查题，用于观察题干换行和操作区域，不计入学习记录。", "hint": "示例提示。",
            "options": [["id": "a", "text": "First option"], ["id": "b", "text": "Second option"]],
            "tokens": [["id": "i", "text": "I"], ["id": "would", "text": "would"], ["id": "like", "text": "like"], ["id": "to", "text": "to"], ["id": "read", "text": "read"], ["id": "books", "text": "books"]],
            "left": [["id": "l1", "text": "a book"], ["id": "l2", "text": "a pencil"], ["id": "l3", "text": "a bag"]],
            "right": [["id": "r1", "text": "一本书"], ["id": "r2", "text": "一个包"], ["id": "r3", "text": "一支铅笔"]]]
        if ProcessInfo.processInfo.environment["UI_TEST_LEARNING_IMAGES"] == "1" {
            question["instruction"] = "图片选项 · 工程预览"
            question["prompt"] = type == "matching" ? "把两组相同的图形配对。此题只检查图片展示与操作，不进入正式题库。" : "请选择红色圆形。此题只检查图片展示与操作，不进入正式题库。"
            question["options"] = [["id": "a", "text": "红色圆形", "imageAssetId": "preview.red"], ["id": "b", "text": "蓝色方形", "imageAssetId": "preview.blue"]]
            question["left"] = [["id": "l1", "text": "红色圆形", "imageAssetId": "preview.red"], ["id": "l2", "text": "蓝色方形", "imageAssetId": "preview.blue"]]
            question["right"] = [["id": "r1", "text": "方形"], ["id": "r2", "text": "圆形"]]
        }
        if ["listeningChoice", "dictation"].contains(type) { question["audio"] = ["assetId": "preview.audio"] }
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
private actor DebugImageDownloadGate {
    static let shared = DebugImageDownloadGate()
    private var attempted: Set<String> = []
    func shouldFail(_ id: String) -> Bool { attempted.insert(id).inserted }
}
#endif
