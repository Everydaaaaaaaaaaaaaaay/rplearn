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

private final class CostWorkflowBundle: NSObject {}
private let costConfigPath = Bundle(for: CostWorkflowBundle.self).object(forInfoDictionaryKey: "LingoTripCostEvalConfig") as? String ?? ""

/// Opt-in native workflow. No fake chat requests: actions enter the shipping view model.
@Suite("真实使用成本工作流", .serialized, .enabled(if: !costConfigPath.isEmpty && !costConfigPath.hasPrefix("$(")))
@MainActor
struct LiveUsageCostWorkflowTests {
    private struct Config: Decodable {
        let baseURL: URL
        let outputDirectory: String
        let cases: [Persona]
    }
    private struct Persona: Decodable {
        let id: String, plan: String, userId: UUID, refreshToken: String, refreshTokenExpiresAt: String, sessionId: UUID
        let turnCount: Int, encounters: Int, grammarEvery: Int, translateEvery: Int, reopenAt: Int
        let difficulty: String?
        let characters: [CharacterCard]?
        let switchEvery: Int?
        let reopenEvery: Int?
        let voice: Bool
        let utterances: [String]
    }
    private final class Credentials: AuthCredentialStore, @unchecked Sendable {
        private let lock = NSLock()
        private var credential: StoredAuthCredential?
        init(_ value: StoredAuthCredential) { credential = value }
        func load() throws -> StoredAuthCredential? { lock.withLock { credential } }
        func save(_ value: StoredAuthCredential) throws { lock.withLock { credential = value } }
        func remove() throws { lock.withLock { credential = nil } }
    }
    private struct SilentSpeech: SpeechService {
        func speak(_ request: SpeechRequest) async {}
        func stopSpeaking() async {}
    }
    private actor Trace {
        struct Call: Codable, Sendable {
            let operationId: String; let task: String; let startedAt: String
            let inputBytes: Int; let messageCount: Int; let maxOutputTokens: Int
            var firstDeltaAt: String?; var finishedAt: String?; var status: String; var modelOutput: String?
        }
        private var calls: [Call] = []
        private var active = 0
        private var changed = Date()
        func begin(_ request: LLMRequest) -> Int {
            active += 1; changed = Date()
            calls.append(Call(operationId: request.operationID.uuidString.lowercased(), task: request.task.rawValue, startedAt: changed.ISO8601Format(), inputBytes: (request.system ?? "").utf8.count + request.messages.reduce(0) { $0 + $1.content.utf8.count }, messageCount: request.messages.count, maxOutputTokens: request.maxTokens, status: "started"))
            return calls.count - 1
        }
        func firstDelta(_ index: Int) { if calls[index].firstDeltaAt == nil { calls[index].firstDeltaAt = Date().ISO8601Format() } }
        func end(_ index: Int, status: String, output: String? = nil) {
            calls[index].modelOutput = output
            active -= 1; changed = Date(); calls[index].finishedAt = changed.ISO8601Format(); calls[index].status = status
        }
        func quiet() -> Bool { active == 0 && Date().timeIntervalSince(changed) > 2 }
        func snapshot() -> [Call] { calls }
    }
    private struct TracedProvider: LLMProvider {
        let upstream: BackendLLMProvider
        let trace: Trace
        func modelID(for tier: LLMTier) -> String { upstream.modelID(for: tier) }
        func complete(_ request: LLMRequest) async throws -> String {
            let index = await trace.begin(request)
            do { let output = try await upstream.complete(request); await trace.end(index, status: "completed", output: output); return output }
            catch { await trace.end(index, status: "failed: \(error.localizedDescription)"); throw error }
        }
        func stream(_ request: LLMRequest) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
            let index = await trace.begin(request)
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        var output = ""
                        for try await event in await upstream.stream(request) {
                            if case .textDelta(let text) = event { output += text; if !text.isEmpty { await trace.firstDelta(index) } }
                            continuation.yield(event)
                        }
                        await trace.end(index, status: "completed", output: output); continuation.finish()
                    } catch { await trace.end(index, status: "failed: \(error.localizedDescription)"); continuation.finish(throwing: error) }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }
    private struct Action: Codable { let kind: String; let startedAt: String; let status: String; let milliseconds: Int; let detail: String }
    private struct Turn: Codable {
        let index: Int; let characterName: String; let user: String; let reply: String
        let operationIDs: [String]; let remainingCredits: Double?
    }
    private struct Evidence: Codable {
        var status = "running"; var completedTurns = 0; var actions: [Action] = []; var calls: [Trace.Call] = []
        var turns: [Turn] = []; var characterCards: [CharacterCard] = []
        var startingCredits: Double?; var endingCredits: Double?
    }

    @Test("六类用户使用真实聊天和辅助功能并生成可核对的会话证据")
    func measuresNativeJourneys() async throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: URL(fileURLWithPath: costConfigPath)))
        #expect(["127.0.0.1", "localhost"].contains(config.baseURL.host ?? ""))
        guard ["127.0.0.1", "localhost"].contains(config.baseURL.host ?? "") else { throw NSError(domain: "CostEvalRequiresIsolatedGateway", code: 1) }
        for persona in config.cases {
            try await run(persona, config: config)
        }
    }
    private func run(_ persona: Persona, config: Config) async throws {
        var evidence = Evidence()
        let trace = Trace()
        let output = URL(fileURLWithPath: config.outputDirectory).appendingPathComponent("\(persona.id).json")
        func save() throws { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(evidence).write(to: output, options: .atomic) }
        try save()
        let dateParser = ISO8601DateFormatter(); dateParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expiry = try #require(dateParser.date(from: persona.refreshTokenExpiresAt))
        let backend = BackendClient(configuration: BackendConfiguration(baseURL: config.baseURL, requestTimeout: 130), credentialStore: Credentials(StoredAuthCredential(refreshToken: persona.refreshToken, refreshTokenExpiresAt: expiry, sessionID: persona.sessionId, userID: persona.userId)))
        let llm = LLMRouter(client: TracedProvider(upstream: BackendLLMProvider(backend: backend), trace: trace))
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let roster = RosterStore(modelContainer: container), chat = ChatStore(modelContainer: container), economy = EconomyStore(modelContainer: container), item = ItemStore(modelContainer: container)
        let tier: SubscriptionTier = persona.plan == "pro" ? .pro : persona.plan == "plus" ? .plus : .free
        let access = try await backend.accessSnapshot()
        evidence.startingCredits = access.credits?.remaining
        let level = DifficultyLevel(rawValue: persona.difficulty ?? "junior3") ?? .junior3
        try await economy.applyAuthoritativeEntitlement(tier: tier, friendSlotLimit: access.policy.friendSlotLimit)
        _ = try await economy.updateProfile { profile in profile.displayName = "Mia"; profile.difficultyLevel = level; profile.learningGoal = .dailyConversation; profile.studyStage = .university; profile.currentRegionID = "london" }
        let memory = MemoryStore(modelContainer: container)
        let translator = TranslationService(llm: llm)
        let dictionary = try DictDatabase(databaseURL: #require(Bundle.main.url(forResource: "learner_dictionary", withExtension: "sqlite")))
        let grammar = try GrammarPointStore(url: #require(Bundle.main.url(forResource: "grammar_points", withExtension: "json")))
        let deps = ChatDependencies(accessClient: backend, chatStore: chat, rosterStore: roster, favorites: FavoritesStore(modelContainer: container), llm: llm, dictionary: dictionary, grammarPoints: grammar, speech: SilentSpeech(), translator: translator, audioSession: AudioSessionCoordinator(), memoryStore: memory, itemStore: item, economyStore: economy, progression: LocalUserStateCoordinator(economyStore: economy, itemStore: item, storyProgressStore: StoryProgressStore(modelContainer: container)), voiceMedia: VoiceMediaCoordinator(backend: backend, chatStore: chat, queueStore: VoiceMediaQueueStore(modelContainer: container)))
        var card = CharacterCard(name: "Oliver Bennett", age: 24, gender: .male, nationality: "British", regionID: "london", occupation: "bookseller", hobbies: ["books", "walking", "indie music"], appearance: "brown hair and a green jacket", personality: "curious, kind, dry humour", speechStyle: "casual British English", background: "grew up in Kent and works near Covent Garden")
        card = persona.characters?.first ?? card
        do {
            let catalog = try RegionCatalog(url: #require(Bundle.main.url(forResource: "regions", withExtension: "json")))
            for index in 0..<persona.encounters {
                let start = Date()
                let region = try #require(catalog.region(id: "london"))
                let encounter = try await EncounterService(llm: llm).generateEncounter(origin: EncounterService.Origin.allCases[index % 3], region: region, userLevel: level, existingNames: [card.name], activityContext: index == 0 ? "browsing a used bookshop" : "visiting a riverside cafe")
                card = encounter.card
                evidence.actions.append(Action(kind: "encounter", startedAt: start.ISO8601Format(), status: encounter.isFallback ? "fallback" : "completed", milliseconds: Int(Date().timeIntervalSince(start)*1000), detail: card.name))
                try save()
            }
            let cards = persona.encounters > 0 ? [card] : (persona.characters ?? [card])
            evidence.characterCards = cards
            var characters: [CharacterDTO] = []
            for value in cards {
                let id = try await roster.addCharacter(card: value, difficulty: level, isFriend: true)
                characters.append(try #require(try await roster.character(id: id)))
            }
            var characterIndex = 0
            var model = ChatViewModel(character: characters[0], deps: deps)
            await model.load()
            for (index, text) in persona.utterances.enumerated() {
                let target = (persona.switchEvery ?? 0) > 0 ? (index / (persona.switchEvery ?? 1)) % characters.count : 0
                let periodicReopen = (persona.reopenEvery ?? 0) > 0 && index > 0 && index % (persona.reopenEvery ?? 1) == 0
                if target != characterIndex || (index == persona.reopenAt && index > 0) || periodicReopen {
                    characterIndex = target
                    model = ChatViewModel(character: characters[target], deps: deps); await model.load()
                }
                let previousMessageIDs = Set(model.messages.map(\.id))
                let callsBefore = await trace.snapshot().count
                let start = Date()
                if persona.voice {
                    let lease = try await backend.reserveVoice(operationID: UUID()); model.voiceLeaseID = lease.operationId
                    var response = ""
                    do { for try await delta in try await model.realtimeReplyStream(userText: text) { response += delta } }
                    catch { try? await backend.stopVoice(operationID: lease.operationId); throw error }
                    await model.saveRealtimeAssistant(spokenText: response, interrupted: false)
                    try await backend.stopVoice(operationID: lease.operationId)
                } else {
                    model.draft = text; await model.sendDraft()
                    while model.isStreaming || model.isWaitingForUserBurst {
                        if Date().timeIntervalSince(start) > 150 { model.cancelPendingReply(); throw NSError(domain: "TurnTimeout", code: 1) }
                        try await Task.sleep(for: .milliseconds(200))
                    }
                    if let error = model.errorMessage { throw NSError(domain: error, code: 1) }
                }
                try await settle(trace)
                await model.refreshMessages()
                let reply = model.messages.filter { $0.role == .assistant && !previousMessageIDs.contains($0.id) }.map(\.text).joined(separator: "\n")
                guard !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NSError(domain: "EmptyOrUnpersistedReply", code: 1) }
                evidence.completedTurns += 1
                evidence.actions.append(Action(kind: "chat", startedAt: start.ISO8601Format(), status: "completed", milliseconds: Int(Date().timeIntervalSince(start)*1000), detail: text))
                evidence.calls = await trace.snapshot(); try save()
                if persona.translateEvery > 0 && (index+1) % persona.translateEvery == 0, let message = model.messages.last(where: { $0.role == .assistant }) {
                    let t = Date(); await model.translate(message: message)
                    let cached = try await chat.messages(conversationID: #require(model.conversation?.id)).first(where: { $0.id == message.id })
                    if let cached { await model.translate(message: cached) }
                    evidence.actions.append(Action(kind: "translation_and_cache_reopen", startedAt: t.ISO8601Format(), status: cached?.translationZh == nil ? "failed" : "completed", milliseconds: Int(Date().timeIntervalSince(t)*1000), detail: "Repeated display must reuse stored translation"))
                }
                if persona.grammarEvery > 0 && (index+1) % persona.grammarEvery == 0 {
                    let t = Date(); _ = try await GrammarAnalysisService(llm: llm).analyze(sentence: text, learnerLevel: level.rawValue)
                    evidence.actions.append(Action(kind: "grammar", startedAt: t.ISO8601Format(), status: "completed", milliseconds: Int(Date().timeIntervalSince(t)*1000), detail: text))
                }
                try await settle(trace)
                let remaining = try await backend.accessSnapshot().credits?.remaining
                evidence.calls = await trace.snapshot()
                evidence.turns.append(Turn(index: index + 1, characterName: characters[characterIndex].card.name, user: text, reply: reply, operationIDs: evidence.calls.dropFirst(callsBefore).map(\.operationId), remainingCredits: remaining))
                try save()
            }
            evidence.status = "completed"
        } catch {
            let message = error.localizedDescription
            evidence.status = message.contains("积分") || message.contains("额度") || message.contains("CREDITS_EXHAUSTED") ? "quota_interrupted" : "failed"
            evidence.actions.append(Action(kind: "interruption", startedAt: Date().ISO8601Format(), status: evidence.status, milliseconds: 0, detail: message))
        }
        try await settle(trace)
        evidence.endingCredits = try? await backend.accessSnapshot().credits?.remaining
        evidence.calls = await trace.snapshot(); try save()
        print("COST_EVAL|\(persona.id)|\(evidence.completedTurns)/\(persona.turnCount)|\(evidence.status)")
    }
    private func settle(_ trace: Trace) async throws {
        let start = Date()
        while !(await trace.quiet()) {
            if Date().timeIntervalSince(start)>150 { throw NSError(domain: "AuxiliaryDrainTimeout", code: 1) }
            try await Task.sleep(for: .milliseconds(250))
        }
    }
}
