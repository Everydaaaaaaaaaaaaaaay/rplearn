import BackendKit
import ChatFeature
import CoreKit
import DesignSystem
import DomainKit
import DictKit
import HomeFeature
import LLMKit
import MediaKit
import PersistenceKit
import SpeechKit
import SwiftData
import SwiftUI

/// Owns a disposable workspace. No production account stores or network clients enter it.
@MainActor
struct ProductionTutorialView: View {
    let character: CharacterDTO
    let environment: AppEnvironment
    let onFinish: @MainActor () async -> Bool
    @State private var workspace: TutorialWorkspace?
    @State private var step = 0
    @State private var translated = false
    @State private var lookedUp = false
    @State private var finishedEncounter = false
    @State private var encounterStarted = false
    @State private var atEncounterSummary = false
    @State private var activity: SceneActivity?
    @StateObject private var journey = ActivityJourneyCoordinator()
    @State private var saving = false
    @State private var error: String?
    @State private var guidanceExpanded = true
    @State private var speechStarts = 0

    private var ready: Bool {
        step == 0 ? translated : step == 1 ? lookedUp : step == 2 ? finishedEncounter : true
    }
    private var prompt: String {
        switch step {
        case 0: return translated ? "译文会显示在消息下方，菜单里也能播放整句咕。" : "长按旅伴的气泡，再点「翻译」试试咕。"
        case 1: return lookedUp ? "不必急着记住，遇到不懂的词随时点开就行嘎。" : "点一下 lovely 看释义，再点喇叭听听读音嘎。"
        case 2:
            if finishedEncounter || atEncounterSummary { return "加好友或道别都由你决定，这次练习不会留下记录咕。" }
            if encounterStarted { return "跟着故事往下看，遇到选项就选你想说的话咕。" }
            return "点场景里的行动，按「出发」体验一次相遇咕。"
        default: return "地图里的机票通向别的城市，剧情里还有新故事，剩下的惊喜就交给你好奇心嘎。"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { guidanceExpanded.toggle() } label: {
                    Label("上手练习", systemImage: guidanceExpanded ? "chevron.up" : "chevron.down")
                }
                .accessibilityIdentifier("tutorial.guide")
                .accessibilityValue(ProcessInfo.processInfo.environment["UI_TEST_TUTORIAL_AUDIO"] == "1" ? "audio:\(speechStarts)" : "")
                Spacer()
                Button("跳过教程", action: finish).disabled(saving)
                    .accessibilityIdentifier("tutorial.skip")
            }.font(.subheadline).padding(.horizontal, 16).padding(.vertical, 8)
            if guidanceExpanded {
                HStack(alignment: .top, spacing: 10) {
                    BrandMascotView(pose: step == 1 || step == 3 ? .reminder : .guide, size: 36, showsShadow: false)
                    Text(prompt).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }.padding(.horizontal, 16).padding(.bottom, 8)
            }
            if let workspace {
                if step < 2 {
                    NavigationStack {
                        ChatView(character: workspace.character, deps: workspace.chatDependencies(environment: environment) { event in
                            if event == "translation" { translated = true }
                            if event == "word" { lookedUp = true }
                        })
                    }
                } else if step == 2 {
                    ActivitiesView(journey: journey,
                        deps: workspace.homeDependencies(environment: environment) { event in
                            if event == "encounter" { encounterStarted = true; atEncounterSummary = false }
                            if event == "summary" { atEncounterSummary = true }
                            if event == "ending" || event == "friend" { finishedEncounter = true }
                        }, storageNamespace: workspace.id.uuidString,
                        isVisible: true, activity: $activity,
                        onClose: {
                            if activity != nil { journey.reset(); activity = nil; encounterStarted = false; atEncounterSummary = false }
                            else { advance() }
                        }, onChat: { _ in })
                } else {
                    VStack(spacing: 24) {
                        BrandMascotView(pose: .encouragement, size: 90, showsShadow: false)
                        Text("接下来，按你的节奏探索").font(.title2.bold())
                        Text("聊聊天、出门转转，或者打开地图挑个新去处。").foregroundStyle(.secondary)
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ProgressView("正在准备练习").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                if step < 3 {
                    Button("跳过这一步", action: advance).accessibilityIdentifier("tutorial.skipStep")
                    Spacer()
                }
                Button(step == 3 ? "开始我的旅程" : "继续") {
                    step == 3 ? finish() : advance()
                }.buttonStyle(.borderedProminent).disabled(!ready || saving)
                    .accessibilityIdentifier("tutorial.next")
            }.padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(Color.dsBackground)
        .task {
            guard workspace == nil else { return }
            do { workspace = try await TutorialWorkspace.make(character: character) }
            catch { self.error = "练习暂时无法打开，可以跳过后开始旅程。" }
        }
        .onReceive(NotificationCenter.default.publisher(for: .speechPlaybackDidBegin)) { _ in speechStarts += 1 }
        .onDisappear { journey.reset(); Task { await environment.speech.stopSpeaking() } }
        .alert("暂时无法出发", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("再试一次", action: finish)
            Button("稍后再试", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
    private func advance() {
        journey.reset(); activity = nil; guidanceExpanded = true
        Task { await environment.speech.stopSpeaking() }
        step = min(3, step + 1)
    }
    private func finish() {
        guard !saving else { return }
        saving = true
        Task {
            await environment.speech.stopSpeaking()
            if !(await onFinish()) { error = "旅伴选择还没有保存成功，请重试。" }
            saving = false
        }
    }
}

@MainActor
private final class TutorialWorkspace {
    let id = UUID()
    let container: ModelContainer
    let character: CharacterDTO
    let chat: ChatStore
    let roster: RosterStore
    let economy: EconomyStore
    let favorites: FavoritesStore
    let memory: MemoryStore
    let items: ItemStore
    let stories: StoryProgressStore
    let stubs: TicketStubStore
    let voice: VoiceMediaCoordinator
    let progression: LocalUserStateCoordinator

    private init(container: ModelContainer, character: CharacterDTO) {
        self.container = container; self.character = character
        chat = ChatStore(modelContainer: container)
        roster = RosterStore(modelContainer: container)
        economy = EconomyStore(modelContainer: container)
        favorites = FavoritesStore(modelContainer: container)
        memory = MemoryStore(modelContainer: container)
        items = ItemStore(modelContainer: container)
        stories = StoryProgressStore(modelContainer: container)
        stubs = TicketStubStore(modelContainer: container)
        progression = LocalUserStateCoordinator(economyStore: economy, itemStore: items, storyProgressStore: stories)
        voice = VoiceMediaCoordinator(backend: TutorialMediaBackend(), chatStore: chat,
            queueStore: VoiceMediaQueueStore(modelContainer: container), ownerStore: TutorialMediaOwner())
    }
    static func make(character: CharacterDTO) async throws -> TutorialWorkspace {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let roster = RosterStore(modelContainer: container)
        let economy = EconomyStore(modelContainer: container)
        let profile = try await economy.profile()
        let id = try await roster.addCharacter(card: character.card, difficulty: profile.difficultyLevel, isFriend: true)
        guard let localCharacter = try await roster.character(id: id) else { throw TutorialFailure.unavailable }
        let result = TutorialWorkspace(container: container, character: localCharacter)
        _ = try await economy.updateProfile { $0.currentRegionID = character.card.regionID; $0.hasCompletedOnboarding = true }
        let conversation = try await result.chat.openConversation(characterID: id)
        _ = try await result.chat.appendMessage(conversationID: conversation.id, role: .assistant,
            text: "That sounds lovely. Tell me more!", createdAt: .now)
        return result
    }
    func chatDependencies(environment: AppEnvironment, onEvent: @escaping @MainActor @Sendable (String) -> Void) -> ChatDependencies {
        let regionCatalog = environment.regionCatalog
        return ChatDependencies(tutorial: .init(onEvent: onEvent), chatStore: chat, rosterStore: roster,
            favorites: favorites, llm: TutorialLLM(), dictionary: environment.dictionary,
            grammarPoints: environment.grammarPoints, speech: environment.speech,
            translator: TranslationService(llm: TutorialLLM()),
            exampleTranslationActions: TutorialExampleTranslations.actions, audioSession: environment.audioSession,
            memoryStore: memory, itemStore: items, economyStore: economy, progression: progression,
            voiceMedia: voice, regionName: { regionCatalog.region(id: $0)?.nameZh ?? $0 }, replyDelayScale: 0)
    }
    func homeDependencies(environment: AppEnvironment, onEvent: @escaping @MainActor @Sendable (String) -> Void) -> HomeDependencies {
        HomeDependencies(tutorial: .init(onEvent: onEvent), economyStore: economy, itemStore: items,
            ticketStubStore: stubs, storyProgress: stories, regionCatalog: environment.regionCatalog,
            rosterStore: roster, chatStore: chat, favorites: favorites, dictionary: environment.dictionary,
            grammarPoints: environment.grammarPoints, speech: environment.speech, llm: TutorialLLM(),
            exampleTranslationActions: TutorialExampleTranslations.actions)
    }
}
private enum TutorialFailure: Error { case unavailable }
private struct TutorialLLM: LLMClient {
    func complete(_ request: LLMRequest) async throws -> String { throw TutorialFailure.unavailable }
    func stream(_ request: LLMRequest) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { $0.yield(.textDelta("That's interesting. Thanks for sharing!")); $0.yield(.finished); $0.finish() }
    }
}
private struct TutorialMediaOwner: VoiceMediaOwnerStore {
    func load() -> UUID? { nil }
    func save(_ userID: UUID) {}
}
private struct TutorialMediaBackend: VoiceMediaBackend {
    func completeVoiceMedia(assetID: UUID) async throws -> BackendMediaAsset { throw TutorialFailure.unavailable }
    func deleteVoiceMedia(assetID: UUID) async throws { throw TutorialFailure.unavailable }
    func reserveVoiceMedia(assetID: UUID, byteSize: Int, checksumSha256: String, contentType: String) async throws -> BackendMediaReservation { throw TutorialFailure.unavailable }
    func voiceMediaDownload(assetID: UUID) async throws -> BackendMediaDownload { throw TutorialFailure.unavailable }
}

/// Prepared translations for the opening practice; other entries use on-device translation.
private enum TutorialExampleTranslations {
    static let actions = DictExampleTranslationActions { request in
        translations[request.sentence].map { DictExampleTranslation(sentenceZh: $0) }
    }
    static let translations: [String: String] = [
        "more land": "更多土地",
        "more support": "更多支持",
        "more interesting": "更有趣",
        "more beautiful": "更美丽",
        "sound investments": "稳健的投资",
        "a sound economy": "稳健的经济",
        "the sound of rain on the roof": "雨落在屋顶上的声音",
        "the beautiful sound of music": "悦耳的音乐声",
        "This sounds interesting": "这听起来很有趣。",
        "She went `Mmmmm'": "她发出了“嗯——”的声音。",
        "The gun went `bang'": "枪“砰”的一声响了。",
        "He said that he wanted to marry her": "他说他想娶她。",
        "tell me what is bothering you": "告诉我你在烦恼什么。",
        "he wanted his share in cash": "他希望自己的那一份以现金支付。",
        "he bought 100 shares of IBM at the market price": "他按市价买了 100 股 IBM 股票。",
        "Our children share a love of music": "我们的孩子都热爱音乐。",
        "The two countries share a long border": "这两个国家有一条很长的共同边界。",
    ]
}
