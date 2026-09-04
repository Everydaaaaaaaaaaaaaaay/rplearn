import CoreKit
import BackendKit
import DomainKit
import Foundation
import PersistenceKit
import SpeechKit

extension ChatViewModel {
    /// 从名册刷新备注、联系人偏好与人格成长等可变状态。
    public func refreshCharacter() async {
        guard let latest = try? await deps.rosterStore.character(id: character.id) else { return }
        character = latest
    }

    public func updateContactPreferences(_ preferences: ContactPreferences) async throws {
        try await deps.rosterStore.updateContactPreferences(
            characterID: character.id,
            preferences: preferences
        )
        await refreshCharacter()
    }

    public func setFavorite(_ isFavorite: Bool) async throws {
        try await deps.rosterStore.setFavorite(characterID: character.id, isFavorite: isFavorite)
        await refreshCharacter()
    }

    public func setPinned(_ isPinned: Bool) async throws {
        guard let conversation else { return }
        try await deps.chatStore.setPinned(conversationID: conversation.id, isPinned: isPinned)
        self.conversation = try await deps.chatStore.conversation(id: conversation.id)
        ConversationReadState.notifyChange()
    }

    public func searchHistory(_ query: String) async throws -> [ChatMessageSearchResultDTO] {
        try await deps.chatStore.searchMessageResults(
            characterID: character.id,
            query: query
        )
    }

    public func historyMessages(conversationID: UUID) async throws -> [MessageDTO] {
        try await deps.chatStore.messages(conversationID: conversationID)
    }

    public func setCharacterGrowthPaused(_ isPaused: Bool) async throws {
        try await deps.rosterStore.mutateGrowth(characterID: character.id) { snapshot in
            CharacterGrowthEngine.settingPaused(isPaused, in: snapshot)
        }
        await refreshCharacter()
    }

    public func removeCharacterGrowthArc(id: UUID) async throws {
        try await deps.rosterStore.mutateGrowth(characterID: character.id) { snapshot in
            CharacterGrowthEngine.removingArc(id: id, from: snapshot)
        }
        await refreshCharacter()
    }

    public func clearCharacterGrowth() async throws {
        try await deps.rosterStore.mutateGrowth(characterID: character.id) { snapshot in
            CharacterGrowthEngine.clearingGrowth(in: snapshot)
        }
        await refreshCharacter()
    }

    public func markConversationRead(at date: Date = .now) async {
        guard let conversation else { return }
        do {
            try await deps.chatStore.markRead(conversationID: conversation.id, at: date)
            self.conversation = try await deps.chatStore.conversation(id: conversation.id)
            ConversationReadState.notifyChange()
        } catch {
            Log.app.warning("标记会话已读失败：\(error.localizedDescription)")
        }
    }

    /// 清空聊天派生内容，但保留好友关系、共同剧情与人格成长。
    public func clearHistory() async throws {
        cancelPendingReply()
        let localVoiceFiles = try await deps.chatStore.clearConversationHistory(characterID: character.id)
        try await deps.memoryStore.deleteChatDerivedMemories(characterID: character.id)
        for fileName in localVoiceFiles {
            VoiceMessageStorage.delete(fileName: fileName)
        }
        await deps.voiceMedia.synchronize()
        messages = []
        guard var conversation else { return }
        conversation.turnCount = 0
        conversation.turnsSinceQuiz = 0
        conversation.lastSummarizedMessageIndex = 0
        conversation.lastMessageAt = conversation.createdAt
        self.conversation = conversation
    }

    /// 移除好友关系；聊天和共同经历仍保留，供“过往联系人”恢复。
    public func removeFriend() async throws {
        cancelPendingReply()
        try await deps.rosterStore.removeFriend(characterID: character.id)
        try? await deps.npcRegistry?.linkPublicNPC(
            npcID: character.id,
            localCharacterID: character.id,
            status: .removed
        )
        await refreshCharacter()
    }
}

enum ChatErrorPresentation {
    static func assistantReply(_ error: Error) -> String {
        if let appError = error as? AppError,
           case .keychain = appError {
            return "AI 服务暂时无法读取安全凭据，请重新启动应用后重试。"
        }
        return error.localizedDescription
    }
}
