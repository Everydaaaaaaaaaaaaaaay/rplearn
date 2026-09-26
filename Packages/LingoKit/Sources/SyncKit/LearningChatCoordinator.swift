import BackendKit
import CoreKit
import DomainKit
import Foundation
import PersistenceKit

/// 每个账号持有自己的周期缓存；缓存不含正文、答案或可自行累加的分数。
public actor LearningChatCoordinator: LearningChatTracking {
    private let accountID: UUID
    private let backend: BackendClient
    private let contentSync: BackendContentSyncCoordinator
    private let defaults: UserDefaults
    private var revisions: [UUID: Int] = [:]
    private var active = true

    public init(accountID: UUID, backend: BackendClient, contentSync: BackendContentSyncCoordinator,
                defaultsSuiteName: String? = nil) {
        self.accountID = accountID; self.backend = backend; self.contentSync = contentSync
        self.defaults = defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
    private func key(_ characterID: UUID) -> String {
        "learning.chat.cycle.\(accountID.uuidString.lowercased()).\(characterID.uuidString.lowercased())"
    }
    private func ownsSession() async -> Bool {
        guard active else { return false }
        return (try? await backend.cachedIdentity()?.userID) == accountID
    }
    public func deactivate() { active = false }

    public func refresh(characterID: UUID) async {
        guard await ownsSession() else { return }
        do {
            try await contentSync.synchronizeAndWait()
            guard await ownsSession() else { return }
            let state = try await backend.learningCharacter(characterID)
            guard await ownsSession(), state.characterId == characterID else { return }
            guard state.revision >= revisions[characterID, default: 0] else { return }
            revisions[characterID] = state.revision
            defaults.set(state.cycleId.uuidString, forKey: key(characterID))
        } catch {
            // 断网保留原周期；离线消息不能猜测新的周期。
        }
    }
    public func userOrigin(characterID: UUID) async -> LearningChatOrigin? {
        guard await ownsSession() else { return nil }
        if defaults.string(forKey: key(characterID)) == nil { await refresh(characterID: characterID) }
        guard await ownsSession(), let value = defaults.string(forKey: key(characterID)),
              let cycle = UUID(uuidString: value) else { return nil }
        return .user(cycleID: cycle)
    }
    public func prepareReply(conversationID: UUID, userMessage: MessageDTO) async throws -> LearningChatContext? {
        guard await ownsSession(), case .user(let cycleID) = userMessage.learningOrigin else { return nil }
        try await contentSync.synchronizeAndWait()
        guard await ownsSession() else { throw CancellationError() }
        return LearningChatContext(conversationID: conversationID, userMessageID: userMessage.id, cycleID: cycleID)
    }
    public func messageSaved(characterID: UUID) async {
        await refresh(characterID: characterID)
    }
}
