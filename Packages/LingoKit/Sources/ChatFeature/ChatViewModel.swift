import CoreKit
import DesignSystem
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

    /// 本会话下一次出题的阈值（N=6±2，每次出题后重掷）。
    private var quizThreshold = QuizService.nextThreshold(random: Int.random(in: -2...2))

    /// 本会话「不再弹题」状态（供 UI 复选框读取）。
    public var conversationOptedOut: Bool { conversation?.quizOptOut ?? false }

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
        #if DEBUG
        if ProcessInfo.processInfo.environment["DEBUG_INJECT_QUIZ"] == "1" {
            if !messages.contains(where: { $0.speechReviewJSON != nil }) {
                await debugInjectSpeechReview()
            }
            if !messages.contains(where: { $0.quizJSON != nil }) {
                await debugInjectQuiz()
            }
        }
        #endif
    }

    /// 正在翻译中的消息（气泡下方转圈）。
    public private(set) var translatingMessageIDs: Set<UUID> = []

    /// 云端翻译失败（离线/报错）时的兜底翻译，由 ChatView 注入 Apple 端上翻译。
    public var translationFallback: (@MainActor (String) async -> String?)?

    /// 翻译整句并缓存到 translationZh（重复点击直接用缓存）。
    /// 正常走云端 LLM；离线或失败时回退 Apple 端上翻译（Translation 框架）。
    public func translate(message: MessageDTO) async {
        guard message.translationZh == nil, !translatingMessageIDs.contains(message.id) else { return }
        translatingMessageIDs.insert(message.id)
        defer { translatingMessageIDs.remove(message.id) }
        do {
            let translation = try await deps.translator.translateToChinese(message.text)
            try await deps.chatStore.setTranslation(messageID: message.id, translationZh: translation)
            await reloadMessages()
        } catch {
            // 云端失败 → Apple 端上翻译兜底；仍失败才报错。
            if let fallback = translationFallback, let local = await fallback(message.text) {
                try? await deps.chatStore.setTranslation(messageID: message.id, translationZh: local)
                await reloadMessages()
            } else {
                errorMessage = "翻译失败：\(error.localizedDescription)"
            }
        }
    }

    /// 收藏语句（带上已有翻译缓存）。
    public func favorite(message: MessageDTO) async {
        Haptics.impact(.light)
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
        Haptics.impact(.light)
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
        runSpeechReview(for: userMessage)
        await streamAssistantReply()
    }

    /// 后台口语点评（仅语音消息）：结果写 speechReviewJSON；超时/失败静默放弃（plan.md §2.8）。
    private func runSpeechReview(for message: MessageDTO) {
        let coach = CoachService(llm: deps.llm)
        let chatStore = deps.chatStore
        let transcript = message.text
        Task(priority: .utility) { [weak self] in
            guard !transcript.isEmpty,
                  let review = try? await coach.reviewSpeech(transcript: transcript),
                  let json = CoachService.encode(review) else { return }
            try? await chatStore.setSpeechReview(messageID: message.id, json: json)
            await self?.reloadMessages()
        }
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

    private var memoryService: MemoryService {
        MemoryService(
            llm: deps.llm,
            chatStore: deps.chatStore,
            memoryStore: deps.memoryStore,
            economyStore: deps.economyStore
        )
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

        // 注入分级记忆（long + short/mid）；原文窗口与记忆按订阅配额；主线机票未发放前附加引导
        let memoryService = self.memoryService
        let memorySections = await memoryService.memorySections(characterID: character.id)
        let rawWindow = await memoryService.quota().rawWindow
        let hasStoryTicket = (try? await deps.itemStore.hasTicket(source: .story)) ?? false
        let mainlineActive = character.isMainCharacter && !hasStoryTicket
        let quizRequested = await shouldRequestQuiz(conversationID: conversation.id)
        let request = PromptBuilder.roleplayRequest(
            card: character.card,
            difficulty: character.difficultyLevel,
            history: messages,
            memorySections: memorySections,
            guidance: mainlineActive ? PromptBuilder.mainlineGuidance : nil,
            quizRequested: quizRequested,
            rawWindow: rawWindow
        )

        var accumulated = ""
        do {
            for try await event in await deps.llm.stream(request) {
                if case .textDelta(let delta) = event {
                    accumulated += delta
                    streamingText = accumulated
                }
            }
            // 出题回合：从回复末尾截出 <quiz>，失败则静默按纯文本处理。
            let (replyText, quiz) = quizRequested
                ? QuizService.extract(from: accumulated)
                : (accumulated, nil)
            if quizRequested {
                streamingText = replyText // 让流式收尾不闪现 quiz 原文
            }
            let assistantMessage = try await persistAssistantMessage(
                conversationID: conversation.id, text: replyText, interrupted: false
            )
            if let assistantMessage, let quiz, let json = QuizService.encode(quiz) {
                try? await deps.chatStore.attachQuiz(
                    messageID: assistantMessage.id, quizJSON: json, conversationID: conversation.id
                )
                quizThreshold = QuizService.nextThreshold(random: Int.random(in: -2...2))
            } else if quizRequested {
                // 指令已发但没解析出 quiz：清零计数，避免每轮重复追加出题指令。
                try? await deps.chatStore.resetQuizCounter(conversationID: conversation.id)
                quizThreshold = QuizService.nextThreshold(random: Int.random(in: -2...2))
            }
            await grantMainlineTicketIfEligible(conversationID: conversation.id)
            // 回复完成后检查记忆压缩触发（后台，不阻塞 UI）
            let conversationID = conversation.id
            let characterName = character.card.name
            Task(priority: .utility) {
                await memoryService.compressIfNeeded(conversationID: conversationID, characterName: characterName)
            }
        } catch {
            Log.llm.error("流式回复失败：\(error)")
            if accumulated.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                // 已收增量落库并标记中断，气泡上提供重试。
                _ = try? await persistAssistantMessage(conversationID: conversation.id, text: accumulated, interrupted: true)
            }
        }
        await reloadMessages()
    }

    @discardableResult
    private func persistAssistantMessage(conversationID: UUID, text: String, interrupted: Bool) async throws -> MessageDTO? {
        guard !text.isEmpty else { return nil }
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
        return message
    }

    // MARK: - 语境出题（plan.md §3.8）

    /// 双开关都开、且距上次出题已达阈值 → 本回合请求出题。
    private func shouldRequestQuiz(conversationID: UUID) async -> Bool {
        let globallyEnabled = (try? await deps.economyStore.profile().quizGloballyEnabled) ?? true
        guard let conversation = try? await deps.chatStore.conversation(id: conversationID) else { return false }
        return QuizService.shouldRequestQuiz(
            globallyEnabled: globallyEnabled,
            conversationOptedOut: conversation.quizOptOut,
            turnsSinceQuiz: conversation.turnsSinceQuiz,
            threshold: quizThreshold
        )
    }

    /// 作答某道 quiz：本地判分、落库记录、答对奖励金币。
    public func answerQuiz(message: MessageDTO, chosenIndex: Int) async {
        guard message.quizChosenIndex == nil,
              let quiz = QuizService.decode(fromJSON: message.quizJSON),
              let optionsJSON = encodeOptions(quiz.options) else { return }
        try? await deps.chatStore.recordQuizAnswer(
            messageID: message.id,
            chosenIndex: chosenIndex,
            question: quiz.question,
            optionsJSON: optionsJSON,
            correctIndex: quiz.answer,
            characterName: character.card.name
        )
        if chosenIndex == quiz.answer {
            Haptics.notify(.success)
            // 只有服务端签发的题目挑战才能产生资产奖励；本地题目只记录学习结果。
        } else {
            Haptics.notify(.error)
        }
        await reloadMessages()
    }

    /// 本会话「不再弹题」开关。
    public func setQuizOptOut(_ optedOut: Bool) async {
        guard let conversation else { return }
        try? await deps.chatStore.setQuizOptOut(conversationID: conversation.id, optedOut: optedOut)
        self.conversation = try? await deps.chatStore.conversation(id: conversation.id)
    }

    private func encodeOptions(_ options: [String]) -> String? {
        guard let data = try? JSONEncoder().encode(options) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    #if DEBUG
    /// 模拟器/调试用：注入一条带口语点评的语音消息，验证口语点评 UI。
    public func debugInjectSpeechReview() async {
        guard let conversation else { return }
        let review = SpeechReview(
            rating: 4,
            commentZh: "说得挺清楚的，语气也自然！再注意一下连读会更地道。",
            tips: [.init(quote: "how to say", better: "how do you say", explanationZh: "口语里更常说 how do you say")]
        )
        guard let message = try? await deps.chatStore.appendMessage(
            conversationID: conversation.id,
            role: .user,
            kind: .voice,
            text: "how to say this word in english",
            audioFileName: nil,
            audioDuration: 3
        ), let json = CoachService.encode(review) else { return }
        try? await deps.chatStore.setSpeechReview(messageID: message.id, json: json)
        await reloadMessages()
    }

    /// 模拟器/调试用：直接注入一条带 quiz 的助手消息，验证出题 UI 全流程。
    public func debugInjectQuiz() async {
        guard let conversation else { return }
        let sample = Quiz(
            question: "Which word means \"very tired\"?",
            options: ["keen", "exhausted", "brave", "tidy"],
            answer: 1,
            explanationZh: "exhausted 表示筋疲力尽；keen 是热衷的、brave 是勇敢的、tidy 是整洁的。"
        )
        guard let message = try? await persistAssistantMessage(
            conversationID: conversation.id,
            text: "Honestly I'm knackered after that shift 😴",
            interrupted: false
        ), let json = QuizService.encode(sample) else { return }
        try? await deps.chatStore.attachQuiz(messageID: message.id, quizJSON: json, conversationID: conversation.id)
        await reloadMessages()
    }
    #endif

    /// 角色回复完成后本地词频标注关键词（划线可点，plan.md §3.8）。
    private func annotateKeywords(message: MessageDTO, text: String) async {
        let annotator = KeywordAnnotator(dictionary: deps.dictionary)
        let threshold = character.difficultyLevel.keywordFrequencyThreshold
        let words = await annotator.keywords(in: text, frequencyThreshold: threshold)
        guard let json = KeywordAnnotator.encode(words: words) else { return }
        try? await deps.chatStore.setKeywordRanges(messageID: message.id, json: json)
    }

    /// 主线奖励：与主角色对话满 3 轮且尚未发放过剧情机票 → 送 1 张通用机票（plan.md §3.6/1.10）。
    private func grantMainlineTicketIfEligible(conversationID: UUID) async {
        guard character.isMainCharacter else { return }
        guard let conversation = try? await deps.chatStore.conversation(id: conversationID),
              conversation.turnCount >= 3 else { return }
        guard (try? await deps.itemStore.hasTicket(source: .quest)) == false else { return }
        do {
            guard try await deps.progression.claimStarterTicket() else { return }
            _ = try await deps.chatStore.appendMessage(
                conversationID: conversationID,
                role: .coach,
                kind: .storyLine,
                text: "🎫 主办方送来一张通用机票！之后可以在地图里用它解锁新的城市。"
            )
        } catch {
            Log.app.warning("主线机票发放失败：\(error)")
        }
    }

    private func reloadMessages() async {
        guard let conversation else { return }
        messages = (try? await deps.chatStore.messages(conversationID: conversation.id)) ?? messages
    }
}
