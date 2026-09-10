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
        var fails: Bool
        var streamDelayMilliseconds: Int
        private(set) var translations = 0
        private(set) var requestedTasks: [LLMTask] = []
        init(
            response: String = "A complete answer.",
            fails: Bool = false,
            streamDelayMilliseconds: Int = 0
        ) {
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
            return "{\"has_issues\":false,\"issues\":[]}"
        }
        func stream(_ request: LLMRequest) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
            requestedTasks.append(request.task)
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
    private func fixture(_ provider: Provider = Provider()) async throws -> Fixture {
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
            speech: SilentSpeech(), translator: TranslationService(llm: llm),
            exampleTranslationActions: DictExampleTranslationActions(translate: { _ in nil }),
            audioSession: AudioSessionCoordinator(), memoryStore: MemoryStore(modelContainer: container),
            itemStore: items, economyStore: economy,
            progression: LocalUserStateCoordinator(economyStore: economy, itemStore: items, storyProgressStore: StoryProgressStore(modelContainer: container)),
            voiceMedia: VoiceMediaCoordinator(backend: backend, chatStore: chat, queueStore: VoiceMediaQueueStore(modelContainer: container)),
            replyDelayScale: 0
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
        #expect(tasks.dropFirst().allSatisfy { $0 == .coachReview })
        #expect(f.model.messages.contains { $0.role == .assistant })
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
        let f = try await fixture(Provider(response: ""))
        f.model.draft = "Hello."
        await f.model.sendDraft()
        try await settle(f.model)
        #expect(f.model.errorMessage != nil)
        #expect(f.model.messages.filter { $0.role == .user }.count == 1)
        #expect(f.model.messages.filter { $0.role == .assistant }.isEmpty)
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

    @Test("语音入口保存完整回复，文本翻译复用已存缓存")
    func voiceAndTranslationPersist() async throws {
        let provider = Provider()
        let f = try await fixture(provider)
        let raw = "First detail.\nSecond detail.\nThird detail.\nFourth detail.\nLast detail."
        await f.model.saveRealtimeAssistant(spokenText: raw, interrupted: false)
        let reply = try #require(f.model.messages.last)
        await f.model.translate(message: reply)
        let reopened = await f.reopen()
        let translated = try #require(reopened.messages.last)
        #expect(normalized(reopened.messages.map(\.text).joined(separator: " ")) == normalized(raw))
        #expect(translated.translationZh == "完整的翻译。")
        await reopened.translate(message: translated)
        #expect(await provider.translations == 1)
    }
}
