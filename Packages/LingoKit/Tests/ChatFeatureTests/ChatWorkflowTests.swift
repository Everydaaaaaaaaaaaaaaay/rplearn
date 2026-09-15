import BackendKit
import CoreKit
import DictKit
import DomainKit
import Foundation
import LLMKit
import MediaKit
import PersistenceKit
import SpeechKit
import Testing
@testable import ChatFeature

/// Shipping view model → real SwiftData stores → reopened view model. Only external services are replaced.
@Suite("聊天结果与失败恢复工作流", .serialized)
@MainActor
struct ChatWorkflowTests {
    private actor Provider: LLMProvider {
        var response: String
        var reviewResponse: String
        var fails: Bool
        var streamDelayMilliseconds: Int
        private(set) var translations = 0
        private(set) var requestedTasks: [LLMTask] = []
        private(set) var streamedMessages: [LLMMessage] = []
        init(
            response: String = "A complete answer.",
            reviewResponse: String = "{\"has_issues\":false,\"issues\":[]}",
            fails: Bool = false,
            streamDelayMilliseconds: Int = 0
        ) {
            self.reviewResponse = reviewResponse
            self.response = response
            self.fails = fails
            self.streamDelayMilliseconds = streamDelayMilliseconds
        }
        nonisolated func modelID(for tier: LLMTier) -> String { "workflow-fixture" }
        func complete(_ request: LLMRequest) async throws -> String {
            requestedTasks.append(request.task)
            if request.task == .translation {
                translations += 1
                return "完整的翻译。"
            }
            return reviewResponse
        }
        func stream(_ request: LLMRequest) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
            requestedTasks.append(request.task)
            streamedMessages = request.messages
            let response = response
            let fails = fails
            let streamDelayMilliseconds = streamDelayMilliseconds
            return AsyncThrowingStream { continuation in
                Task {
                    if streamDelayMilliseconds > 0 {
                        try? await Task.sleep(
                            for: .milliseconds(streamDelayMilliseconds)
                        )
                    }
                    if !response.isEmpty { continuation.yield(.textDelta(response)) }
                    if fails { continuation.finish(throwing: URLError(.networkConnectionLost)) }
                    else { continuation.yield(.finished); continuation.finish() }
                }
            }
        }

