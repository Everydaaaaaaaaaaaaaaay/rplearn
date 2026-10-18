#if DEBUG
import BackendKit
import Foundation
import Observation
import PersistenceKit

/// 开始入口只略过聊天字数等待；挑战、媒体、判分与奖励全部交给原服务。
@MainActor @Observable
public final class LearningTrialModel {
    public static let levels = DifficultyLevel.allCases.filter { $0 != .kindergarten }
    public private(set) var journey: LearningJourney?
    public private(set) var character: BackendLearningCharacter?
    public private(set) var activeAttempt: LearningAttempt?
    public private(set) var isBusy = false
    public private(set) var error: String?
    public private(set) var notice: String?
    public var presentedAttempt: LearningAttempt?
    public var selectedLevel: DifficultyLevel = .primary3
    private var loadedInitialLevel = false
    private let service: any LearningServing & LearningDirectionServing
    private let changeLevel: @Sendable (DifficultyLevel) async throws -> Void
    private let fillCycle: @Sendable (UUID, UUID, UUID) async throws -> Void
    private var startRequest: (characterID: UUID, id: UUID)?

    public init(service: any LearningServing & LearningDirectionServing,
                changeLevel: @escaping @Sendable (DifficultyLevel) async throws -> Void,
                fillCycle: @escaping @Sendable (UUID, UUID, UUID) async throws -> Void) {
        self.service = service; self.changeLevel = changeLevel; self.fillCycle = fillCycle
    }

    public func load(characterID: UUID?) async {
        guard !isBusy else { return }
        isBusy = true; error = nil; character = nil; activeAttempt = nil
        defer { isBusy = false }
        do {
            journey = try await service.learningJourney()
            if !loadedInitialLevel, let raw = journey?.currentLevel,
               let level = DifficultyLevel(rawValue: raw), Self.levels.contains(level) {
                selectedLevel = level; loadedInitialLevel = true
            }
            if let characterID {
                character = try await service.learningCharacter(characterID)
                if let id = character?.activeAttemptId { activeAttempt = try await service.learningAttempt(id) }
            }
        } catch { self.error = error.localizedDescription }
    }

    public func start(characterID: UUID) async {
        guard !isBusy, Self.levels.contains(selectedLevel) else { return }
        let target = selectedLevel
        isBusy = true; error = nil; notice = nil
        defer { isBusy = false }
        do {
            // 每次操作重新查权威状态，不凭页面旧数量或本地选择制造可用挑战。
            let current = try await service.learningJourney()
            journey = current
            let state = try await service.learningCharacter(characterID)
            character = state
            if let id = state.activeAttemptId {
                let attempt = try await service.learningAttempt(id)
                activeAttempt = attempt
                guard attempt.level == target.rawValue else {
                    notice = "这位旅伴还有\(learningLevelName(attempt.level))的挑战。请先继续该挑战，或换一位旅伴。"
                    return
                }
                presentedAttempt = attempt
                return
            }
            activeAttempt = nil
            guard let progress = current.levels.first(where: { $0.level == target.rawValue }) else {
                throw TrialError("服务器暂未提供这个档位的题库状态，请刷新后重试。")
            }
            guard progress.publishedUnitCount != 0 else {
                notice = "这个档位当前没有已发布练习；账号档位没有改变。"
                return
            }
            let directions = try await service.learningDirections()
            guard directions.directions.contains(where: { $0.id == "general" && $0.status == "available" }) else {
                throw TrialError("通用英语暂不可用，请稍后重试。")
            }
            if directions.selectedDirection != "general" {
                _ = try await service.selectLearningDirection("general", requestID: UUID(), expectedRevision: directions.revision)
            }
            if current.currentLevel != target.rawValue {
                try await changeLevel(target)
                journey = try await service.learningJourney()
                guard journey?.currentLevel == target.rawValue else {
                    throw TrialError("服务器尚未确认档位切换，没有开始新挑战。请刷新后重试。")
                }
            }
            if state.characters < state.threshold {
                try await fillCycle(characterID, state.cycleId, UUID())
            }
            let request: UUID
            if let previous = startRequest, previous.characterID == characterID { request = previous.id }
            else { request = UUID(); startRequest = (characterID, request) }
            let result = try await service.startLearning(characterID, requestID: request)
            startRequest = nil
            if let attempt = result.attempt {
                guard attempt.characterId == characterID else { throw BackendClientError.invalidResponse }
                activeAttempt = attempt
                guard attempt.level == target.rawValue && attempt.unit.level == target.rawValue else {
                    notice = "服务器返回了已存在的\(learningLevelName(attempt.level))挑战。可从下方继续，未将它标成所选档位。"
                    return
                }
                presentedAttempt = attempt
            } else if result.status == "preparing" {
                notice = "当前档位暂时没有可用的新练习，可能已用完当前题库。可以换旅伴、换档位或稍后再试。"
            } else { throw TrialError("服务器没有返回可用挑战，请刷新后重试。") }
        } catch {
            self.error = error.localizedDescription
            // 档位写入或创建响应可能丢失；刷新状态，不伪造成功，也不回写旧档位。
            if let latest = try? await service.learningJourney() { journey = latest }
            if let latest = try? await service.learningCharacter(characterID) {
                character = latest
                if let id = latest.activeAttemptId { activeAttempt = try? await service.learningAttempt(id) }
            }
        }
    }

    public func resume() async {
        guard !isBusy, let id = activeAttempt?.id else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        do { presentedAttempt = try await service.learningAttempt(id) }
        catch { self.error = error.localizedDescription }
    }
}

private struct TrialError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
#endif
