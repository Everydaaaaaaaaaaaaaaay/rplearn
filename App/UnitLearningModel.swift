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
    private let client: BackendClient
    private let refreshProfile: @MainActor () async -> Void
    private let queueURL: URL
    private var queue: [MessageBody] = []
    private var flushing = false
    private var active = true
    private var flushTask: Task<Void, Never>?
    private var progressRevision: [UUID: Int] = [:]
    private var latestProgress: [UUID: UnitLearningProgress] = [:]
    private var profileRevision = 0
    private var appliedDifficulty: DifficultyLevel?
    private(set) var states: [UUID: UnitLearningState] = [:]
    private(set) var currentGrade: Int?
    private(set) var errors: [UUID: String] = [:]
    private(set) var busyCharacters: Set<UUID> = []
    private(set) var lastAnswer: (attemptID: UUID, questionID: String, correct: Bool, awarded: Bool, explanation: String?, levelAdvanced: Bool)?
    func pendingMessageCount(for characterID: UUID) -> Int {
        queue.count { $0.characterId == characterID }
    }

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
                let revisionAtSend = profileRevision
                let progress: UnitLearningProgress = try await client.send(
                    path: "/v1/learning/units/messages", method: "POST", body: first)
                guard active, !Task.isCancelled else { return }
                queue.removeFirst(); saveQueue()
                if profileRevision != revisionAtSend { continue }
                latestProgress[first.characterId] = progress
                progressRevision[first.characterId, default: 0] += 1
                if let old = states[first.characterId] {
                    states[first.characterId] = UnitLearningState(progress: progress, active: old.active, history: old.history)
                    errors[first.characterId] = nil
                }
                currentGrade = progress.grade
            } catch {
                guard active, !Task.isCancelled else { return }
                errors[first.characterId] = "聊天进度暂未同步，联网后重新打开学习页会继续上传。"
                return
            }
        }
    }

    func refresh(character: CharacterDTO) async {
        busyCharacters.insert(character.id)
        defer {
            busyCharacters.remove(character.id)
            scheduleFlush()
        }
        let revisionAtStart = progressRevision[character.id, default: 0]
        let profileAtStart = profileRevision
        do {
            let state: UnitLearningState = try await client.get(
                "/v1/learning/units/characters/\(character.id.uuidString)",
                queryItems: [URLQueryItem(name: "roleKey", value: Self.roleKey(for: character))])
            guard profileRevision == profileAtStart else { return }
            let progress = progressRevision[character.id, default: 0] == revisionAtStart
                ? state.progress : (latestProgress[character.id] ?? state.progress)
            states[character.id] = UnitLearningState(progress: progress, active: state.active, history: state.history)
            currentGrade = progress.grade
            if queue.isEmpty { errors[character.id] = nil }
        } catch {
            errors[character.id] = "学习记录暂时无法读取，请检查网络或登录状态。"
        }
    }

    #if DEBUG
    /// 开发构建的手动测试入口；使用当前账号的进度接口，不写入聊天记录。
    func debugFill(character: CharacterDTO) async -> Bool {
        guard active else { return false }
        busyCharacters.insert(character.id)
        defer { busyCharacters.remove(character.id) }
        do {
            let progress: UnitLearningProgress = try await client.send(
                path: "/v1/learning/units/messages", method: "POST",
                body: MessageBody(characterId: character.id, roleKey: Self.roleKey(for: character),
                                  messageId: UUID(), role: MessageRole.user.rawValue, characterCount: 1000))
            latestProgress[character.id] = progress
            progressRevision[character.id, default: 0] += 1
            if let old = states[character.id] {
                states[character.id] = UnitLearningState(progress: progress, active: old.active, history: old.history)
            } else {
                await refresh(character: character)
            }
            currentGrade = progress.grade
            errors[character.id] = nil
            return progress.ready
        } catch {
            errors[character.id] = "开发版填满挑战进度失败，请检查网络或登录状态。"
            return false
        }
    }
    #endif

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

    func applyProfileDifficulty(_ difficulty: DifficultyLevel) {
        let levels: [DifficultyLevel] = [.primary1, .primary2, .primary3, .primary4, .primary5, .primary6,
                                         .junior1, .junior2, .junior3, .senior1, .senior2, .senior3]
        let grade: Int
        if let index = levels.firstIndex(of: difficulty) {
            grade = index + 1
        } else {
            grade = [.undergraduate, .postgraduate, .advanced].contains(difficulty) ? 12 : 1
        }
        guard currentGrade != grade || appliedDifficulty != difficulty else { return }
        profileRevision += 1
        appliedDifficulty = difficulty
        currentGrade = grade
        states.removeAll()
        latestProgress.removeAll()
    }
}