        func tasks() -> [LLMTask] { requestedTasks }
        func setResponse(_ text: String) { response = text }
    }
    private struct SilentSpeech: SpeechService {
        func speak(_ request: SpeechRequest) async {}
        func stopSpeaking() async {}
    }
    private struct NoCredentials: AuthCredentialStore {
        func load() throws -> StoredAuthCredential? { nil }
        func save(_ value: StoredAuthCredential) throws {}
        func remove() throws {}
    }
    @MainActor
    private struct Fixture {
        let model: ChatViewModel
        let deps: ChatDependencies
        func reopen() async -> ChatViewModel {
            let reopened = ChatViewModel(character: model.character, deps: deps)
            await reopened.load()
            return reopened
        }
    }
    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var date = Date.now
        func now() -> Date { lock.withLock { date } }
        func set(_ value: Date) { lock.withLock { date = value } }
    }

    private func fixture(_ provider: Provider = Provider(),
                         now: @escaping @Sendable () -> Date = { .now },
                         replyDelayScale: Double = 0) async throws -> Fixture {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let chat = ChatStore(modelContainer: container), roster = RosterStore(modelContainer: container)
        let economy = EconomyStore(modelContainer: container), items = ItemStore(modelContainer: container)
        _ = try await economy.updateProfile { $0.quizGloballyEnabled = false }
        let llm = LLMRouter(client: provider, maxRetries: 0)
        let backend = BackendClient(configuration: BackendConfiguration(baseURL: URL(string: "http://127.0.0.1:9")!), credentialStore: NoCredentials())
        let deps = ChatDependencies(
            chatStore: chat, rosterStore: roster, favorites: FavoritesStore(modelContainer: container),
            llm: llm,
            dictionary: try DictDatabase(databaseURL: #require(Bundle.main.url(forResource: "learner_dictionary", withExtension: "sqlite"))),
            grammarPoints: try GrammarPointStore(url: #require(Bundle.main.url(forResource: "grammar_points", withExtension: "json"))),
            speech: SilentSpeech(),
            exampleTranslationActions: DictExampleTranslationActions(translate: { _ in nil }),
            audioSession: AudioSessionCoordinator(), memoryStore: MemoryStore(modelContainer: container),
            itemStore: items, economyStore: economy,
            progression: LocalUserStateCoordinator(economyStore: economy, itemStore: items, storyProgressStore: StoryProgressStore(modelContainer: container)),
            voiceMedia: VoiceMediaCoordinator(backend: backend, chatStore: chat, queueStore: VoiceMediaQueueStore(modelContainer: container)),
            now: now, replyDelayScale: replyDelayScale
        )
        let id = try await roster.addCharacter(card: CharacterCard(name: "Workflow Friend", age: 25, gender: .female, nationality: "British", regionID: "london", occupation: "writer", hobbies: ["books"], appearance: "green coat", personality: "kind"), difficulty: .junior3, isFriend: true)
        let model = ChatViewModel(character: try #require(try await roster.character(id: id)), deps: deps)
        await model.load()
        return Fixture(model: model, deps: deps)
    }
    private func settle(_ model: ChatViewModel) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while model.isStreaming || model.isWaitingForUserBurst {
            guard ContinuousClock.now < deadline else {
                model.cancelPendingReply()
                Issue.record("Chat did not finish within the workflow deadline")
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        await model.refreshMessages()
    }
    private func normalized(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    @Test("聚焦与单字符不续期，四种字符续期，退出缩短等待")
    func composerEventsControlHandoff() async throws {
        let provider = Provider()
        let clock = TestClock()
        let f = try await fixture(provider, now: { clock.now() }, replyDelayScale: 0.001)
        defer { f.model.cancelPendingReply() }
        f.model.composerFocusChanged(true)
        f.model.draft = "Hello there."
        await f.model.sendDraft()
        let message = try #require(f.model.messages.last(where: { $0.role == .user }))
        let sentAt = message.createdAt
        #expect((8...9).contains(f.model.userTurnHandoffDate(after: message).timeIntervalSince(sentAt)))
        f.model.composerFocusChanged(false)
        clock.set(sentAt.addingTimeInterval(7))
        f.model.composerFocusChanged(true)
        #expect((8...9).contains(f.model.userTurnHandoffDate(after: message).timeIntervalSince(sentAt)))
        f.model.draft = "I"
        #expect((8...9).contains(f.model.userTurnHandoffDate(after: message).timeIntervalSince(sentAt)))
        f.model.draft = "what"
        #expect(f.model.userTurnHandoffDate(after: message) == sentAt.addingTimeInterval(32))
        clock.set(sentAt.addingTimeInterval(20))
        f.model.draft = "I also wanted to say"
        #expect(f.model.userTurnHandoffDate(after: message) == sentAt.addingTimeInterval(45))
        clock.set(sentAt.addingTimeInterval(21))
        f.model.composerFocusChanged(false)
        #expect(f.model.userTurnHandoffDate(after: message) == sentAt.addingTimeInterval(26))
        try await Task.sleep(for: .milliseconds(450))
        #expect(await provider.tasks().isEmpty)
        #expect(f.model.streamingText == nil)
        clock.set(sentAt.addingTimeInterval(1000))
        try await settle(f.model)
        #expect(f.model.messages.contains { $0.role == .assistant })
        #expect(f.model.draft == "I also wanted to say")
        #expect(await provider.tasks().filter { $0 == .conversation }.count == 1)
    }

    @Test("模型生成期间恢复输入会推迟投递，不会重复请求")
    func editingDuringGenerationDefersDelivery() async throws {
        let provider = Provider(streamDelayMilliseconds: 600)
        let clock = TestClock()
        let f = try await fixture(provider, now: { clock.now() }, replyDelayScale: 0.001)
        defer { f.model.cancelPendingReply() }
        f.model.draft = "Hello there."
        await f.model.sendDraft()
        let sentAt = try #require(f.model.messages.last(where: { $0.role == .user })).createdAt
        clock.set(sentAt.addingTimeInterval(1000))
        for _ in 0..<100 {
            if await provider.tasks().contains(.conversation) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await provider.tasks().filter { $0 == .conversation }.count == 1)
        f.model.composerFocusChanged(true)
        f.model.draft = "One more thing"
        try await Task.sleep(for: .milliseconds(750))
        #expect(!f.model.messages.contains { $0.role == .assistant })
        #expect(f.model.isWaitingForUserBurst)
        #expect(f.model.streamingText == nil)
        clock.set(sentAt.addingTimeInterval(1001))
        f.model.composerFocusChanged(false)
        clock.set(sentAt.addingTimeInterval(1007))
        try await settle(f.model)
        #expect(f.model.messages.contains { $0.role == .assistant })
        #expect(await provider.tasks().filter { $0 == .conversation }.count == 1)
    }

    @Test("模型完整回复经发送、落库、重新进入后逐字保留")
    func fullReplySurvivesReopen() async throws {
        let raw = "One useful detail.\nAnother useful detail.\nA third important detail.\nWhat happens next?\nKeep this final explanation too."
        let f = try await fixture(Provider(response: raw))
        f.model.draft = "Tell me the whole story."
        await f.model.sendDraft()
        try await settle(f.model)
        #expect(f.model.errorMessage == nil)
        let reopened = await f.reopen()
        #expect(reopened.messages.filter { $0.role == .user }.map(\.text) == ["Tell me the whole story."])
        #expect(normalized(reopened.messages.filter { $0.role == .assistant }.map(\.text).joined(separator: " ")) == normalized(raw))
        #expect(reopened.messages.map(\.id) == f.model.messages.map(\.id))
    }

    @Test("首条消息先完成 NPC 回复，后台点评不能抢占免费额度")
    func visibleReplyHasPriorityOverCoachReview() async throws {
        let provider = Provider(streamDelayMilliseconds: 180)
        let f = try await fixture(provider)
        f.model.draft = "I must say pretty good"
        await f.model.sendDraft()

        try await Task.sleep(for: .milliseconds(50))
        #expect(await provider.tasks() == [.conversation])

        try await settle(f.model)
        try await Task.sleep(for: .milliseconds(80))
        let tasks = await provider.tasks()
        #expect(tasks.first == .conversation)
        #expect(tasks == [.conversation, .coachReview])
        #expect(f.model.messages.contains { $0.role == .assistant })
    }

    @Test("到期小测与点评共用一次请求，题目保存到 NPC 消息")
    func quizSharesBackgroundReview() async throws {
        let provider = Provider(reviewResponse: #"{"coach_review":{"has_issues":false,"issues":[]},"relationship":{"warmth":0,"responsiveness":0,"respect":0,"empathy":0,"reciprocity":0,"disclosure":0,"resonance":0,"engagement":0,"boundary_harm":0,"repair":0,"significance":0,"confidence":0.8,"reason_zh":""},"growth":null,"quiz":{"question":"Choose the greeting","options":["Hello","Blue","Train","Book"],"answer":0,"explanation_zh":"Hello 是问候语"}}"#)
        let f = try await fixture(provider)
        _ = try await f.deps.economyStore.updateProfile { $0.quizGloballyEnabled = true }
        let conversation = try #require(f.model.conversation)
        for _ in 0..<9 {
            _ = try await f.deps.chatStore.appendAssistantReply(conversationID: conversation.id, texts: ["Hello there."])
        }
        f.model.draft = "Hello, how are you?"
        await f.model.sendDraft()
        try await settle(f.model)
        for _ in 0..<50 {
            let saved = try await f.deps.chatStore.messages(conversationID: conversation.id)
            if saved.contains(where: { $0.quizJSON != nil }) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let saved = try await f.deps.chatStore.messages(conversationID: conversation.id)
        #expect(await provider.tasks() == [.conversation, .coachReview])
        let target = try #require(saved.last(where: { $0.role == .assistant }))
        #expect(QuizService.decode(fromJSON: target.quizJSON)?.answer == 0)
        #expect(try await f.deps.chatStore.conversation(id: conversation.id)?.turnsSinceQuiz == 0)
    }

    @Test("退出或重启后会从未回复的最后一条用户消息恢复同一回复")
    func unansweredMessageResumesAfterReopen() async throws {
        let f = try await fixture()
        let conversation = try #require(f.model.conversation)
        _ = try await f.deps.chatStore.appendMessage(
            conversationID: conversation.id,
            role: .user,
            text: "Please come back to this message.",
            tokenEstimate: 7
        )

        let reopened = await f.reopen()
        try await settle(reopened)

        #expect(reopened.messages.filter { $0.role == .user }.count == 1)
        #expect(reopened.messages.filter { $0.role == .assistant }.map(\.text) == [
            "A complete answer."
        ])
    }

    @Test("连续发送新消息会取消旧计划且只生成一次最新回复")
    func latestUserMessageSupersedesPendingReply() async throws {
        let f = try await fixture(Provider(streamDelayMilliseconds: 120))
        f.model.draft = "First thought."
        await f.model.sendDraft()
        f.model.draft = "One more detail."
        await f.model.sendDraft()
        try await settle(f.model)

        #expect(f.model.messages.filter { $0.role == .user }.map(\.text) == [
            "First thought.",
            "One more detail.",
        ])
        #expect(f.model.messages.filter { $0.role == .assistant }.map(\.text) == [
            "A complete answer."
        ])
    }

    @Test("旧回复周期不能释放同一页面接管后的新租约")
    func staleCycleCannotReleaseReplacementLease() {
        let registry = NPCReplyLeaseRegistry.shared
        let conversationID = UUID()
        let ownerID = UUID()
        let oldCycleID = UUID()
        let newCycleID = UUID()
        let otherOwnerID = UUID()
        let oldMessageID = UUID()
        let newMessageID = UUID()

        #expect(registry.acquire(
            conversationID: conversationID,
            ownerID: ownerID,
            cycleID: oldCycleID,
            messageID: oldMessageID
        ))
        #expect(registry.acquire(
            conversationID: conversationID,
            ownerID: ownerID,
            cycleID: newCycleID,
            messageID: newMessageID
        ))
        registry.release(
            conversationID: conversationID,
            ownerID: ownerID,
            cycleID: oldCycleID,
            messageID: oldMessageID
        )
        #expect(!registry.acquire(
            conversationID: conversationID,
            ownerID: otherOwnerID,
            cycleID: UUID(),
            messageID: newMessageID
        ))
        registry.release(
            conversationID: conversationID,
            ownerID: ownerID,
            cycleID: newCycleID,
            messageID: newMessageID
        )
        let otherCycleID = UUID()
        #expect(registry.acquire(
            conversationID: conversationID,
            ownerID: otherOwnerID,
            cycleID: otherCycleID,
            messageID: newMessageID
        ))
        registry.release(
            conversationID: conversationID,
            ownerID: otherOwnerID,
            cycleID: otherCycleID,
            messageID: newMessageID
        )
    }

    @Test("同一未回复消息被两个页面恢复时只生成一次且双方都刷新")
    func duplicateViewModelsShareOneReply() async throws {
        let f = try await fixture(Provider(streamDelayMilliseconds: 120))
        let conversation = try #require(f.model.conversation)
        _ = try await f.deps.chatStore.appendMessage(
            conversationID: conversation.id,
            role: .user,
            text: "Please answer this once."
        )

        async let firstLoad = f.reopen()
        async let secondLoad = f.reopen()
        let (first, second) = await (firstLoad, secondLoad)
        try await settle(first)
        try await settle(second)

        #expect(first.messages.filter { $0.role == .assistant }.count == 1)
        #expect(second.messages.filter { $0.role == .assistant }.count == 1)
        #expect(first.messages.map(\.id) == second.messages.map(\.id))
    }

    @Test("生成期间重新进入不误报中断也不重复生成")
    func reopenDuringActiveGeneration() async throws {
        let provider = Provider(streamDelayMilliseconds: 400)
        let f = try await fixture(provider)
        f.model.draft = "Hello again."
        await f.model.sendDraft()
        for _ in 0..<100 {
            if f.model.messages.last?.isInterrupted == true { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(f.model.messages.last?.isInterrupted == true)
        let reopened = await f.reopen()
        #expect(reopened.errorMessage == nil)
        #expect(!reopened.canRetryUnansweredReply)
        #expect(reopened.isWaitingForUserBurst)
        try await settle(f.model)
        try await settle(reopened)
        #expect(reopened.messages.contains { $0.role == .assistant })
        #expect(reopened.errorMessage == nil)
        #expect(await provider.tasks().filter { $0 == .conversation }.count == 1)
    }

    @Test("重新进入后追加消息不会被旧观察任务清空状态")
    func sendWhileFollowingExistingProducer() async throws {
        let provider = Provider(streamDelayMilliseconds: 300)
        let f = try await fixture(provider)
        f.model.draft = "One moment."
        await f.model.sendDraft()
        for _ in 0..<100 {
            if f.model.messages.last?.isInterrupted == true { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let reopened = await f.reopen()
        reopened.draft = "Here is the rest of my question."
        await reopened.sendDraft()
        try await settle(f.model)
        try await settle(reopened)
        #expect(reopened.messages.last?.role == .assistant)
        #expect(reopened.messages.filter { $0.role == .assistant }.count == 1)
        #expect(!reopened.canRetryUnansweredReply)
    }

    @Test("会话尚未准备好时保留草稿")
    func draftSurvivesUnavailableConversation() async throws {
        let f = try await fixture()
        let unloaded = ChatViewModel(character: f.model.character, deps: f.deps)
        unloaded.draft = "Do not lose my draft."
        await unloaded.sendDraft()
        #expect(unloaded.draft == "Do not lose my draft.")
        #expect(!unloaded.isWaitingForUserBurst)
    }

    @Test("本地保存失败时保留草稿并提示错误")
    func draftSurvivesStorageFailure() async throws {
        let f = try await fixture()
        // Simulate a conversation removed between rendering and tapping Send.
        f.model.conversation?.id = UUID()
        f.model.draft = "Please keep this message."
        await f.model.sendDraft()
        #expect(f.model.draft == "Please keep this message.")
        #expect(f.model.errorMessage != nil)
        #expect(!f.model.isWaitingForUserBurst)
    }

    @Test("空模型输出不能当作成功回复")
    func emptyReplyShowsFailure() async throws {
        let provider = Provider(response: "")
        let f = try await fixture(provider)
        f.model.draft = "Hello."
        await f.model.sendDraft()
        try await settle(f.model)
        #expect(f.model.errorMessage != nil)
        #expect(f.model.messages.filter { $0.role == .user }.count == 1)
        #expect(f.model.messages.filter { $0.role == .assistant }.isEmpty)
        let calls = await provider.tasks().count
        let reopened = await f.reopen()
        try await Task.sleep(for: .milliseconds(80))
        #expect(await provider.tasks().count == calls)
        #expect(reopened.canRetryUnansweredReply)
        await provider.setResponse("Hi, I'm here now.")
        reopened.retryUnansweredReply()
        try await settle(reopened)
        #expect(reopened.messages.contains { $0.role == .assistant })
        #expect(!reopened.canRetryUnansweredReply)
    }

    @Test("电话转写也触发且只触发一次联合点评")
    func realtimeTriggersReview() async throws {
        let provider = Provider(response: "I love the breeze too.")
        let f = try await fixture(provider)
        let stream = try await f.model.realtimeReplyStream(userText: "The wind floats to on my face.")
        for try await _ in stream {}
        for _ in 0..<50 {
            if await provider.tasks().contains(.coachReview) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(await provider.tasks().filter { $0 == .coachReview }.count == 1)
    }

    @Test("电话空回复结束后，重新进入不会把转写自动重发")
    func realtimeFailureDoesNotAutoResend() async throws {
        let provider = Provider(response: "")
        let f = try await fixture(provider)
        let stream = try await f.model.realtimeReplyStream(userText: "Hello")
        await #expect(throws: LLMError.emptyResponse) {
            for try await _ in stream {}
        }
        let reopened = await f.reopen()
        try await Task.sleep(for: .milliseconds(80))
        #expect(await provider.tasks().filter { $0 == .conversation }.count == 1)
        #expect(reopened.canRetryUnansweredReply)
        #expect(reopened.messages.last?.text == "Hello")
    }

    @Test("流式断网保留已收到文字和中断标记，重新进入仍可见")
    func partialReplySurvivesNetworkFailure() async throws {
        let f = try await fixture(Provider(response: "Keep this partial reply", fails: true))
        f.model.draft = "Hello."
        await f.model.sendDraft()
        try await settle(f.model)
        let reopened = await f.reopen()
        let reply = try #require(reopened.messages.last(where: { $0.role == .assistant }))
        #expect(reply.text == "Keep this partial reply")
        #expect(reply.isInterrupted)
    }

    @Test("重试再次失败不能删掉原有中断内容")
    func retryFailurePreservesOriginal() async throws {
        let f = try await fixture(Provider(response: "", fails: true))
        await f.model.saveRealtimeAssistant(spokenText: "Already received words", interrupted: true)
        let original = try #require(f.model.messages.last)
        await f.model.retryInterrupted(messageID: original.id)
        try await settle(f.model)
        let reopened = await f.reopen()
        #expect(reopened.messages.contains { $0.id == original.id && $0.text == original.text && $0.isInterrupted })
        #expect(f.model.errorMessage != nil)
    }

    @Test("成功重试才替换旧中断消息，且不能删除普通消息")
    func retrySuccessReplacesOnlyInterruptedMessage() async throws {
        let f = try await fixture()
        await f.model.saveRealtimeAssistant(spokenText: "Partial", interrupted: true)
        let original = try #require(f.model.messages.last)
        await f.model.retryInterrupted(messageID: original.id)
        try await settle(f.model)
        #expect(!f.model.messages.contains { $0.id == original.id })
        let complete = try #require(f.model.messages.last)
        #expect(complete.text == "A complete answer.")
        await f.model.retryInterrupted(messageID: complete.id)
        #expect(!f.model.isWaitingForUserBurst)
        #expect(f.model.messages.contains { $0.id == complete.id })
        f.model.cancelPendingReply()
    }

    @Test("语音发送保留录音和时长，只向模型发送转写且不触发独立口语点评")
    func voiceMessageUsesTranscriptWithoutSpeechFeedback() async throws {
        let provider = Provider()
        let f = try await fixture(provider)
        let transcript = "Could we meet at the bookshop tomorrow?"
        let capture = VoiceRecorder.Capture(fileName: "voice-fixture.m4a", duration: 4.2, transcript: transcript)
        await f.model.sendVoice(capture: capture)
        try await settle(f.model)
        let reopened = await f.reopen()
        let voice = try #require(reopened.messages.first(where: { $0.role == .user }))
        #expect(voice.kind == .voice)
        #expect(voice.text == transcript)
        #expect(voice.audioFileName == capture.fileName)
        #expect(voice.audioDuration == capture.duration)
        #expect(voice.speechReviewJSON == nil)
        let sent = await provider.streamedMessages
        #expect(sent.contains(.user(transcript)))
        #expect(!sent.contains { $0.content.contains("voice-fixture.m4a") })
        let tasks = await provider.tasks()
        #expect(tasks.contains(.conversation))
        #expect(!tasks.contains { $0.rawValue == "speech_feedback" })
        #expect(reopened.messages.contains { $0.role == .assistant })
    }

    @Test("语音入口保存完整回复，文本翻译复用已存缓存")
    func voiceAndTranslationPersist() async throws {
        let provider = Provider()
        let f = try await fixture(provider)
        let raw = "First detail.\nSecond detail.\nThird detail.\nFourth detail.\nLast detail."
        await f.model.saveRealtimeAssistant(spokenText: raw, interrupted: false)
        let reply = try #require(f.model.messages.last)
        var localCalls = 0
        f.model.localTranslation = { text in
            #expect(text == reply.text)
            localCalls += 1
            return "完整的翻译。"
        }
        await f.model.translate(message: reply)
        await f.model.translate(message: reply) // A stale DTO must also reuse persisted state.
        #expect(localCalls == 1)
        let reopened = await f.reopen()
        let translated = try #require(reopened.messages.last)
        #expect(normalized(reopened.messages.map(\.text).joined(separator: " ")) == normalized(raw))
        #expect(translated.translationZh == "完整的翻译。")
        await reopened.translate(message: translated)
        #expect(await provider.translations == 0)
        #expect(await provider.tasks().isEmpty)
    }
    @Test("系统翻译失败或返回空白不调用 AI，且可以重试")
    func localTranslationFailureCanRetryWithoutAI() async throws {
        let provider = Provider()
        let f = try await fixture(provider)
        await f.model.saveRealtimeAssistant(spokenText: "Hello there.", interrupted: false)
        let message = try #require(f.model.messages.last)
        await f.model.translate(message: message) // No bound system session.
        #expect(f.model.errorMessage?.contains("Apple") == true)
        f.model.localTranslation = { _ in nil }
        await f.model.translate(message: message)
        f.model.localTranslation = { _ in "  \n " }
        await f.model.translate(message: message)
        #expect(f.model.messages.last?.translationZh == nil)
        #expect(f.model.translatingMessageIDs.isEmpty)
        f.model.localTranslation = { _ in "你好。" }
        await f.model.translate(message: message)
        #expect(f.model.messages.last?.translationZh == "你好。")
        #expect(await provider.tasks().isEmpty)
    }

    @Test("重复点击合并进行中的本地翻译")
    func duplicateLocalTranslationIsCoalesced() async throws {
        let provider = Provider()
        let f = try await fixture(provider)
        await f.model.saveRealtimeAssistant(spokenText: "Hello.", interrupted: false)
        let message = try #require(f.model.messages.last)
        var continuation: CheckedContinuation<String?, Never>?
        var calls = 0
        f.model.localTranslation = { _ in
            calls += 1
            return await withCheckedContinuation { continuation = $0 }
        }
        let first = Task { await f.model.translate(message: message) }
        while continuation == nil { await Task.yield() }
        await f.model.translate(message: message)
        #expect(calls == 1)
        continuation?.resume(returning: "你好。")
        await first.value
        #expect(f.model.messages.last?.translationZh == "你好。")
        #expect(await provider.tasks().isEmpty)
    }

}

@Suite("Apple 翻译请求生命周期", .serialized)
@MainActor
struct AppleTranslatorQueueTests {
    @Test("并发请求共用会话且新消息不会打断正在翻译的消息")
    func queuedRequestsShareSession() async throws {
        let translator = AppleTranslator()
        let first = Task { await translator.enqueue("First.") }
        while translator.configuration == nil { await Task.yield() }
        let sessionID = translator.sessionID
        let batch = translator.takeBatch(sessionID: sessionID)
        #expect(batch.count == 1)
        let second = Task { await translator.enqueue("Second.") }
        // Wait for the second task to run on this actor before inspecting its queue.
        await Task.yield()
        #expect(translator.sessionID == sessionID)
        translator.complete(try #require(batch.first?.id), with: "第一句。")
        #expect(await first.value == "第一句。")
        var next = translator.takeBatch(sessionID: sessionID)
        while next.isEmpty {
            await Task.yield()
            next = translator.takeBatch(sessionID: sessionID)
        }
        translator.complete(try #require(next.first?.id), with: "第二句。")
        translator.finishSession(sessionID)
        #expect(await second.value == "第二句。")
    }

    @Test("下载失败释放等待请求，后续可以重新启动")
    func preparationFailureAndRetry() async {
        let translator = AppleTranslator()
        let first = Task { await translator.enqueue("Hello.") }
        while translator.configuration == nil { await Task.yield() }
        let oldID = translator.sessionID
        translator.finishSession(oldID, failed: true)
        #expect(await first.value == nil)
        let retry = Task { await translator.enqueue("Hello.") }
        while translator.sessionID == oldID { await Task.yield() }
        translator.finishSession(oldID, failed: true) // A stale session cannot cancel the retry.
        #expect(translator.takeBatch(sessionID: translator.sessionID).count == 1)
        translator.cancelAll()
        #expect(await retry.value == nil)
        #expect(translator.configuration == nil)
    }

    @Test("取消请求移出队列，离开页面释放所有等待者")
    func cancellationCleansQueue() async {
        let translator = AppleTranslator()
        let task = Task { await translator.enqueue("Hello.") }
        while translator.configuration == nil { await Task.yield() }
        task.cancel()
        #expect(await task.value == nil)
        #expect(translator.takeBatch(sessionID: translator.sessionID).isEmpty)
        translator.cancelAll()
        #expect(translator.configuration == nil)
    }
}
