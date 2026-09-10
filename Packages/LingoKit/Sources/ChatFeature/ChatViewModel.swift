import CoreKit
import DesignSystem
import DomainKit
import Foundation
import LLMKit
import MediaKit
import Observation
import PersistenceKit
import RealtimeVoiceKit
import SpeechKit

/// 单个聊天页的状态与编排：发送 → 落库 → 流式回复 → 定稿。
@MainActor
@Observable
public final class ChatViewModel {
    private static let minimumVisibleTypingDuration: TimeInterval = 0.9

    public internal(set) var character: CharacterDTO
    public internal(set) var learnerDifficulty: DifficultyLevel
    let deps: ChatDependencies

    public internal(set) var conversation: ConversationDTO?
    public internal(set) var messages: [MessageDTO] = []
    /// 角色已经进入可见输入阶段；空字符串显示输入指示，nil 表示当前没有回复。
    public private(set) var streamingText: String?
    public private(set) var isStreaming = false
    /// 已收到用户消息，仍处于注意、准备或等待连续消息阶段；此时不显示“正在输入”。
    public private(set) var isWaitingForUserBurst = false
    public var errorMessage: String?
    public var draft = ""

    private var replyTask: Task<Void, Never>?
    private var replyCycleID = UUID()
    private var pendingReplyPlan: NPCReplyPlan?
    private var typingBeganAt: Date?
    private let replyOwnerID = UUID()
    var retryingMessageID: UUID?

    /// 本会话下一次出题的阈值（N=6±2，每次出题后重掷）。
    private var quizThreshold = QuizService.nextThreshold(random: Int.random(in: -2...2))

    /// 本会话「不再弹题」状态（供 UI 复选框读取）。
    public var conversationOptedOut: Bool { conversation?.quizOptOut ?? false }

    public init(character: CharacterDTO, deps: ChatDependencies) {
        self.character = character
        self.learnerDifficulty = character.difficultyLevel
        self.deps = deps
    }

