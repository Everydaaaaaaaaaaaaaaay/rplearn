import CoreKit
import DomainKit
import Foundation
import LLMKit
import Observation
import PersistenceKit

/// 单个聊天页的状态与编排：发送 → 落库 → 流式回复 → 定稿。
@MainActor
@Observable
public final class ChatViewModel {
    public let character: CharacterDTO
    private let deps: ChatDependencies

    public private(set) var conversation: ConversationDTO?
    public private(set) var messages: [MessageDTO] = []
    /// 流式中的助手消息文本（尚未定稿）；nil 表示无进行中的回复。
    public private(set) var streamingText: String?
    public private(set) var isStreaming = false
    public var errorMessage: String?
    public var draft = ""

    private var streamingMessageID: UUID?

    public init(character: CharacterDTO, deps: ChatDependencies) {
        self.character = character
        self.deps = deps
    }

    public func load() async {
        do {
            let conversation = try await deps.chatStore.openConversation(characterID: character.id)
            self.conversation = conversation
            self.messages = try await deps.chatStore.messages(conversationID: conversation.id)
        } catch {
            errorMessage = "加载会话失败：\(error.localizedDescription)"
            Log.app.error("openConversation 失败：\(error)")
        }
    }

    public func sendDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        draft = ""
        await send(userText: text)
    }

    /// 重试：删除中断的助手消息并按当前历史重新请求。
    public func retryInterrupted(messageID: UUID) async {
        guard !isStreaming else { return }
        do {
            try await deps.chatStore.deleteMessage(messageID: messageID)
            await reloadMessages()
            await streamAssistantReply()
        } catch {
            errorMessage = "重试失败：\(error.localizedDescription)"
        }
    }

    private func send(userText: String) async {
        guard let conversation else { return }
        do {
            try await deps.chatStore.appendMessage(
                conversationID: conversation.id,
                role: .user,
                text: userText,
                tokenEstimate: TokenEstimator.estimate(userText)
            )
            await reloadMessages()
        } catch {
            errorMessage = "发送失败：\(error.localizedDescription)"
            return
        }
        await streamAssistantReply()
    }

    private func streamAssistantReply() async {
        guard let conversation else { return }
        isStreaming = true
        streamingText = ""
        errorMessage = nil
        defer {
            isStreaming = false
            streamingText = nil
            streamingMessageID = nil
        }

        let request = PromptBuilder.roleplayRequest(
            card: character.card,
            difficulty: character.difficultyLevel,
            history: messages
        )

        var accumulated = ""
        do {
            for try await event in await deps.llm.stream(request) {
                if case .textDelta(let delta) = event {
                    accumulated += delta
                    streamingText = accumulated
                }
            }
            try await persistAssistantMessage(conversationID: conversation.id, text: accumulated, interrupted: false)
        } catch {
            Log.llm.error("流式回复失败：\(error)")
            if accumulated.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                // 已收增量落库并标记中断，气泡上提供重试。
                try? await persistAssistantMessage(conversationID: conversation.id, text: accumulated, interrupted: true)
            }
        }
        await reloadMessages()
    }

    private func persistAssistantMessage(conversationID: UUID, text: String, interrupted: Bool) async throws {
        guard !text.isEmpty else { return }
        let message = try await deps.chatStore.appendMessage(
            conversationID: conversationID,
            role: .assistant,
            text: text,
            tokenEstimate: TokenEstimator.estimate(text)
        )
        if interrupted {
            try await deps.chatStore.updateMessageText(messageID: message.id, text: text, isInterrupted: true)
        }
    }

    private func reloadMessages() async {
        guard let conversation else { return }
        messages = (try? await deps.chatStore.messages(conversationID: conversation.id)) ?? messages
    }
}
