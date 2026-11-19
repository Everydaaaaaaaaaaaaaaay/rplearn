import BackendKit
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
    public internal(set) var messages: [MessageDTO] = [] {
        didSet {
            guard messages != oldValue else { return }
            timelineEvents = ChatTimelineEventPolicy.ordinaryEvents(in: messages)
            rebuildAppointmentTimeline()
        }
    }
    private(set) var timelineEvents: [UUID: ChatMessageTimelineEvent] = [:]
    struct AppointmentTimelineRow: Identifiable, Equatable {
        let appointmentID: UUID
        let event: BackendAppointmentTimelineEvent
        var id: String { event.id }
    }
    private(set) var appointmentTimeline: [UUID: [AppointmentTimelineRow]] = [:]
    private var timelineAppointments: [BackendAppointment] = []
    /// 角色已经进入可见输入阶段；空字符串显示输入指示，nil 表示当前没有回复。
    public private(set) var streamingText: String?
    public private(set) var isStreaming = false
    /// 已收到用户消息，仍处于注意、准备或等待连续消息阶段；此时不显示“正在输入”。
    public private(set) var isWaitingForUserBurst = false
    public var errorMessage: String?
    public var quickNotice: DSQuickNotice?
    public var draft = "" {
        didSet {
            if draft != oldValue {
                recordComposerEdit(from: oldValue, to: draft)
            }
        }
    }
    private var composerActivity = RoleplayComposerActivity()

    func composerSourceEdited(from old: String, to new: String) {
        recordComposerEdit(from: old, to: new)
    }

    public func composerFocusChanged(_ focused: Bool) {
        composerActivity.focusChanged(focused, at: deps.now())
        if !focused { queueSharedComposer(.blurred, remaining: 5) }
    }

    private func recordComposerEdit(from old: String, to new: String) {
        let previous = composerActivity.editedAt
        composerActivity.recordEdit(from: old, to: new, at: deps.now())
        if composerActivity.editedAt != previous {
            queueSharedComposer(.edited, remaining: 25)
            pauseTypingForComposer()
        }
    }

    private func pauseTypingForComposer() {
        if isStreaming {
            isStreaming = false
            streamingText = nil
            isWaitingForUserBurst = true
            typingBeganAt = nil
            if !usesSharedChat, let plan = pendingReplyPlan {
                replyYieldTask?.cancel()
                let cycle = replyCycleID
                replyYieldTask = Task { [weak self] in
                    guard let self else { return }
                    do { try await waitForUserToFinish(plan: plan) } catch { return }
                    beginTyping(cycleID: cycle)
                }
            }
        }
    }

    private struct ComposerEvent {
        let sequence: Int
        let activity: SharedComposerActivity
        let expiresAt: Date
    }
    private let sharedComposerSessionID = UUID()
    private var sharedComposerSequence = 0
    private var pendingComposerEvent: ComposerEvent?
    private var composerReportTask: Task<Void, Never>?
    private var voiceCompositionTask: Task<Void, Never>?

    public func composerRecordingChanged(_ active: Bool) {
        voiceCompositionTask?.cancel()
        composerActivity.voiceActivityChanged(recording: active, at: deps.now())
        queueSharedComposer(active ? .edited : .blurred, remaining: active ? 25 : 5)
        guard active else { voiceCompositionTask = nil; return }
        pauseTypingForComposer()
        voiceCompositionTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                guard let self else { return }
                self.composerActivity.voiceActivityChanged(recording: true, at: self.deps.now())
                self.queueSharedComposer(.edited, remaining: 25)
            }
        }
    }

    private func queueSharedComposer(_ activity: SharedComposerActivity, remaining: TimeInterval = 0) {
        guard usesSharedChat else { return }
        sharedComposerSequence += 1
        pendingComposerEvent = .init(sequence: sharedComposerSequence, activity: activity,
                                     expiresAt: deps.now().addingTimeInterval(remaining))
        flushSharedComposer()
    }

    private func flushSharedComposer() {
        guard composerReportTask == nil, let event = pendingComposerEvent,
              let gateway = deps.sharedChat, let conversation else { return }
        composerReportTask = Task { [weak self] in
            guard let self else { return }
            let remaining = max(0, event.expiresAt.timeIntervalSince(deps.now()))
            do {
                let accepted = try await gateway.reportSharedComposer(conversationID: conversation.id,
                    sessionID: sharedComposerSessionID, sequence: event.sequence,
                    activity: event.activity, remaining: remaining)
                if accepted, pendingComposerEvent?.sequence == event.sequence { pendingComposerEvent = nil }
            } catch { /* The observer retries the same event within its original deadline. */ }
            composerReportTask = nil
            if let pendingComposerEvent, pendingComposerEvent.sequence != event.sequence {
                flushSharedComposer()
            }
        }
    }

    func userTurnHandoffDate(after message: MessageDTO) -> Date {
        let policy = RoleplayTurnTakingPolicy.standard
        let quiet = policy.quietWindow(after: message.text,
            consecutiveUserMessageCount: messages.reversed().prefix { $0.role == .user }.count,
            variation: 0.5, continuingConversation: pendingReplyPlan?.continuingConversation == true)
        return policy.handoffDate(sentAt: message.createdAt, quietWindow: quiet,
            activity: composerActivity)
    }

    /// Editing extends the quiet window without restarting an in-flight paid request.
    private func waitForUserToFinish(plan: NPCReplyPlan) async throws {
        guard deps.replyDelayScale > 0 else { return }
        guard let anchor = messages.first(where: { $0.id == plan.userMessageID }) else { return }
        let cycle = replyCycleID
        let wasStreaming = isStreaming
        let previousStreamingText = streamingText
        var paused = false
        defer {
            if paused, cycle == replyCycleID, !Task.isCancelled {
                isStreaming = wasStreaming
                streamingText = previousStreamingText
                isWaitingForUserBurst = !wasStreaming
            }
        }
        while true {
            try Task.checkCancellation()
            let now = deps.now()
            let until = userTurnHandoffDate(after: anchor)
            guard until > now else { return }
            paused = true
            streamingText = nil
            isStreaming = false
            isWaitingForUserBurst = true
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    private var sharedPageVisible = false
    private var sharedObserver: Task<Void, Never>?
    private var sharedSnapshot: SharedChatSnapshot?
    private var sharedReviewMessages: [UUID: MessageDTO] = [:]
    private var sharedReplyError = false
    private var noticedMessageIDs: Set<UUID> = []
    private var usesSharedChat: Bool { deps.sharedChat != nil }

    func hasRead(_ messageID: UUID) -> Bool { noticedMessageIDs.contains(messageID) }

    private var realtimeLearningSource: LearningReplySource?
    private var replyTask: Task<Void, Never>?
    private var replyYieldTask: Task<Void, Never>?
    private let replyOwnerID = UUID()
    private var replyCycleID = UUID()
    private var pendingReplyPlan: NPCReplyPlan?
    private var typingBeganAt: Date?
    var retryingMessageID: UUID?

    public init(character: CharacterDTO, deps: ChatDependencies) {
        self.character = character
        self.learnerDifficulty = character.difficultyLevel
        self.deps = deps
    }

    public func load() async {
        sharedPageVisible = true
        await refreshCharacter()
        do {
            let conversation = try await deps.chatStore.openConversation(characterID: character.id)
            self.conversation = conversation
            self.messages = try await deps.chatStore.messages(conversationID: conversation.id)
            if let gateway = deps.sharedChat {
                do {
                    let state = try await gateway.openSharedConversation(characterID: character.id)
                    try await acceptSharedState(state)
                } catch {
                    errorMessage = "会话暂未同步，恢复连接后会继续。"
                }
                startSharedObservation()
            }
            if let profile = try? await deps.economyStore.profile() {
                learnerDifficulty = profile.difficultyLevel
            }
            #if DEBUG
            if !deps.marketingMotionCapture { resumePendingReplyIfNeeded() }
            #else
            resumePendingReplyIfNeeded()
            #endif
        } catch {
            errorMessage = "加载会话失败：\(error.localizedDescription)"
            Log.app.error("openConversation 失败：\(error)")
        }
        await deps.learningChat?.refresh(characterID: character.id)
        await refreshAppointments()
    }

    public private(set) var appointments: [BackendAppointment] = []
    public private(set) var appointmentNotice: String?
    public private(set) var checkingAppointments = false
    @ObservationIgnored private var needsAppointmentRefresh = false

    public func refreshAppointments(detect: Bool = false) async {
        guard let conversation, let refresh = deps.refreshAppointments else { return }
        if checkingAppointments {
            if !detect { needsAppointmentRefresh = true }
            return
        }
        checkingAppointments = true
        defer {
            checkingAppointments = false
            if needsAppointmentRefresh {
                needsAppointmentRefresh = false
                Task { await refreshAppointments() }
            }
        }
        do {
            let records = try await refresh(character.id, conversation.id, detect).filter { $0.characterId == character.id }
            if records != timelineAppointments {
                timelineAppointments = records
                rebuildAppointmentTimeline()
            }
            appointments = records
                .filter { $0.status != "cancelled" && $0.status != "expired" }
                .sorted {
                    let priority: (BackendAppointment) -> Int = { $0.status == "in_progress" ? 0 : $0.status == "confirmed" ? 1 : 2 }
                    if priority($0) != priority($1) { return priority($0) < priority($1) }
                    return $0.status == "completed" ? $0.startsAt > $1.startsAt : $0.startsAt < $1.startsAt
                }
            appointmentNotice = detect && appointments.isEmpty ? "还没有说定的约定。请在聊天里确认当地日期、时间和地点。" : nil
        } catch {
            if detect {
                appointmentNotice = (error as? BackendClientError)?.code == "LOGIN_REQUIRED"
                    ? "请先登录账号，再把聊天中的计划保存为约定。"
                    : "约定暂时没有同步成功，可以稍后再整理。"
            }
        }
    }

    private func rebuildAppointmentTimeline() {
        guard let conversationID = conversation?.id, !timelineAppointments.isEmpty else {
            if !appointmentTimeline.isEmpty { appointmentTimeline = [:] }
            return
        }
        var result: [UUID: [AppointmentTimelineRow]] = [:]
        var seen = Set<String>()
        let messageIDs = Set(messages.map(\.id))
        for appointment in timelineAppointments {
            for event in appointment.timelineEvents ?? [] where seen.insert(event.id).inserted {
                let anchor: UUID?
                if let cited = event.messageId, messageIDs.contains(cited) {
                    anchor = cited
                } else if event.conversationId == conversationID, let date = AppointmentDisplayTime.date(event.occurredAt) {
                    anchor = messages.last(where: { $0.role != .coach && $0.createdAt <= date })?.id
                } else {
                    anchor = nil
                }
                guard let anchor else { continue }
                result[anchor, default: []].append(.init(appointmentID: appointment.id, event: event))
            }
        }
        appointmentTimeline = result.mapValues { $0.sorted { ($0.event.occurredAt, $0.id) < ($1.event.occurredAt, $1.id) } }
    }

    private func inspectAppointmentAgreement() {
        let context = messages.suffix(12).map(\.text).joined(separator: " ").lowercased()
        let cues = ["meet", "tomorrow", "tonight", "coffee", "cafe", "café", "see you", "o'clock", "约", "明天", "后天", "周末", "见面", "咖啡", "下午", "上午", "晚上", "改期"]
        guard cues.contains(where: context.contains) else { return }
        Task { [weak self] in await self?.refreshAppointments(detect: true) }
    }

    /// 正在翻译中的消息（气泡下方转圈）。
    public private(set) var translatingMessageIDs: Set<UUID> = []

    /// 云端翻译失败（离线/报错/额度）时的兜底翻译，由 ChatView 注入 Apple 端上翻译。
    public var translationFallback: (@MainActor (String) async -> String?)?

    /// 翻译整句并持久缓存：优先云端 LLM，失败时回退本地翻译。
    /// 同时检查最新消息，避免旧 DTO 导致重复翻译。
    public func translate(message: MessageDTO) async {
        let text = message.text
        guard message.translationZh == nil,
              messages.first(where: { $0.id == message.id })?.translationZh == nil,
              !translatingMessageIDs.contains(message.id) else { return }
        translatingMessageIDs.insert(message.id)
        errorMessage = nil
        defer { translatingMessageIDs.remove(message.id) }

        var translation = try? await deps.chatStore.cachedTranslation(for: text)
        var cloudError: Error?
        if translation == nil {
            do {
                let candidate = try await deps.translator.translateToChinese(text)
                translation = candidate.isEmpty ? nil : candidate
            } catch { cloudError = error }
        }
        guard !Task.isCancelled else { return }

        if translation == nil, let fallback = translationFallback {
            let local = await fallback(text)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let local, !local.isEmpty { translation = local }
            guard !Task.isCancelled else { return }
        }

        guard let translation else {
            let detail = cloudError?.localizedDescription ?? "请稍后重试"
            errorMessage = "翻译失败：\(detail)"
            return
        }
        do {
            try await deps.chatStore.setTranslation(messageID: message.id, translationZh: translation)
            await reloadMessages()
            deps.tutorial?.onEvent("translation")
        } catch {
            errorMessage = "保存译文失败，请重试：\(error.localizedDescription)"
        }
    }

    /// 播放消息音频（按角色国籍口音）。
    public func speak(message: MessageDTO) async {
        await deps.speech.speak(speechRequest(for: message))
    }

    func speechRequest(for message: MessageDTO) -> SpeechRequest {
        SpeechRequest(
            text: message.text,
            language: message.role == .assistant ? AccentMapper.language(forNationality: character.card.nationality) : "en-GB",
            purpose: .characterDialogue,
            voiceHint: message.role == .assistant ? SpeechVoiceHint(
                stableID: character.id.uuidString.lowercased(),
                gender: character.card.gender.rawValue,
                nationality: character.card.nationality,
                supertonicVoice: character.card.resolvedReadingVoice
            ) : StoryVoiceCasting.narrator
        )
    }

    private func reserveTutorialMessage() -> Bool {
        guard let tutorial = deps.tutorial else { return true }
        guard tutorial.session.reserveMessage() else {
            quickNotice = DSQuickNotice("请先完成教程再和朋友聊天吧～", symbol: .finishPractice)
            return false
        }
        return true
    }

    public func canRemoveFriend() -> Bool {
        guard deps.tutorial != nil else { return true }
        quickNotice = DSQuickNotice("在教程中无法删除好友～", symbol: .protectedFriend)
        return false
    }

    public func sendDraft() async {
        let originalDraft = draft
        let text = originalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard reserveTutorialMessage() else { return }
        Haptics.impact(.light)
        draft = ""
        composerActivity.didSend()
        queueSharedComposer(.sent)
        if !(await send(userText: text)) {
            deps.tutorial?.session.releaseFailedMessage()
            if draft.isEmpty { draft = originalDraft }
        }
    }

    /// 发送语音消息：气泡为语音条，发给 LLM 的是转写文本，同样走教练审核。
    public func sendVoice(capture: VoiceRecorder.Capture) async {
        composerActivity.didSend()
        queueSharedComposer(.sent)
        guard let conversation else { return }
        guard reserveTutorialMessage() else {
            if let file = capture.fileName { VoiceMessageStorage.delete(fileName: file) }
            return
        }
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
                tokenEstimate: TokenEstimator.estimate(capture.transcript),
                learningOrigin: await userLearningOrigin(),
                contextMemoryIDs: usesSharedChat ? await memoryService.contextMemoryIDs(characterID: character.id, query: capture.transcript) : nil,
                sharedOrdering: usesSharedChat
            )
            if let sourceFileName = capture.fileName {
                Task { [weak self] in
                    guard let self else { return }
                    // Backup must not delay the visible message or its reply.
                    if await deps.voiceMedia.isCloudBackupAvailable {
                        do {
                            _ = try await deps.voiceMedia.enqueue(messageID: messageID, sourceFileName: sourceFileName)
                        } catch {
                            if errorMessage == nil { errorMessage = "语音已保存在本机，云端备份暂未完成。" }
                            Log.app.warning("语音云端排队失败：\(String(describing: type(of: error)))")
                        }
                    }
                }
            }
            await reloadMessages()
            notifyConversationChanged()
        } catch {
            deps.tutorial?.session.releaseFailedMessage()
            errorMessage = "发送失败：\(error.localizedDescription)"
            return
        }
        Task { await deps.learningChat?.messageSaved(characterID: character.id) }
        scheduleAssistantReply(after: capture.transcript, userMessage: userMessage)
    }

    /// 实时语音回合：端侧终稿只发送为文本，并继续复用当前低成本流式 LLM。
    /// 该方法先持久化用户话轮，再返回纯文本增量；应用不向 LLM 上传音频。
    var voiceLeaseID: UUID?
    private var sharedVoiceInputs: [UUID: UUID] = [:]
    private var earlyVoiceReceipts: [UUID: (text: String, interrupted: Bool)] = [:]
    private var legacyVoiceResponseID = UUID()

    public func realtimeReplyStream(
        userText: String, responseID: UUID? = nil
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard let conversation else {
            throw AppError.storage("聊天尚未加载")
        }
        let text = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AppError.storage("语音转写为空")
        }

        guard reserveTutorialMessage() else { throw AppError.storage("请先完成教程再和朋友聊天吧～") }
        var persisted = false
        defer { if !persisted { deps.tutorial?.session.releaseFailedMessage() } }
        let responseID = responseID ?? legacyVoiceResponseID
        let origin = await userLearningOrigin()
        let recall = usesSharedChat ? await memoryService.contextMemoryIDs(characterID: character.id, query: text) : nil
        try Task.checkCancellation()
        let userMessage = try await deps.chatStore.appendMessage(
            conversationID: conversation.id,
            role: .user,
            text: text,
            tokenEstimate: TokenEstimator.estimate(text),
            learningOrigin: origin,
            sharedVoiceLeaseID: usesSharedChat ? voiceLeaseID : nil,
            contextMemoryIDs: recall,
            sharedOrdering: usesSharedChat
        )
        persisted = true
        try await deps.chatStore.setReplyInterrupted(userMessageID: userMessage.id, interrupted: true)
        messages.append(userMessage)
        messages.sort { $0.orderIndex < $1.orderIndex }
        notifyConversationChanged()

        if let gateway = deps.sharedChat {
            sharedVoiceInputs[responseID] = userMessage.id
            if let early = earlyVoiceReceipts.removeValue(forKey: responseID) {
                await saveRealtimeAssistant(spokenText: early.text, interrupted: early.interrupted, responseID: responseID)
            }
            sharedReviewMessages[userMessage.id] = userMessage
            startSharedObservation()
            try await gateway.uploadSharedMessages()
            return sharedVoiceStream(
                gateway: gateway, conversationID: conversation.id, userMessageID: userMessage.id)
        }
        try Task.checkCancellation()
        realtimeLearningSource = nil
        let tracker = deps.learningChat
        var request = try await AsyncDeadline.run(timeout: deps.replyTimeout) { [self] in
            var request = await makeRoleplayRequest(voiceMode: true)
            try Task.checkCancellation()
            request.learningChat = try await tracker?.prepareReply(conversationID: conversation.id, userMessage: userMessage)
            try Task.checkCancellation()
            return request
        }
        try Task.checkCancellation()
        realtimeLearningSource = request.learningChat.map { LearningReplySource(context: $0, operationID: request.operationID) }
        try Task.checkCancellation()
        request.voiceLeaseID = voiceLeaseID
        let upstream = await deps.llm.stream(request)
        return AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                var reviewStarted = false
                defer {
                    if !reviewStarted { self?.runInteractionReview(for: userMessage, source: .voiceChat) }
                }
                do {
                    var receivedText = false
                    for try await event in upstream {
                        try Task.checkCancellation()
                        if case .textDelta(let delta) = event, !delta.isEmpty {
                            if !delta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { receivedText = true }
                            if receivedText && !reviewStarted {
                                reviewStarted = true
                                self?.runInteractionReview(for: userMessage, source: .voiceChat)
                            }
                            continuation.yield(delta)
                        }
                    }
                    guard receivedText else { throw LLMError.emptyResponse }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 保存模型实际生成的语音字幕；被用户插话截断时保留中断标记。
    public func saveRealtimeAssistant(spokenText: String, interrupted: Bool, responseID: UUID? = nil) async {
        if usesSharedChat {
            let responseID = responseID ?? legacyVoiceResponseID
            guard let conversation, let gateway = deps.sharedChat else { return }
            guard let inputID = sharedVoiceInputs.removeValue(forKey: responseID) else {
                earlyVoiceReceipts[responseID] = (spokenText, interrupted)
                return
            }
            if responseID == legacyVoiceResponseID { legacyVoiceResponseID = UUID() }
            do {
                try await gateway.recordSharedVoiceReceipt(conversationID: conversation.id, userMessageID: inputID,
                                                           text: spokenText, interrupted: interrupted)
            } catch {
                Log.app.warning("通话收听记录等待同步：\(error.localizedDescription)")
            }
            await reloadMessages()
            notifyConversationChanged()
            return
        }
        guard let conversation else { return }
        let spokenText = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spokenText.isEmpty else { return }
        do {
            let delivered = try await persistAssistantReply(
                conversationID: conversation.id,
                text: spokenText,
                interrupted: interrupted,
                learningSource: interrupted ? nil : realtimeLearningSource
            )
            if !interrupted, let first = delivered.first,
               let input = messages.last(where: { $0.role == .user && $0.orderIndex < first.orderIndex }),
               let mood = ChatTimelineEvidence.mood(reply: delivered.map(\.text).joined(separator: "\n")) {
                try? await deps.chatStore.addTimelineEvents(messageID: input.id, events: [mood])
            }
            Task { await deps.learningChat?.messageSaved(characterID: character.id) }
            Task { [weak self] in
                await self?.grantMainlineTicketIfEligible(conversationID: conversation.id)
                await self?.reloadMessages()
                self?.notifyConversationChanged()
            }
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

    public func refreshMessages() async {
        if usesSharedChat { startSharedObservation() }
        await reloadMessages()
        if latestDialogueMessage?.role == .assistant, errorMessage == "上次回复未完成，点重试继续。" {
            errorMessage = nil
        }
    }

    public func presence(at date: Date) -> NPCPresenceSnapshot {
        NPCAttentionPolicy.standard.presence(
            for: character,
            at: date,
            lastAssistantMessageAt: messages.last(where: { $0.role == .assistant })?.createdAt,
            pendingReplyPlan: pendingReplyPlan
        )
    }

    public func cancelPendingReply() {
        sharedObserver?.cancel()
        sharedObserver = nil
        cancelReplyProducer()
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
            // 云端备份可能已将原始文件移入账号目录，先取得最新媒体引用。
            await reloadMessages()
            let current = messages.first(where: { $0.id == message.id }) ?? message
            let fileName = try await deps.voiceMedia.localFile(
                messageID: message.id,
                assetID: current.audioAssetID,
                existingFileName: current.audioFileName
            )
            await reloadMessages()
            return fileName
        } catch {
            Log.app.warning("语音文件获取失败：\(String(describing: type(of: error)))")
            errorMessage = "语音下载失败，请稍后重试。"
            return nil
        }
    }

    /// 重试成功后才删除旧中断消息；失败时仍保留用户已收到的内容。
    public func retryInterrupted(messageID: UUID) async {
        guard !isStreaming, !isWaitingForUserBurst,
              messages.contains(where: { $0.id == messageID && $0.role == .assistant && $0.isInterrupted })
        else { return }
        scheduleAssistantReply(after: "", preferredDelay: 0.45, replacing: messageID)
    }

    private func userLearningOrigin() async -> LearningChatOrigin? {
        guard let tracker = deps.learningChat else { return nil }
        let characterID = character.id
        return try? await AsyncDeadline.run(timeout: .seconds(5)) {
            await tracker.userOrigin(characterID: characterID)
        }
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
                tokenEstimate: TokenEstimator.estimate(userText),
                learningOrigin: await userLearningOrigin(),
                contextMemoryIDs: usesSharedChat ? await memoryService.contextMemoryIDs(characterID: character.id, query: userText) : nil,
                sharedOrdering: usesSharedChat
            )
            await reloadMessages()
            notifyConversationChanged()
        } catch {
            errorMessage = "发送失败：\(error.localizedDescription)"
            return false
        }
        // 辅助点评必须等主回复完成：免费额度下不能让后台任务抢走用户可见回复的预留。
        Task { await deps.learningChat?.messageSaved(characterID: character.id) }
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
        let conversationID = conversation?.id
        // 点评延后到主回复之后执行，但输入语境必须停在这条用户消息，不能把后生成的回复倒灌到它前面。
        let history = messages.filter { $0.orderIndex <= message.orderIndex }
        let memoryStore = deps.memoryStore
        Task(priority: .utility) { [weak self] in
            let reply: String
            if let conversationID {
                reply = (try? await chatStore.replyText(after: message, conversationID: conversationID)) ?? ""
            } else { reply = "" }
            var events = [ChatTimelineEvidence.mood(reply: reply)].compactMap { $0 }
            let extractMemory = MemoryFact.shouldExtract(message.text)
            let existing = extractMemory ? ((try? await memoryStore.memories(characterID: character.id, tier: .long, includingArchived: true)) ?? []) : []
            let context = existing.filter { $0.record?.edited != true }.suffix(4).compactMap {
                $0.record.map { $0.key + ": " + String($0.text.prefix(90)) }
            }.joined(separator: "\n")
            let historyCutoff = try? await memoryStore.extractionCutoff(characterID: character.id)
            let reviewHistory = history.filter { historyCutoff == nil || $0.createdAt > historyCutoff! }
            let result: InteractionReview
            do {
                result = try await relationship.evaluate(character: character, history: reviewHistory,
                    userMessage: message, memoryContext: context, extractMemory: extractMemory)
                if let settlement = try await relationship.apply(review: result, character: character,
                    history: reviewHistory, userMessage: message, source: source) {
                    events.append(settlement.event)
                }
            } catch {
                Log.app.warning("互动审阅失败，本轮跳过辅助点评：\(error.localizedDescription)")
                try? await relationship.recordContact(characterID: character.id, message: message)
                try? await chatStore.addTimelineEvents(messageID: message.id, events: events)
                return
            }
            let cutoff = try? await memoryStore.extractionCutoff(characterID: character.id)
            if extractMemory && (cutoff == nil || message.createdAt > cutoff!) {
                let records = (result.memoryFacts ?? []).compactMap { $0.record(from: message) }
                do {
                    let changes = try await memoryStore.applyFacts(characterID: character.id, records: records, sourceIndex: message.orderIndex + 1)
                    if let first = changes.first { events.append(ChatTimelineEvidence.memory(first)) }
                } catch { Log.app.warning("记忆更新保存失败：\(error.localizedDescription)") }
            }
            if !events.contains(where: { $0.kind == .memory }), ChatTimelineEvidence.hasRecallCue(reply),
               let memories = try? await memoryStore.memories(characterID: character.id, tier: .long),
               let recall = ChatTimelineEvidence.recalledMemory(reply: reply, userMessage: message, memories: memories) {
                events.append(recall)
            }
            do { try await chatStore.addTimelineEvents(messageID: message.id, events: events) }
            catch { Log.app.warning("聊天事件保存失败：\(error.localizedDescription)") }
            if result.coachReview.hasIssues, let json = CoachService.encode(result.coachReview) {
                try? await chatStore.setCoachReview(messageID: message.id, json: json)
            }
            await self?.reloadMessages()
        }
    }

    private func scheduleAssistantReply(
        after _: String,
        preferredDelay: TimeInterval? = nil,
        replacing messageID: UUID? = nil,
        userMessage explicitUserMessage: MessageDTO? = nil
    ) {
        if usesSharedChat {
            if let explicitUserMessage { sharedReviewMessages[explicitUserMessage.id] = explicitUserMessage }
            errorMessage = nil
            isWaitingForUserBurst = true
            startSharedObservation()
            Task { [weak self] in
                guard let self, let gateway = self.deps.sharedChat else { return }
                do { try await gateway.uploadSharedMessages() } catch {
                    self.errorMessage = "消息已保存在本机，连接恢复后会继续发送。"
                }
            }
            return
        }
        cancelReplyProducer()
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
        } else if deps.tutorial != nil {
            // The same typing/delivery pipeline, without making a practice wait
            // for the NPC's next scheduled online window.
            plan = NPCAttentionPolicy.standard.expeditedReplyPlan(
                userMessageID: anchorMessage.id, sentAt: deps.now(), delay: 1
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
        cancelReplyProducer()
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
                guard cycleID == replyCycleID, !Task.isCancelled else { return }
                try await waitForUserToFinish(plan: plan)
                let wordCount = messages.last(where: { $0.role == .user })?.text.split(whereSeparator: \.isWhitespace).count ?? 0
                // During an active conversation, preparation overlaps the quiet
                // window instead of adding another delay after the user yields.
                if !plan.continuingConversation {
                    try await wait(until: deps.now().addingTimeInterval(
                        2.5 + min(8, Double(wordCount) * 0.2)
                    ))
                }
                try await waitForUserToFinish(plan: plan)
                try Task.checkCancellation()
            } catch {
                return
            }
            await streamAssistantReply(cycleID: cycleID, plan: plan)
        }
    }

    private func cancelReplyProducer() {
        replyTask?.cancel()
        replyYieldTask?.cancel()
        replyYieldTask = nil
        if let conversation, let plan = pendingReplyPlan {
            NPCReplyLeaseRegistry.shared.release(conversationID: conversation.id,
                ownerID: replyOwnerID, cycleID: replyCycleID, messageID: plan.userMessageID)
        }
    }

    private var latestDialogueMessage: MessageDTO? {
        messages.last { $0.role == .user || $0.role == .assistant }
    }

    public var canRetryUnansweredReply: Bool {
        if usesSharedChat { return sharedReplyError && !isStreaming && !isWaitingForUserBurst }
        return !isStreaming && !isWaitingForUserBurst && latestDialogueMessage?.role == .user
            && latestDialogueMessage?.isInterrupted == true && !hasActiveReplyProducer
    }

    private var hasActiveReplyProducer: Bool {
        guard let conversation, let latest = latestDialogueMessage else { return false }
        return NPCReplyLeaseRegistry.shared.contains(conversationID: conversation.id, messageID: latest.id)
    }

    public func retryUnansweredReply() {
        if let gateway = deps.sharedChat, let conversation {
            guard canRetryUnansweredReply else { return }
            sharedReplyError = false
            isWaitingForUserBurst = true
            Task { [weak self] in
                do {
                    try await gateway.uploadSharedMessages()
                    try await gateway.retrySharedReply(conversationID: conversation.id, commandID: UUID())
                    self?.startSharedObservation()
                } catch {
                    self?.errorMessage = "回复状态核对失败，请稍后重试。"
                    self?.isWaitingForUserBurst = false
                    self?.sharedReplyError = true
                }
            }
            return
        }
        guard canRetryUnansweredReply, let latest = latestDialogueMessage else { return }
        scheduleAssistantReply(after: latest.text, preferredDelay: 0.45, userMessage: latest)
    }

    private func resumePendingReplyIfNeeded() {
        guard !usesSharedChat else { return }
        guard replyTask == nil,
              conversation?.isArchived == false,
              let latest = latestDialogueMessage,
              latest.role == .user
        else { return }
        // The persisted interruption marker is also a crash-recovery checkpoint.
        // Another living page may still own this request; follow it instead of
        // reporting a failure or starting another paid generation.
        if hasActiveReplyProducer, let conversation {
            isWaitingForUserBurst = true
            errorMessage = nil
            replyCycleID = UUID()
            let observerCycle = replyCycleID
            replyTask = Task { [self] in
                defer {
                    if replyCycleID == observerCycle { replyTask = nil; isWaitingForUserBurst = false }
                }
                do {
                    try await NPCReplyLeaseRegistry.shared.waitUntilAvailable(conversationID: conversation.id)
                    try Task.checkCancellation()
                    await reloadMessages()
                    guard replyCycleID == observerCycle else { return }
                    if latestDialogueMessage?.role == .user, latestDialogueMessage?.isInterrupted == true {
                        errorMessage = "上次回复未完成，点重试继续。"
                    }
                } catch { }
            }
            return
        }
        guard !latest.isInterrupted else {
            errorMessage = "上次回复未完成，点重试继续。"
            return
        }
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
        if let messageID = pendingReplyPlan?.userMessageID { noticedMessageIDs.insert(messageID) }
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
        let watchdog = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: deps.replyTimeout) } catch { return }
            guard cycleID == replyCycleID else { return }
            replyTask?.cancel()
            clearReplyState(cycleID: cycleID)
            replyCycleID = UUID()
            errorMessage = "回复等待超时，点重试继续；你的消息已保留。"
            NPCReplyLeaseRegistry.shared.release(conversationID: conversation.id,
                ownerID: replyOwnerID, cycleID: cycleID, messageID: plan.userMessageID)
            try? await deps.chatStore.setReplyInterrupted(userMessageID: plan.userMessageID, interrupted: true)
            if let last = latestDialogueMessage, last.role == .assistant,
               let user = messages.first(where: { $0.id == plan.userMessageID }), last.orderIndex > user.orderIndex {
                try? await deps.chatStore.updateMessageText(messageID: last.id, text: last.text, isInterrupted: true)
            }
            await reloadMessages()
        }
        defer { watchdog.cancel() }
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
                try await waitForUserToFinish(plan: plan)
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

        do { try await deps.chatStore.setReplyInterrupted(userMessageID: plan.userMessageID, interrupted: true) }
        catch { errorMessage = "回复状态未能保存，请重试。"; return }
        await reloadMessages()
        guard cycleID == replyCycleID, !Task.isCancelled else { return }
        let memoryService = self.memoryService
        var request = await makeRoleplayRequest(
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
            if let userMessage = messages.first(where: { $0.id == plan.userMessageID }) {
                request.learningChat = try await deps.learningChat?.prepareReply(conversationID: conversation.id, userMessage: userMessage)
            }
            try Task.checkCancellation()
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
            guard cycleID == replyCycleID, !Task.isCancelled else { return }
            Log.llm.error("流式回复失败：\(error)")
            if accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

        // AsyncThrowingStream may end normally on cancellation, without throwing.
        // A superseded user turn must never publish an empty-response error.
        guard cycleID == replyCycleID, !Task.isCancelled else { return }
        guard !accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "暂时没有收到回复，请点重试。"
            return
        }

        let recentAssistantReplies = messages
            .filter { $0.role == .assistant }
            .suffix(12)
            .map(\.text)
        var learningSource = request.learningChat.map { LearningReplySource(context: $0, operationID: request.operationID) }
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
                    learningSource = remainingViolations.isEmpty
                        ? retryRequest.learningChat.map { LearningReplySource(context: $0, operationID: retryRequest.operationID) }
                        : nil
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
                replacingAssistantMessageID: replacedMessageID,
                learningSource: learningSource
            )
            try Task.checkCancellation()
            guard cycleID == replyCycleID else { throw CancellationError() }
            if let replacedMessageID, !assistantMessages.isEmpty {
                try await deps.chatStore.deleteMessage(messageID: replacedMessageID)
                messages.removeAll { $0.id == replacedMessageID }
            }
            try? await deps.chatStore.setReplyInterrupted(userMessageID: plan.userMessageID, interrupted: false)
            if let userMessage = messages.first(where: { $0.id == plan.userMessageID }) {
                let source: RelationshipEventRecord.Source = userMessage.kind == .voice ? .voiceChat : .textChat
                runInteractionReview(for: userMessage, source: source)
            }
            Task { [weak self] in
                await self?.grantMainlineTicketIfEligible(conversationID: conversation.id)
                await self?.reloadMessages()
                self?.notifyConversationChanged()
            }
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
        replacingAssistantMessageID: UUID?,
        learningSource: LearningReplySource? = nil
    ) async throws -> [MessageDTO] {
        let texts = RoleplayReplyFormatter.messages(from: text)
        var delivered: [MessageDTO] = []
        delivered.reserveCapacity(texts.count)

        for (index, text) in texts.enumerated() {
            try Task.checkCancellation()
            guard cycleID == replyCycleID else { throw CancellationError() }
            try await waitForUserToFinish(plan: plan)
            beginTyping(cycleID: cycleID)
            let delay = RoleplayTypingPace.standard.delay(
                for: text,
                messageIndex: index,
                elapsedSinceTypingBegan: typingBeganAt.map {
                    deps.now().timeIntervalSince($0) / max(deps.replyDelayScale, 0.001)
                } ?? 0,
                variation: Double.random(in: 0...1)
            )
            let milliseconds = Int((delay * deps.replyDelayScale * 1_000).rounded())
            if milliseconds > 0 {
                try await Task.sleep(for: .milliseconds(milliseconds))
            }
            try await waitForUserToFinish(plan: plan)
            try Task.checkCancellation()
            guard cycleID == replyCycleID else { throw CancellationError() }

            let message: MessageDTO
            if index == 0 {
                guard let first = try await deps.chatStore.appendAssistantReplyPartIfCurrent(
                    conversationID: conversationID,
                    text: text,
                    respondingToMessageID: plan.userMessageID,
                    replacingAssistantMessageID: replacingAssistantMessageID,
                    createdAt: deps.now(),
                    learningOrigin: learningSource?.origin(index: index, count: texts.count)
                ) else { throw CancellationError() }
                message = first
            } else {
                message = try await deps.chatStore.appendAssistantReplyPart(
                    conversationID: conversationID,
                    text: text,
                    startsNewReply: false,
                    createdAt: deps.now(),
                    learningOrigin: learningSource?.origin(index: index, count: texts.count)
                )
            }
            delivered.append(message)
            messages.append(message)
            messages.sort { $0.orderIndex < $1.orderIndex }
            notifyConversationChanged()

            // 关键词标注不阻塞下一条气泡的计时和显示。
            Task(priority: .utility) { [weak self] in
                await self?.annotateKeywords(message: message, text: text)
                await self?.reloadMessages()
            }
        }
        if !delivered.isEmpty {
            Task { await deps.learningChat?.messageSaved(characterID: character.id) }
            inspectAppointmentAgreement()
        }
        return delivered
    }

    @discardableResult
    private func persistAssistantReply(
        conversationID: UUID,
        text: String,
        interrupted: Bool,
        learningSource: LearningReplySource? = nil
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
            texts: texts,
            learningSource: learningSource
        )
        for message in messages {
            await annotateKeywords(message: message, text: message.text)
        }
        inspectAppointmentAgreement()
        return messages
    }

    #if DEBUG
    /// Records the native typing indicator and production bubble delivery at normal speed.
    /// Only the reply text is prepared; no model, relationship review or paid gateway runs.
    func playMarketingCaptureReply() async {
        guard deps.marketingMotionCapture, let conversation,
              let user = messages.last, user.role == .user,
              user.text == "How did your latte art practice go?" else { return }
        let cycle = replyCycleID
        let plan = NPCAttentionPolicy.standard.expeditedReplyPlan(
            userMessageID: user.id, sentAt: user.createdAt, delay: 0)
        pendingReplyPlan = plan
        defer { clearReplyState(cycleID: cycle) }
        do {
            try await Task.sleep(for: .seconds(4))
            beginTyping(cycleID: cycle)
            _ = try await deliverAssistantReply(conversationID: conversation.id,
                text: "A jellyfish 😂\nApparently, foam has other plans.",
                cycleID: cycle, plan: plan, replacingAssistantMessageID: nil)
        } catch is CancellationError { }
        catch { errorMessage = "Capture playback failed: \(error.localizedDescription)" }
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

    public func stopSharedObservation() {
        voiceCompositionTask?.cancel()
        voiceCompositionTask = nil
        queueSharedComposer(.inactive)
        sharedPageVisible = false
        // Finish the originating device's existing coaching/memory work when the
        // user navigates away, without affecting the durable server producer.
        guard sharedReviewMessages.isEmpty || sharedReplyError else { return }
        sharedObserver?.cancel()
        sharedObserver = nil
    }

    private func startSharedObservation() {
        guard sharedObserver == nil, let gateway = deps.sharedChat else { return }
        sharedObserver = Task { [self] in
            while !Task.isCancelled {
                do {
                    let state: SharedChatSnapshot
                    if let snapshot = self.sharedSnapshot {
                        state = try await gateway.refreshSharedConversation(
                            conversationID: snapshot.conversationID)
                    } else {
                        state = try await gateway.openSharedConversation(characterID: self.character.id)
                    }
                    try Task.checkCancellation()
                    try await self.acceptSharedState(state)
                    self.flushSharedComposer()
                } catch is CancellationError { return } catch BackendClientError.signedOut {
                    sharedObserver = nil
                    return
                } catch { errorMessage = "会话连接暂时中断，正在重新同步。" }
                do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            }
        }
    }

    private func acceptSharedState(_ state: SharedChatSnapshot) async throws {
        sharedSnapshot = state
        guard let canonical = try await deps.chatStore.conversation(id: state.conversationID) else {
            throw AppError.storage("会话尚未同步")
        }
        conversation = canonical
        await reloadMessages()
        let status = state.generation?.status
        let active = status == "queued" || status == "dispatched"
        if status == "dispatched", let ids = state.generation?.inputMessageIDs {
            noticedMessageIDs.formUnion(ids)
        }
        if active, let plan = state.generation?.replyPlan,
           let attention = NPCAttentionLevel(rawValue: plan.attention) {
            pendingReplyPlan = .init(userMessageID: plan.userMessageID, attention: attention,
                noticedAt: plan.noticedAt, generationStartsAt: plan.generationStartsAt,
                typingStartsAt: plan.typingStartsAt, firstBubbleAt: plan.firstBubbleAt,
                continuingConversation: plan.continuingConversation)
        } else if !active { pendingReplyPlan = nil }
        let localYield = messages.last(where: { $0.role == .user }).map {
            deps.replyDelayScale > 0 && userTurnHandoffDate(after: $0) > deps.now()
        } ?? false
        isStreaming = status == "dispatched" && (state.generation?.phase ?? "typing") == "typing" && !localYield
        isWaitingForUserBurst = active && !isStreaming
        streamingText = isStreaming ? "" : nil
        sharedReplyError = status == "failed" || status == "uncertain"
        errorMessage =
            status == "uncertain" ? "上次回复状态未确认。重试会重新生成，可能再次计费。" : (sharedReplyError ? "上次回复未完成，点重试继续。" : nil)
        let reviewed = sharedReviewMessages.values.filter { state.coveredMessageIDs.contains($0.id) }
        for message in reviewed {
            sharedReviewMessages[message.id] = nil
            if state.durableFollowups {
                if let reply = try? await deps.chatStore.replyText(after: message, conversationID: state.conversationID),
                   let mood = ChatTimelineEvidence.mood(reply: reply) {
                    do { try await deps.chatStore.addTimelineEvents(messageID: message.id, events: [mood]) }
                    catch { Log.app.warning("聊天情绪提示保存失败：\(error.localizedDescription)") }
                }
            } else {
                runInteractionReview(for: message, source: message.kind == .voice ? .voiceChat : .textChat)
            }
        }
        if !reviewed.isEmpty {
            await grantMainlineTicketIfEligible(conversationID: state.conversationID)
            Task { await deps.learningChat?.messageSaved(characterID: character.id) }
            inspectAppointmentAgreement()
            let memoryService = self.memoryService
            let character = self.character
            Task(priority: .utility) {
                guard !state.durableFollowups else { return }
                await memoryService.compressIfNeeded(
                    conversationID: state.conversationID, characterName: character.card.name,
                    characterRegionID: character.card.regionID)
            }
        }
        notifyConversationChanged()
        if !sharedPageVisible && (sharedReviewMessages.isEmpty || sharedReplyError) {
            stopSharedObservation()
        }
    }

    private func sharedVoiceStream(gateway: any SharedChatGateway, conversationID: UUID, userMessageID: UUID)
        -> AsyncThrowingStream<String, Error>
    {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                let deadline = ContinuousClock.now.advanced(by: .seconds(120))
                var generationID: UUID?
                var emitted = ""
                do {
                    while ContinuousClock.now < deadline {
                        try Task.checkCancellation()
                        let state = try await gateway.sharedReply(
                            conversationID: conversationID, userMessageID: userMessageID)
                        await self?.reloadMessages()
                        if let generation = state.generation,
                            generation.inputMessageIDs.contains(userMessageID)
                        {
                            if let generationID, generationID != generation.id {
                                throw AppError.storage("回复已重新开始，请重试")
                            }
                            generationID = generation.id
                            guard generation.partialText.hasPrefix(emitted) else {
                                throw AppError.storage("回复状态已更新，请重试")
                            }
                            let delta = String(generation.partialText.dropFirst(emitted.count))
                            if !delta.isEmpty {
                                continuation.yield(delta)
                                emitted = generation.partialText
                            }
                            if generation.status == "failed" || generation.status == "uncertain" {
                                throw AppError.storage("通话回复未完成，请重试")
                            }
                            if generation.status == "completed" {
                                continuation.finish()
                                return
                            }
                        }
                        if state.coveredMessageIDs.contains(userMessageID), !emitted.isEmpty {
                            continuation.finish()
                            return
                        }
                        try await Task.sleep(for: .milliseconds(250))
                    }
                    throw AppError.storage("通话回复等待超时，文字回复会继续同步")
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func reloadMessages() async {
        guard let conversation else { return }
        if let refreshed = try? await deps.chatStore.messages(conversationID: conversation.id), refreshed != messages {
            messages = refreshed
        }
    }

}