    public func load() async {
        await refreshCharacter()
        do {
            let conversation = try await deps.chatStore.openConversation(characterID: character.id)
            self.conversation = conversation
            self.messages = try await deps.chatStore.messages(conversationID: conversation.id)
            if let profile = try? await deps.economyStore.profile() {
                learnerDifficulty = profile.difficultyLevel
            }
            resumePendingReplyIfNeeded()
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

    /// 播放消息音频（按角色国籍口音）。
    public func speak(message: MessageDTO) async {
        let language = AccentMapper.language(forNationality: character.card.nationality)
        await deps.speech.speak(
            SpeechRequest(
                text: message.text,
                language: language,
                purpose: .characterDialogue,
                voiceHint: SpeechVoiceHint(
                    stableID: character.id.uuidString.lowercased(),
                    gender: character.card.gender.rawValue,
                    nationality: character.card.nationality
                )
            )
        )
    }

    public func sendDraft() async {
        let originalDraft = draft
        let text = originalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Haptics.impact(.light)
        draft = ""
        if !(await send(userText: text)), draft.isEmpty {
            // Preserve failed input without overwriting anything typed while saving.
            draft = originalDraft
        }
    }

    /// 发送语音消息：气泡为语音条，发给 LLM 的是转写文本，同样走教练审核。
    public func sendVoice(capture: VoiceRecorder.Capture) async {
        guard let conversation else { return }
        let userMessage: MessageDTO
        let messageID = UUID()
        do {
            userMessage = try await deps.chatStore.appendMessage(
                messageID: messageID,
                conversationID: conversation.id,
                role: .user,
                kind: .voice,
                text: capture.transcript,
                audioFileName: capture.fileName,
                audioDuration: capture.duration,
                tokenEstimate: TokenEstimator.estimate(capture.transcript)
            )
            if let sourceFileName = capture.fileName {
                // 语音发送是常用本地能力；仅在账号云空间已激活时追加备份。
                if await deps.voiceMedia.isCloudBackupAvailable {
                    do {
                        _ = try await deps.voiceMedia.enqueue(
                            messageID: messageID,
                            sourceFileName: sourceFileName
                        )
                    } catch {
                        errorMessage = "语音已保存在本机，云端备份暂未完成。"
                        Log.app.warning("语音云端排队失败：\(String(describing: type(of: error)))")
                    }
                }
            }
            await reloadMessages()
            notifyConversationChanged()
        } catch {
            errorMessage = "发送失败：\(error.localizedDescription)"
            return
        }
        scheduleAssistantReply(after: capture.transcript, userMessage: userMessage)
    }

    /// 实时语音回合：端侧终稿只发送为文本，并继续复用当前低成本流式 LLM。
    /// 该方法先持久化用户话轮，再返回纯文本增量；应用不向 LLM 上传音频。
    var voiceLeaseID: UUID?

    public func realtimeReplyStream(
        userText: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard let conversation else {
            throw AppError.storage("聊天尚未加载")
        }
        let text = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AppError.storage("语音转写为空")
        }

        let userMessage = try await deps.chatStore.appendMessage(
            conversationID: conversation.id,
            role: .user,
            text: text,
            tokenEstimate: TokenEstimator.estimate(text)
        )
        messages.append(userMessage)
        messages.sort { $0.orderIndex < $1.orderIndex }
        notifyConversationChanged()

        try Task.checkCancellation()
        var request = await makeRoleplayRequest(quizRequested: false, voiceMode: true)
        try Task.checkCancellation()
        request.voiceLeaseID = voiceLeaseID
        let upstream = await deps.llm.stream(request)
        return AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                defer { self?.runInteractionReview(for: userMessage, source: .voiceChat) }
                do {
                    for try await event in upstream {
                        try Task.checkCancellation()
                        if case .textDelta(let delta) = event, !delta.isEmpty {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 保存模型实际生成的语音字幕；被用户插话截断时保留中断标记。
    public func saveRealtimeAssistant(spokenText: String, interrupted: Bool) async {
        guard let conversation else { return }
        let spokenText = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spokenText.isEmpty else { return }
        do {
            _ = try await persistAssistantReply(
                conversationID: conversation.id,
                text: spokenText,
                interrupted: interrupted
            )
            await grantMainlineTicketIfEligible(conversationID: conversation.id)
            await reloadMessages()
            notifyConversationChanged()

            let memoryService = self.memoryService
            let conversationID = conversation.id
            let characterName = character.card.name
            let characterRegionID = character.card.regionID
            Task(priority: .utility) {
                await memoryService.compressIfNeeded(
                    conversationID: conversationID,
                    characterName: characterName,
                    characterRegionID: characterRegionID
                )
            }
        } catch {
            Log.app.warning("实时语音回复保存失败：\(error.localizedDescription)")
        }
    }

    public func refreshMessages() async { await reloadMessages() }

    public func presence(at date: Date) -> NPCPresenceSnapshot {
        NPCAttentionPolicy.standard.presence(
            for: character,
            at: date,
            lastAssistantMessageAt: messages.last(where: { $0.role == .assistant })?.createdAt,
            pendingReplyPlan: pendingReplyPlan
        )
    }

    public func cancelPendingReply() {
        replyTask?.cancel()
        replyTask = nil
        replyCycleID = UUID()
        pendingReplyPlan = nil
        typingBeganAt = nil
        retryingMessageID = nil
        isWaitingForUserBurst = false
        isStreaming = false
        streamingText = nil
    }

    public func localVoiceFile(for message: MessageDTO) async -> String? {
        do {
            let fileName = try await deps.voiceMedia.localFile(
                messageID: message.id,
                assetID: message.audioAssetID,
                existingFileName: message.audioFileName
            )
            await reloadMessages()
            return fileName
        } catch {
            Log.app.warning("语音文件获取失败：\(String(describing: type(of: error)))")
            errorMessage = "语音下载失败，请稍后重试。"
            return nil
        }
    }

    /// 后台口语点评（仅语音消息）：结果写 speechReviewJSON；超时/失败静默放弃。
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

    /// 重试成功后才删除旧中断消息；失败时仍保留用户已收到的内容。
    public func retryInterrupted(messageID: UUID) async {
        guard !isStreaming, !isWaitingForUserBurst,
              messages.contains(where: { $0.id == messageID && $0.role == .assistant && $0.isInterrupted })
        else { return }
        scheduleAssistantReply(after: "", preferredDelay: 0.45, replacing: messageID)
    }

    private func send(userText: String) async -> Bool {
        guard let conversation else {
            errorMessage = "聊天尚未加载，请稍后重试。"
            return false
        }
        let userMessage: MessageDTO
        do {
            userMessage = try await deps.chatStore.appendMessage(
                conversationID: conversation.id,
                role: .user,
                text: userText,
                tokenEstimate: TokenEstimator.estimate(userText)
            )
            await reloadMessages()
            notifyConversationChanged()
        } catch {
            errorMessage = "发送失败：\(error.localizedDescription)"
            return false
        }
        // 辅助点评必须等主回复完成：免费额度下不能让后台任务抢走用户可见回复的预留。
        scheduleAssistantReply(after: userText, userMessage: userMessage)
        return true
    }

    /// 一次后台调用同时完成语言点评与关系信号分析，避免每条消息额外消耗一轮模型请求。
    private func runInteractionReview(
        for message: MessageDTO,
        source: RelationshipEventRecord.Source
    ) {
        let relationship = RelationshipService(llm: deps.llm, rosterStore: deps.rosterStore)
        let chatStore = deps.chatStore
        let character = character
        // 点评延后到主回复之后执行，但输入语境必须停在这条用户消息，不能把后生成的回复倒灌到它前面。
        let history = messages.filter { $0.orderIndex <= message.orderIndex }
        let fallbackCoach = CoachService(llm: deps.llm)
        Task(priority: .utility) { [weak self] in
            let review: CoachReview
            do {
                review = try await relationship.reviewAndApply(
                    character: character,
                    history: history,
                    userMessage: message,
                    source: source
                )
            } catch {
                if case LLMError.accessRestricted = error {
                    // 辅助任务没有剩余额度时只记录本地互动，不再追加第二次教练请求。
                    try? await relationship.recordContact(characterID: character.id, message: message)
                    return
                }
                Log.app.warning("关系互动审阅失败，回退语言点评：\(error.localizedDescription)")
                try? await relationship.recordContact(characterID: character.id, message: message)
                guard let fallback = try? await fallbackCoach.review(userText: message.text) else { return }
                review = fallback
            }
            guard review.hasIssues, let json = CoachService.encode(review) else { return }
            try? await chatStore.setCoachReview(messageID: message.id, json: json)
            await self?.reloadMessages()
        }
    }

    private func scheduleAssistantReply(
        after _: String,
        preferredDelay: TimeInterval? = nil,
        replacing messageID: UUID? = nil,
        userMessage explicitUserMessage: MessageDTO? = nil
    ) {
        replyTask?.cancel()
        retryingMessageID = messageID
        guard let anchorMessage = explicitUserMessage
            ?? messages.last(where: { $0.role == .user })
            ?? messageID.flatMap({ replacementID in
                messages.first(where: { $0.id == replacementID })
            })
        else { return }

        let plan: NPCReplyPlan
        if let preferredDelay {
            plan = NPCAttentionPolicy.standard.expeditedReplyPlan(
                userMessageID: anchorMessage.id,
                sentAt: deps.now(),
                delay: preferredDelay
            )
        } else {
            plan = NPCAttentionPolicy.standard.replyPlan(
                for: character,
                userMessage: anchorMessage,
                history: messages
            )
        }
        restartPendingReply(using: plan)
    }

    private func restartPendingReply(using plan: NPCReplyPlan) {
        replyTask?.cancel()
        replyCycleID = UUID()
        let cycleID = replyCycleID
        pendingReplyPlan = plan
        typingBeganAt = nil
        isWaitingForUserBurst = true
        isStreaming = false
        streamingText = nil
        errorMessage = nil

        // 任务在页面返回后仍保留 ViewModel，确保用户留在 App 内时回复不会丢失。
        // App 被系统终止后，load() 会从最后一条用户消息重建同一份确定性计划。
        replyTask = Task { [self] in
            do {
                try await wait(until: plan.generationStartsAt)
                try Task.checkCancellation()
            } catch {
                return
            }
            await streamAssistantReply(cycleID: cycleID, plan: plan)
        }
    }

    private func resumePendingReplyIfNeeded() {
        guard replyTask == nil,
              conversation?.isArchived == false,
              let latest = messages.last,
              latest.role == .user
        else { return }
        scheduleAssistantReply(
            after: latest.text,
            userMessage: latest
        )
    }

    private func wait(until date: Date) async throws {
        let remaining = date.timeIntervalSince(deps.now())
        guard remaining > 0 else { return }
        let scaledDelay = remaining * deps.replyDelayScale
        guard scaledDelay > 0 else { return }
        try await Task.sleep(
            for: .milliseconds(Int((scaledDelay * 1_000).rounded()))
        )
    }

    private func beginTyping(cycleID: UUID) {
        guard cycleID == replyCycleID, !Task.isCancelled else { return }
        if typingBeganAt == nil {
            typingBeganAt = deps.now()
        }
        isWaitingForUserBurst = false
        isStreaming = true
        streamingText = ""
    }

    private func clearReplyState(cycleID: UUID) {
        guard cycleID == replyCycleID else { return }
        isWaitingForUserBurst = false
        isStreaming = false
        streamingText = nil
        pendingReplyPlan = nil
        typingBeganAt = nil
        replyTask = nil
        retryingMessageID = nil
    }

    private func isStillLatestUnanswered(
        plan: NPCReplyPlan,
        conversationID: UUID
    ) async -> Bool {
        do {
            return try await deps.chatStore.isLatestUnansweredUserMessage(
                conversationID: conversationID,
                messageID: plan.userMessageID,
                replacingAssistantMessageID: retryingMessageID
            )
        } catch {
            errorMessage = "回复状态暂时无法确认，请稍后重试。"
            return false
        }
    }

    private func streamAssistantReply(cycleID: UUID, plan: NPCReplyPlan) async {
        guard let conversation, cycleID == replyCycleID, !Task.isCancelled else { return }
        guard await isStillLatestUnanswered(plan: plan, conversationID: conversation.id) else {
            clearReplyState(cycleID: cycleID)
            return
        }
        guard NPCReplyLeaseRegistry.shared.acquire(
            conversationID: conversation.id,
            ownerID: replyOwnerID,
            cycleID: cycleID,
            messageID: plan.userMessageID
        ) else {
            do {
                try await NPCReplyLeaseRegistry.shared.waitUntilAvailable(
                    conversationID: conversation.id
                )
                try Task.checkCancellation()
            } catch {
                return
            }
            guard cycleID == replyCycleID else { return }
            await reloadMessages()
            if await isStillLatestUnanswered(plan: plan, conversationID: conversation.id) {
                await streamAssistantReply(cycleID: cycleID, plan: plan)
            } else {
                clearReplyState(cycleID: cycleID)
            }
            return
        }
        defer {
            NPCReplyLeaseRegistry.shared.release(
                conversationID: conversation.id,
                ownerID: replyOwnerID,
                cycleID: cycleID,
                messageID: plan.userMessageID
            )
        }
        guard await isStillLatestUnanswered(plan: plan, conversationID: conversation.id) else {
            clearReplyState(cycleID: cycleID)
            return
        }
        let replacedMessageID = retryingMessageID
        errorMessage = nil
        let typingTimer = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await wait(until: plan.typingStartsAt)
                try Task.checkCancellation()
            } catch {
                return
            }
            beginTyping(cycleID: cycleID)
        }
        defer {
            typingTimer.cancel()
            if cycleID == replyCycleID {
                clearReplyState(cycleID: cycleID)
            }
        }

        let memoryService = self.memoryService
        let quizRequested = await shouldRequestQuiz(conversationID: conversation.id)
        var request = await makeRoleplayRequest(
            quizRequested: false,
            voiceMode: false
        )
        request.system = Self.appendingSystemInstruction(
            RoleplayReplyDiversityPolicy.turnVariationDirective(
                variation: Int.random(in: 0..<10_000)
            ),
            to: request.system
        )
        guard cycleID == replyCycleID, !Task.isCancelled else { return }

        var accumulated = ""
        do {
            for try await event in await deps.llm.stream(request) {
                try Task.checkCancellation()
                guard cycleID == replyCycleID else { throw CancellationError() }
                if case .textDelta(let delta) = event {
                    accumulated += delta
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard cycleID == replyCycleID else { return }
            Log.llm.error("流式回复失败：\(error)")
            if accumulated.isEmpty {
                errorMessage = ChatErrorPresentation.assistantReply(error)
            } else {
                // 已收增量落库并标记中断，气泡上提供重试。
                _ = try? await persistAssistantReply(
                    conversationID: conversation.id,
                    text: accumulated,
                    interrupted: true
                )
            }
            await reloadMessages()
            notifyConversationChanged()
            return
        }

        guard !accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "暂时没有收到回复，请重试。"
            return
        }

        let recentAssistantReplies = messages
            .filter { $0.role == .assistant }
            .suffix(12)
            .map(\.text)
        let firstReplyText = accumulated
        let tooSimilar = RoleplayReplyDiversityPolicy.isTooSimilar(
            firstReplyText,
            to: recentAssistantReplies
        )
        let latestUserText = messages.last(where: { $0.role == .user })?.text ?? ""
        let continuityViolations = RoleplayReplyContinuityPolicy.violations(
            reply: firstReplyText,
            respondingTo: latestUserText
        )
        if tooSimilar || !continuityViolations.isEmpty {
            var retryRequest = request
            retryRequest.operationID = UUID()
            retryRequest.parentOperationID = request.operationID
            let retryInstructions = [
                tooSimilar
                    ? RoleplayReplyDiversityPolicy.regenerationDirective(avoiding: recentAssistantReplies)
                    : nil,
                continuityViolations.isEmpty
                    ? nil
                    : RoleplayReplyContinuityPolicy.regenerationDirective(
                        violations: continuityViolations
                    ),
            ]
            .compactMap { $0 }
            .joined(separator: "\n\n")
            retryRequest.system = Self.appendingSystemInstruction(
                retryInstructions,
                to: retryRequest.system
            )
            var regenerated = ""
            do {
                for try await event in await deps.llm.stream(retryRequest) {
                    try Task.checkCancellation()
                    guard cycleID == replyCycleID else { throw CancellationError() }
                    if case .textDelta(let delta) = event {
                        regenerated += delta
                    }
                }
                if !regenerated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let remainingViolations = RoleplayReplyContinuityPolicy.violations(
                        reply: regenerated,
                        respondingTo: latestUserText
                    )
                    accumulated = remainingViolations.isEmpty
                        ? regenerated
                        : RoleplayReplyContinuityPolicy.fallbackReply(
                            violations: remainingViolations,
                            characterName: character.card.name
                        )
                }
            } catch is CancellationError {
                return
            } catch {
                // 首个候选仍然是完整模型输出；重试失败时保留它，避免吞掉回复。
                Log.llm.warning("角色回复质量重试失败，保留首个候选：\(error)")
            }
        }

        let replyText = accumulated
        guard cycleID == replyCycleID, !Task.isCancelled else { return }
        guard await isStillLatestUnanswered(plan: plan, conversationID: conversation.id) else {
            return
        }
        do {
            typingTimer.cancel()
            do {
                try await wait(until: plan.typingStartsAt)
            } catch {
                return
            }
            beginTyping(cycleID: cycleID)
            let visibleTypingBeganAt = typingBeganAt ?? deps.now()
            let earliestVisibleDelivery = visibleTypingBeganAt.addingTimeInterval(
                Self.minimumVisibleTypingDuration
            )
            do {
                try await wait(until: max(plan.firstBubbleAt, earliestVisibleDelivery))
            } catch {
                return
            }
            guard await isStillLatestUnanswered(
                plan: plan,
                conversationID: conversation.id
            ) else { return }
            let assistantMessages = try await deliverAssistantReply(
                conversationID: conversation.id,
                text: replyText,
                cycleID: cycleID,
                plan: plan,
                replacingAssistantMessageID: replacedMessageID
            )
            try Task.checkCancellation()
            guard cycleID == replyCycleID else { throw CancellationError() }
            if let replacedMessageID, !assistantMessages.isEmpty {
                try await deps.chatStore.deleteMessage(messageID: replacedMessageID)
                messages.removeAll { $0.id == replacedMessageID }
            }
            // 主对话已经完成并结算后，才允许低优先级学习辅助申请额度。
            // 额度不足时这些任务会静默跳过，但绝不会反过来阻断 NPC 回复。
            if let userMessage = messages.first(where: { $0.id == plan.userMessageID }) {
                let source: RelationshipEventRecord.Source = userMessage.kind == .voice
                    ? .voiceChat
                    : .textChat
                runInteractionReview(for: userMessage, source: source)
                if userMessage.kind == .voice {
                    runSpeechReview(for: userMessage)
                }
            }
            let quiz = quizRequested
                ? try? await QuizService.generate(
                    history: messages,
                    learnerDifficulty: learnerDifficulty,
                    using: deps.llm
                )
                : nil
            if let assistantMessage = assistantMessages.last,
               let quiz,
               let json = QuizService.encode(quiz) {
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
            let characterRegionID = character.card.regionID
            Task(priority: .utility) {
                await memoryService.compressIfNeeded(
                    conversationID: conversationID,
                    characterName: characterName,
                    characterRegionID: characterRegionID
                )
            }
        } catch is CancellationError {
            return
        } catch {
            guard cycleID == replyCycleID else { return }
            Log.app.error("角色回复逐条保存失败：\(error)")
            errorMessage = "回复保存失败：\(error.localizedDescription)"
        }
        await reloadMessages()
        notifyConversationChanged()
    }

    private static func appendingSystemInstruction(
        _ instruction: String,
        to system: String?
    ) -> String {
        [system, instruction]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// 首条气泡已由 NPCReplyPlan 定时；之后仍依据文本长度逐条显示。
    private func deliverAssistantReply(
        conversationID: UUID,
        text: String,
        cycleID: UUID,
        plan: NPCReplyPlan,
        replacingAssistantMessageID: UUID?
    ) async throws -> [MessageDTO] {
        let texts = RoleplayReplyFormatter.messages(from: text)
        var delivered: [MessageDTO] = []
        delivered.reserveCapacity(texts.count)

        for (index, text) in texts.enumerated() {
            try Task.checkCancellation()
            guard cycleID == replyCycleID else { throw CancellationError() }
            let delay = index == 0 ? 0 : RoleplayTypingPace.standard.delay(
                for: text,
                messageIndex: index,
                elapsedSinceTypingBegan: 0,
                variation: Double.random(in: 0...1)
            )
            let milliseconds = Int((delay * 1_000).rounded())
            if milliseconds > 0 {
                try await Task.sleep(for: .milliseconds(milliseconds))
            }
            try Task.checkCancellation()
            guard cycleID == replyCycleID else { throw CancellationError() }

            let message: MessageDTO
            if index == 0 {
                guard let first = try await deps.chatStore.appendAssistantReplyPartIfCurrent(
                    conversationID: conversationID,
                    text: text,
                    respondingToMessageID: plan.userMessageID,
                    replacingAssistantMessageID: replacingAssistantMessageID,
                    createdAt: deps.now()
                ) else { throw CancellationError() }
                message = first
            } else {
                message = try await deps.chatStore.appendAssistantReplyPart(
                    conversationID: conversationID,
                    text: text,
                    startsNewReply: false,
                    createdAt: deps.now()
                )
            }
            delivered.append(message)
            messages.append(message)
            messages.sort { $0.orderIndex < $1.orderIndex }

            // 关键词标注不阻塞下一条气泡的计时和显示。
            Task(priority: .utility) { [weak self] in
                await self?.annotateKeywords(message: message, text: text)
                await self?.reloadMessages()
            }
        }
        return delivered
    }

    @discardableResult
    private func persistAssistantReply(
        conversationID: UUID,
        text: String,
        interrupted: Bool
    ) async throws -> [MessageDTO] {
        if interrupted {
            let cleanedText = RoleplayReplyFormatter.streamingPreview(from: text)
            guard !cleanedText.isEmpty else { return [] }
            let message = try await deps.chatStore.appendMessage(
                conversationID: conversationID,
                role: .assistant,
                text: cleanedText,
                tokenEstimate: TokenEstimator.estimate(cleanedText)
            )
            try await deps.chatStore.updateMessageText(
                messageID: message.id,
                text: cleanedText,
                isInterrupted: true
            )
            await annotateKeywords(message: message, text: cleanedText)
            return [message]
        }

        let texts = RoleplayReplyFormatter.messages(from: text)
        let messages = try await deps.chatStore.appendAssistantReply(
            conversationID: conversationID,
            texts: texts
        )
        for message in messages {
            await annotateKeywords(message: message, text: message.text)
        }
        return messages
    }

    // MARK: - 语境出题

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
        guard let messages = try? await persistAssistantReply(
            conversationID: conversation.id,
            text: "Honestly I'm knackered after that shift 😴",
            interrupted: false
        ), let message = messages.last,
           let json = QuizService.encode(sample) else { return }
        try? await deps.chatStore.attachQuiz(messageID: message.id, quizJSON: json, conversationID: conversation.id)
        await reloadMessages()
    }
    #endif

    /// 角色回复完成后本地词频标注关键词（划线可点）。
    private func annotateKeywords(message: MessageDTO, text: String) async {
        let annotator = KeywordAnnotator(dictionary: deps.dictionary)
        let threshold = learnerDifficulty.keywordFrequencyThreshold
        let words = await annotator.keywords(in: text, frequencyThreshold: threshold)
        guard let json = KeywordAnnotator.encode(words: words) else { return }
        try? await deps.chatStore.setKeywordRanges(messageID: message.id, json: json)
    }

    /// 主线奖励：与主角色对话满 3 轮且尚未发放过剧情机票 → 送 1 张通用机票。
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
