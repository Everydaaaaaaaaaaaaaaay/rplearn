import BackendKit
import Foundation
import Observation
import PersistenceKit

struct UnitLearningProgress: Decodable, Sendable {
    let grade: Int
    let gradeCorrect: Int
    let stars: Int
    let correctPerStar: Int
    let starsPerGrade: Int
    let gradeTarget: Int
    let completedLevels: Int
    let chatCharacters: Int
    let challengeLength: Int
    let ready: Bool
}

struct UnitLearningSceneBeat: Decodable, Sendable {
    let speaker: String
    let english: String
    let chinese: String
}

struct UnitLearningQuestion: Decodable, Identifiable, Sendable {
    let id: String
    let kind: String
    let prompt: String
    let options: [String]
}

struct UnitLearningTemplate: Decodable, Sendable {
    let id: String
    let title: String
    let objective: String
    let grade: Int
    let scene: [UnitLearningSceneBeat]
    let questions: [UnitLearningQuestion]
}

struct UnitLearningAttempt: Decodable, Identifiable, Sendable {
    let id: UUID
    let grade: Int
    let startedAt: String
    let completedAt: String?
    let template: UnitLearningTemplate
    let answers: [String: String]
    let correctQuestionIds: [String]
    let correctCount: Int
    let questionCount: Int
}

struct UnitLearningState: Decodable, Sendable {
    let progress: UnitLearningProgress
    let active: UnitLearningAttempt?
    let history: [UnitLearningAttempt]
}

private struct UnitLearningAnswerResponse: Decodable, Sendable {
    let correct: Bool
    let newlyCorrect: Bool
    let awarded: Bool
    let completed: Bool
    let levelAdvanced: Bool
    let explanation: String?
    let correctAnswer: String?
    let state: UnitLearningState
}

@MainActor @Observable
final class UnitLearningModel {
    private struct MessageBody: Codable, Sendable {
        let characterId: UUID
        let roleKey: String
        let messageId: UUID
        let role: String
        let characterCount: Int
    }
    private struct StartBody: Encodable, Sendable { let characterId: UUID; let roleKey: String }
    private struct AnswerBody: Encodable, Sendable { let attemptId: UUID; let questionId: String; let answer: String }
    private struct LevelBody: Encodable, Sendable { let characterId: UUID; let roleKey: String; let grade: Int; let acknowledge: Bool }
    private let client: BackendClient
    private let refreshProfile: @MainActor () async -> Void
    private let queueURL: URL
    private var queue: [MessageBody] = []
    private var flushing = false
    private var active = true
    private var flushTask: Task<Void, Never>?
    private(set) var states: [UUID: UnitLearningState] = [:]
    private(set) var currentGrade: Int?
    private(set) var errors: [UUID: String] = [:]
    private(set) var busyCharacters: Set<UUID> = []
    private(set) var lastAnswer: (attemptID: UUID, questionID: String, correct: Bool, awarded: Bool, explanation: String?, levelAdvanced: Bool)?

    init(owner: UUID, client: BackendClient, refreshProfile: @escaping @MainActor () async -> Void) {
        self.client = client
        self.refreshProfile = refreshProfile
        queueURL = URL.applicationSupportDirectory
            .appendingPathComponent("UnitLearning-v1/\(owner.uuidString).json")
        if let data = try? Data(contentsOf: queueURL),
           let saved = try? JSONDecoder().decode([MessageBody].self, from: data) {
            queue = saved
        }
        scheduleFlush()
    }

    static func roleKey(for character: CharacterDTO) -> String {
        guard character.isMainCharacter else { return "other" }
        switch character.card.avatarAssetName {
        case "avatar_oliver": return "oliver"
        case "avatar_ruby": return "ruby"
        case "avatar_marcus": return "marcus"
        default: return "other"
        }
    }

    func record(character: UUID, roleKey: String, message: UUID, role: MessageRole, text: String) {
        guard active, role == .user || role == .assistant,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !queue.contains(where: { $0.messageId == message }) else { return }
        queue.append(MessageBody(characterId: character, roleKey: roleKey,
                                 messageId: message, role: role.rawValue, characterCount: min(text.count, 4000)))
        saveQueue()
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard active, flushTask == nil else { return }
        flushTask = Task {
            await flush()
            flushTask = nil
        }
    }

