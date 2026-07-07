import CoreKit
import DomainKit
import Foundation
import LLMKit
import Observation
import PersistenceKit
import SpeechKit

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

    /// 正在翻译中的消息（气泡下方转圈）。
    public private(set) var translatingMessageIDs: Set<UUID> = []

    /// 翻译整句并缓存到 translationZh（重复点击直接用缓存）。
    public func translate(message: MessageDTO) async {
        guard message.translationZh == nil, !translatingMessageIDs.contains(message.id) else { return }
        translatingMessageIDs.insert(message.id)
        defer { translatingMessageIDs.remove(message.id) }
        do {
            let translation = try await deps.translator.translateToChinese(message.text)
            try await deps.chatStore.setTranslation(messageID: message.id, translationZh: translation)
            await reloadMessages()
        } catch {
            errorMessage = "翻译失败：\(error.localizedDescription)"
        }
    }

    /// 收藏语句（带上已有翻译缓存）。
    public func favorite(message: MessageDTO) async {
        let name = message.role == .user ? "我" : character.card.name
        _ = try? await deps.favorites.add(
            sentence: message.text,
            sourceMessageID: message.id,
            characterName: name,
            translationZh: message.translationZh
        )
    }

    /// 播放消息音频（按角色国籍口音）。
    public func speak(message: MessageDTO) async {
        let language = AccentMapper.language(forNationality: character.card.nationality)
        await deps.speech.speak(message.text, language: language)
    }

    public func sendDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        draft = ""
        await send(userText: text)
    }

    /// 发送语音消息：气泡为语音条，发给 LLM 的是转写文本，同样走教练审核（plan.md §3.2）。
    public func sendVoice(capture: VoiceRecorder.Capture) async {
        guard let conversation, !isStreaming else { return }
        let userMessage: MessageDTO
        do {
            userMessage = try await deps.chatStore.appendMessage(
                conversationID: conversation.id,
                role: .user,
                kind: .voice,
                text: capture.transcript,
                audioFileName: capture.fileName,
                audioDuration: capture.duration,
                tokenEstimate: TokenEstimator.estimate(capture.transcript)
            )
            await reloadMessages()
        } catch {
            errorMessage = "发送失败：\(error.localizedDescription)"
            return
        }
        runCoachReview(for: userMessage)
        await streamAssistantReply()
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
        let userMessage: MessageDTO
        do {
            userMessage = try await deps.chatStore.appendMessage(
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
        // 教练审核与主链路并行，互不阻塞（plan.md §3.4）。
        runCoachReview(for: userMessage)
        await streamAssistantReply()
    }

    /// 后台教练审核：结果写 coachReviewJSON；超时/失败静默放弃。
    private func runCoachReview(for message: MessageDTO) {
        let coach = CoachService(llm: deps.llm)
        let chatStore = deps.chatStore
        Task(priority: .utility) { [weak self] in
            guard let review = try? await coach.review(userText: message.text) else { return }
            guard review.hasIssues, let json = CoachService.encode(review) else { return }
            try? await chatStore.setCoachReview(messageID: message.id, json: json)
            await self?.reloadMessages()
        }
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
        await annotateKeywords(message: message, text: text)
    }

    /// 角色回复完成后本地词频标注关键词（划线可点，plan.md §3.8）。
    private func annotateKeywords(message: MessageDTO, text: String) async {
        let annotator = KeywordAnnotator(dictionary: deps.dictionary)
        let threshold = character.difficultyLevel.keywordFrequencyThreshold
        let words = await annotator.keywords(in: text, frequencyThreshold: threshold)
        guard let json = KeywordAnnotator.encode(words: words) else { return }
        try? await deps.chatStore.setKeywordRanges(messageID: message.id, json: json)
    }

    private func reloadMessages() async {
        guard let conversation else { return }
        messages = (try? await deps.chatStore.messages(conversationID: conversation.id)) ?? messages
    }
}
