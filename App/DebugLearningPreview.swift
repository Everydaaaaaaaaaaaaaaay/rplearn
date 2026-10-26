#if DEBUG
import BackendKit
import CryptoKit
import Foundation
import PersistenceKit
import UIKit

/// 仅免登录界面预览使用；显式场景可展示示例记录，不请求后端、不写账号或题库。
actor DebugLearningFillStore {
    static let shared = DebugLearningFillStore()
    private var filled: Set<UUID> = []
    func fill(_ id: UUID) { filled.insert(id) }
    func contains(_ id: UUID) -> Bool { filled.contains(id) }
}

actor DebugLearningDirectionStore {
    static let shared = DebugLearningDirectionStore()
    private var selected = ProcessInfo.processInfo.environment["UI_TEST_LEARNING_DIRECTION"] ?? "general"
    private var revision = 0
    private var receipts: [UUID: LearningDirections] = [:]
    func read() -> LearningDirections {
        .init(selectedDirection: selected, revision: revision, directions: [
            .init(id: "general", title: "通用英语", status: "available"),
            .init(id: "entrance-english-1", title: "考研英语一", status: "inReview"),
            .init(id: "entrance-english-2", title: "考研英语二", status: "inReview"),
            .init(id: "toefl-ibt-2026", title: "托福 iBT", status: "inReview"),
            .init(id: "ielts-academic", title: "雅思 Academic", status: "inReview")
        ])
    }
    func select(_ direction: String, requestID: UUID, expectedRevision: Int) throws -> LearningDirections {
        if let receipt = receipts[requestID] { return receipt }
        guard expectedRevision == revision else {
            throw BackendClientError.api(code: "LEARNING_DIRECTION_CONFLICT", message: "方向已更新，请重新选择。", requestID: nil, status: 409)
        }
        guard read().directions.contains(where: { $0.id == direction }) else { throw BackendClientError.invalidResponse }
        if selected != direction { selected = direction; revision += 1 }
        let receipt = read(); receipts[requestID] = receipt
        return receipt
    }
}