    func deactivate() {
        active = false
        flushTask?.cancel()
        flushTask = nil
    }

    private func saveQueue() {
        do {
            try FileManager.default.createDirectory(at: queueURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(queue).write(to: queueURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch {
            // 原始消息仍在 ChatStore；同步失败不会改写挑战分数。
        }
    }

    private func flush() async {
        while flushing && active {
            try? await Task.sleep(for: .milliseconds(30))
        }
        guard active, !Task.isCancelled else { return }
        flushing = true
        defer { flushing = false }
        while active && !Task.isCancelled, let first = queue.first {
            do {
                let progress: UnitLearningProgress = try await client.send(
                    path: "/v1/learning/units/messages", method: "POST", body: first)
                guard active, !Task.isCancelled else { return }
                queue.removeFirst(); saveQueue()
                if let old = states[first.characterId] {
                    states[first.characterId] = UnitLearningState(progress: progress, active: old.active, history: old.history)
                }
                currentGrade = progress.grade
                errors[first.characterId] = nil
            } catch {
                guard active, !Task.isCancelled else { return }
                errors[first.characterId] = "聊天进度暂未同步，联网后重新打开学习页会继续上传。"
                return
            }
        }
    }

    func refresh(character: CharacterDTO) async {
        busyCharacters.insert(character.id)
        defer { busyCharacters.remove(character.id) }
        await flush()
        do {
            let state: UnitLearningState = try await client.get(
                "/v1/learning/units/characters/\(character.id.uuidString)",
                queryItems: [URLQueryItem(name: "roleKey", value: Self.roleKey(for: character))])
            states[character.id] = state
            currentGrade = state.progress.grade
            if queue.isEmpty { errors[character.id] = nil }
        } catch {
            errors[character.id] = "学习记录暂时无法读取，请检查网络或登录状态。"
        }
    }

    func start(character: CharacterDTO) async {
        busyCharacters.insert(character.id)
        defer { busyCharacters.remove(character.id) }
        await flush()
        do {
            let state: UnitLearningState = try await client.send(
                path: "/v1/learning/units/start", method: "POST",
                body: StartBody(characterId: character.id, roleKey: Self.roleKey(for: character)))
            states[character.id] = state
            currentGrade = state.progress.grade
            errors[character.id] = nil
        } catch let error as BackendClientError where error.code == "UNIT_POOL_EXHAUSTED" {
            errors[character.id] = "这个年级的新单元正在补充，聊天进度已保留。"
        } catch {
            errors[character.id] = "开启单元挑战失败，请稍后重试。"
        }
    }

    func answer(character: CharacterDTO, attemptID: UUID, questionID: String, text: String) async {
        busyCharacters.insert(character.id)
        defer { busyCharacters.remove(character.id) }
        do {
            let result: UnitLearningAnswerResponse = try await client.send(
                path: "/v1/learning/units/answer", method: "POST",
                body: AnswerBody(attemptId: attemptID, questionId: questionID, answer: text))
            states[character.id] = result.state
            currentGrade = result.state.progress.grade
            lastAnswer = (attemptID, questionID, result.correct, result.awarded, result.explanation, result.levelAdvanced)
            errors[character.id] = nil
            if result.levelAdvanced { await refreshProfile() }
        } catch {
            errors[character.id] = "答案未提交成功，请重试；不会重复增加进度。"
        }
    }

    func changeGrade(character: CharacterDTO, to grade: Int) async {
        busyCharacters.insert(character.id)
        defer { busyCharacters.remove(character.id) }
        do {
            let state: UnitLearningState = try await client.send(
                path: "/v1/learning/units/level", method: "POST",
                body: LevelBody(characterId: character.id, roleKey: Self.roleKey(for: character),
                                grade: grade, acknowledge: true))
            states[character.id] = state
            currentGrade = state.progress.grade
            errors[character.id] = nil
            await refreshProfile()
        } catch {
            errors[character.id] = "水平调整失败，请检查网络后重试。"
        }
    }
}
