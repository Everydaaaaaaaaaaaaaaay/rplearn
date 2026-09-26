import BackendKit
import CoreKit
import DictKit
import DomainKit
import Foundation
import LLMKit
import MediaKit
import PersistenceKit
import SpeechKit
import SyncKit
import Testing
@testable import ChatFeature

private final class LearningBackendTestBundle: NSObject {}
private let learningBackendConfig = Bundle(for: LearningBackendTestBundle.self)
    .object(forInfoDictionaryKey: "LingoTripLearningBackendConfig") as? String ?? ""

/// 必须显式提供独立账号；普通回归不访问公网或模型。
@Suite("原生聊天到权威学习计数", .serialized,
       .enabled(if: !learningBackendConfig.isEmpty && !learningBackendConfig.hasPrefix("$(")))
@MainActor
struct LearningChatBackendIntegrationTests {
    private struct Config: Decodable {
        let baseURL: URL
        let userId: UUID
        let sessionId: UUID
        let refreshToken: String
        let refreshTokenExpiresAt: String
        let outputPath: String
    }
    private final class Credentials: AuthCredentialStore, @unchecked Sendable {
        private let lock = NSLock()
        private var value: StoredAuthCredential?
        init(_ value: StoredAuthCredential) { self.value = value }
        func load() -> StoredAuthCredential? { lock.withLock { value } }
        func save(_ credential: StoredAuthCredential) { lock.withLock { value = credential } }
        func remove() { lock.withLock { value = nil } }
    }
    private struct SilentSpeech: SpeechService {
        func speak(_ request: SpeechRequest) async {}
        func stopSpeaking() async {}
    }
    private actor ConversationProvider: LLMProvider {
        let upstream: BackendLLMProvider
        private(set) var requests = 0
        init(backend: BackendClient) { upstream = BackendLLMProvider(backend: backend) }
        nonisolated func modelID(for tier: LLMTier) -> String { "learning-live-conversation" }
        func complete(_ request: LLMRequest) async throws -> String {
            // 本检查只验证聊天，不另发辅助点评或记忆请求。
            throw CancellationError()
        }
        func stream(_ request: LLMRequest) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
            requests += 1
            guard request.task == .conversation, requests <= 2 else {
                return AsyncThrowingStream { $0.finish(throwing: CancellationError()) }
            }
            return await upstream.stream(request)
        }
    }

    @Test("真实聊天保存、服务端完成证据和重传共同保持单次计数", .timeLimit(.minutes(3)))
    func confirmsPersistedChat() async throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: URL(fileURLWithPath: learningBackendConfig)))
        guard ["rplearn.haruyuki.cn", "127.0.0.1", "localhost"].contains(config.baseURL.host ?? "") else {
            throw AppError.storage("学习验证必须使用指定测试服务。")
        }
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expiry = try #require(parser.date(from: config.refreshTokenExpiresAt))
        let backend = BackendClient(configuration: .init(baseURL: config.baseURL), credentialStore: Credentials(.init(refreshToken: config.refreshToken, refreshTokenExpiresAt: expiry, sessionID: config.sessionId, userID: config.userId)))
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let chat = ChatStore(modelContainer: container), roster = RosterStore(modelContainer: container)
        let economy = EconomyStore(modelContainer: container), items = ItemStore(modelContainer: container)
        _ = try await economy.updateProfile { $0.difficultyLevel = .junior1 }
        let sync = BackendContentSyncCoordinator(backend: backend, store: ContentSyncStore(modelContainer: container))
        _ = try await sync.activate(userID: config.userId)
        let tracker = LearningChatCoordinator(accountID: config.userId, backend: backend, contentSync: sync, defaultsSuiteName: "learning-live.\(config.userId)")
        defer { UserDefaults.standard.removePersistentDomain(forName: "learning-live.\(config.userId)") }
        let card = CharacterCard(name: "Oliver Bennett", age: 28, gender: .male, nationality: "British", regionID: "london", occupation: "bookseller", hobbies: ["books", "walking"], appearance: "green jacket", personality: "kind, curious, and calm")
        let id = try await roster.addCharacter(card: card, difficulty: .junior1, isFriend: true)
        let character = try #require(try await roster.character(id: id))
        let provider = ConversationProvider(backend: backend)
        let llm = LLMRouter(client: provider, maxRetries: 0)
        var deps = ChatDependencies(chatStore: chat, rosterStore: roster, favorites: FavoritesStore(modelContainer: container), llm: llm,
            dictionary: try DictDatabase(databaseURL: #require(Bundle.main.url(forResource: "learner_dictionary", withExtension: "sqlite"))),
            grammarPoints: try GrammarPointStore(url: #require(Bundle.main.url(forResource: "grammar_points", withExtension: "json"))),
            speech: SilentSpeech(), translator: TranslationService(llm: llm), audioSession: AudioSessionCoordinator(),
            memoryStore: MemoryStore(modelContainer: container), itemStore: items, economyStore: economy,
            progression: LocalUserStateCoordinator(economyStore: economy, itemStore: items, storyProgressStore: StoryProgressStore(modelContainer: container)),
            voiceMedia: VoiceMediaCoordinator(backend: backend, chatStore: chat, queueStore: VoiceMediaQueueStore(modelContainer: container)), replyDelayScale: 0)
        deps.learningChat = tracker
        let model = ChatViewModel(character: character, deps: deps)
        await model.load()
        #expect(try await backend.learningCharacter(id).characters == 0)
        model.draft = "Hi Oliver! I enjoyed walking past your bookshop today. What kind of books do you like?"
        await model.sendDraft()
        let deadline = ContinuousClock.now.advanced(by: .seconds(100))
        while model.isStreaming || model.isWaitingForUserBurst {
            guard ContinuousClock.now < deadline else { model.cancelPendingReply(); throw AppError.storage("真实聊天验证超时。") }
            try await Task.sleep(for: .milliseconds(100))
        }
        await model.refreshMessages()
        let user = try #require(model.messages.first(where: { $0.role == .user }))
        let assistant = model.messages.filter { $0.role == .assistant && !$0.isInterrupted }
        #expect(!assistant.isEmpty)
        #expect(user.learningOrigin != nil)
        #expect(assistant.allSatisfy { $0.learningOrigin != nil })
        try await sync.synchronizeAndWait()
        let expected = (user.text + assistant.map(\.text).joined()).filter { !$0.isWhitespace }.count
        let counted = try await backend.learningCharacter(id)
        #expect(counted.characters == expected)
        try await sync.synchronizeAndWait()
        let replay = try await backend.learningCharacter(id)
        #expect(replay.characters == expected)
        let evidence: [String: Int] = ["storedUserMessages": 1, "storedAssistantMessages": assistant.count, "expectedCharacters": expected, "serverCharacters": counted.characters, "afterReplayCharacters": replay.characters, "conversationRequests": await provider.requests]
        try JSONEncoder().encode(evidence).write(to: URL(fileURLWithPath: config.outputPath), options: .atomic)
        await tracker.deactivate(); await sync.deactivate()
    }
}