struct DebugLearningPreviewService: LearningServing, LearningDirectionServing, MainlineServing {
    let characterID: UUID
    let roleKey: String
    var profile: EconomyStore? = nil
    private var pageState: String { ProcessInfo.processInfo.environment["UI_TEST_LEARNING_PAGE_STATE"] ?? "empty" }
    private var previewRecordID: String { "20000000-0000-4000-8000-000000000001" }
    func learningDirections() async throws -> LearningDirections { await DebugLearningDirectionStore.shared.read() }
    func selectLearningDirection(_ direction: String, requestID: UUID, expectedRevision: Int) async throws -> LearningDirections {
        try await DebugLearningDirectionStore.shared.select(direction, requestID: requestID, expectedRevision: expectedRevision)
    }
    func learningCharacter(_ characterID: UUID) async throws -> BackendLearningCharacter {
        if pageState == "error" { throw BackendClientError.transport("学习数据暂时无法载入") }
        let filled = await DebugLearningFillStore.shared.contains(characterID)
        return try decode(["characterId": characterID.uuidString, "roleKey": roleKey, "cycleId": UUID().uuidString,
                    "characters": (filled || ["ready", "active", "preparing"].contains(pageState)) ? 1000 : 720,
                    "threshold": 1000, "revision": 1,
                    "activeAttemptId": pageState == "active" ? previewRecordID : NSNull(), "level": "primary3",
                    "availableUnits": 3, "generationStatus": pageState == "preparing" ? "running" : NSNull()])
    }
    func learningJourney() async throws -> LearningJourney {
        if ProcessInfo.processInfo.environment["UI_TEST_LEARNING_PROMOTION"] == "1" { return try await DebugLearningPromotionService.shared.journey() }
        let level = try await profile?.profile().difficultyLevel.rawValue ?? "primary3"
        return try decode(["currentLevel": level, "promotion": ["level": level, "nextLevel": NSNull(), "points": 0, "targetPoints": 540, "goals": [], "transferCompleted": false, "courseVersion": NSNull(), "courseHash": NSNull(), "ready": false, "completedPromotionId": NSNull(), "activePromotionId": NSNull(), "blockers": [["code": "course_unpublished", "message": "本级完整课程与进阶标准尚在准备，现有学习进度会保留。"]]], "policy": ["version": 1, "characterThreshold": 1000, "pointsPerQuestion": 1, "pointsPerStar": 60, "starsPerLevel": 9],
                    "levels": DifficultyLevel.allCases.map { ["level": $0.rawValue, "points": 0, "displayPoints": 0, "targetPoints": 540, "stars": 0, "currentStarPoints": 0, "pointsPerStar": 60, "publishedUnitCount": 0] as [String: Any] }])
    }
    func mainlineProgress() async throws -> BackendMainlineProgress {
        let cities = ["london", "capetown", "newyork", "melbourne", "singapore"]
        return try decode(["chapters": cities.enumerated().map { index, city in
            ["storyId": "mainline_\(city)", "regionId": city, "sequence": index + 1,
             "previousStoryId": index == 0 ? NSNull() : "mainline_\(cities[index - 1])",
             "state": index == 0 ? "available" : "locked", "lockReason": index == 0 ? NSNull() : "previousChapter"] as [String: Any]
        }])
    }
    func learningHistory(_ characterID: UUID, cursor: String?) async throws -> LearningHistory {
        guard ["records", "ready", "active", "preparing"].contains(pageState) else {
            return try decode(["items": [], "nextCursor": NSNull()])
        }
        let titles = ["综合练习 · 在书店挑选一本新书", "综合练习 · 周末集市询价与比较商品", "综合练习 · 问路前往车站"]
        let items: [[String: Any]] = titles.enumerated().map { index, title in
            ["id": index == 0 ? previewRecordID : "20000000-0000-4000-8000-00000000000\(index + 1)",
             "title": title, "level": index == 1 ? "junior3" : "primary3",
             "startedAt": ["2026-10-25T17:00:00Z", "2026-10-25T16:20:00Z", "2026-10-25T10:30:00Z"][index],
             "firstCompletedAt": index == 0 && pageState == "active" ? NSNull() : ["2026-10-25T17:10:00Z", "2026-10-25T16:30:00Z", "2026-10-25T10:40:00Z"][index],
             "correctCount": [2, 4, 6][index], "questionCount": 6, "earnedPoints": [2, 3, 0][index]]
        }
        return try decode(["items": items, "nextCursor": NSNull()])
    }
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
    func learningSpeech(_ attemptID: UUID, questionID: String, assetID: String) async throws -> LearningSpeechScript {
        if ProcessInfo.processInfo.environment["UI_TEST_LEARNING_AUDIO_FAILURE"] == "1" { throw unavailable }
        if let json = ProcessInfo.processInfo.environment["UI_TEST_LEARNING_SPEECH_JSON"] {
            let script = try JSONDecoder().decode(LearningSpeechScript.self, from: Data(json.utf8))
            guard script.assetId == assetID else { throw unavailable }
            return script
        }
        guard assetID == "preview.audio" else { throw unavailable }
        return LearningSpeechScript(assetId: assetID, segments: [.init(text: "Water, please.")])
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
              kind == "image" ? question.imageAssetIDs.contains(assetID) : question.audioAssetIDs.contains(assetID) else { throw unavailable }
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
            let showStory = ProcessInfo.processInfo.environment["UI_TEST_LEARNING_STORY"] == "1"
            let publicUnit = try JSONSerialization.jsonObject(with: JSONEncoder().encode(unit))
            return try decode(["id": UUID().uuidString, "characterId": characterID.uuidString,
                "level": unit.level, "revision": 1, "startedAt": "2026-09-26T00:00:00Z",
                "firstCompletedAt": showStory ? NSNull() : "2026-09-26T00:00:00Z", "correctQuestionIds": [],
                "round": ["id": UUID().uuidString, "ordinal": showStory ? 0 : 1,
                    "questionIds": showStory ? unit.questions.map(\.id) : [question.id], "completed": false, "answers": []],
                "unit": publicUnit])
        }
        let supported = ["choice", "arrange", "audioArrange", "matching", "completion", "listeningChoice", "dictation", "listeningCompletion", "cloze"]
        let type = supported.contains(kind) ? kind : "choice"
        var question: [String: Any] = ["id": "preview.question", "type": type, "goalId": "preview.goal",
            "instruction": "界面预览：完成这个练习", "prompt": "这是一道工程检查题，用于观察题干换行和操作区域，不计入学习记录。", "hint": "示例提示。",
            "options": [["id": "a", "text": "First option"], ["id": "b", "text": "Second option"]],
            "tokens": [["id": "i", "text": "I"], ["id": "would", "text": "would"], ["id": "like", "text": "like"], ["id": "to", "text": "to"], ["id": "read", "text": "read"], ["id": "books", "text": "books"]],
            "left": [["id": "l1", "text": "a book"], ["id": "l2", "text": "a pencil"], ["id": "l3", "text": "a bag"]],
            "right": [["id": "r1", "text": "一本书"], ["id": "r2", "text": "一个包"], ["id": "r3", "text": "一支铅笔"]]]
        if type == "cloze" {
            question["instruction"] = "选择词块，填入两空。"
            question["prompt"] = "工程交互检查，不进入正式题库。"
            question["passage"] = "First {first}.\nThen {second}."
            question["tokens"] = [["id": "a", "text": "one"], ["id": "b", "text": "two"], ["id": "c", "text": "three"]]
        }
        if ProcessInfo.processInfo.environment["UI_TEST_LEARNING_IMAGES"] == "1" {
            question["instruction"] = "图片选项 · 工程预览"
            question["prompt"] = type == "matching" ? "把两组相同的图形配对。此题只检查图片展示与操作，不进入正式题库。" : "请选择红色圆形。此题只检查图片展示与操作，不进入正式题库。"
            question["options"] = [["id": "a", "text": "红色圆形", "imageAssetId": "preview.red"], ["id": "b", "text": "蓝色方形", "imageAssetId": "preview.blue"]]
            question["left"] = [["id": "l1", "text": "红色圆形", "imageAssetId": "preview.red"], ["id": "l2", "text": "蓝色方形", "imageAssetId": "preview.blue"]]
            question["right"] = [["id": "r1", "text": "方形"], ["id": "r2", "text": "圆形"]]
        }
        if ["listeningChoice", "dictation", "audioArrange", "listeningCompletion"].contains(type) { question["audio"] = ["assetId": "preview.audio"] }
        if type == "listeningCompletion" {
            question["instruction"] = "听录音，补全笔记。"
            question["prompt"] = "Participants should bring ____."
            question["hint"] = "工程界面预览，不进入题库。"
            question["wordLimit"] = 2
        }
        let showStory = ProcessInfo.processInfo.environment["UI_TEST_LEARNING_STORY"] == "1"
        let beats: [[String: Any]] = showStory ? [
            ["id": "arrival", "afterQuestion": 0, "speaker": "旁白", "text": "A book falls open. A blue bookmark is inside.", "translation": "一本书翻开了，里面夹着一枚蓝色书签。"],
            ["id": "discovery", "afterQuestion": 0, "speaker": "同行者", "text": "Here it is! Thank you.", "translation": "原来在这里！谢谢你。"]
        ] : []
        return try decode(["id": UUID().uuidString, "characterId": characterID.uuidString, "level": "primary3", "revision": 1,
            "startedAt": "2026-09-26T00:00:00Z", "firstCompletedAt": showStory ? NSNull() : "2026-09-26T00:00:00Z", "correctQuestionIds": [],
            "round": ["id": UUID().uuidString, "ordinal": showStory ? 0 : 1, "questionIds": ["preview.question"], "completed": false, "answers": []],
            "unit": ["id": "preview.unit", "version": 1, "schemaVersion": 1, "roleKey": roleKey, "level": "primary3", "title": "工程界面预览", "summary": "不进入正式题库", "scene": "界面检查", "estimatedMinutes": 2, "goalIds": ["preview.goal"], "beats": beats, "questions": [question]]])
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
