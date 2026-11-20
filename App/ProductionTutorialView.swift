import BackendKit
import ChatFeature
import DesignSystem
import DomainKit
import HomeFeature
import MediaKit
import PersistenceKit
import SpeechKit
import SwiftData
import SwiftUI

@MainActor
struct TutorialReplayView: View {
    let environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var character: CharacterDTO?
    @State private var unavailable = false

    var body: some View {
        Group {
            if let character {
                ProductionTutorialView(character: character, environment: environment) {
                    dismiss()
                    return true
                }
            } else if unavailable {
                ContentUnavailableView {
                    Label("暂时无法打开练习", systemImage: "book.closed")
                } actions: {
                    Button("返回") { dismiss() }
                }
            } else {
                ProgressView("正在准备练习")
            }
        }
        .task {
            let options = (try? await environment.rosterStore.allCharacters().filter(\.isMainCharacter)) ?? []
            character = options.first(where: \.isFriend) ?? options.first
            unavailable = character == nil
        }
    }
}

/// Practice chats and outing receipts belong to a disposable workspace.
@MainActor
struct ProductionTutorialView: View {
    let character: CharacterDTO
    let environment: AppEnvironment
    let onFinish: @MainActor () async -> Bool

    private enum Step { case translateAndListen, lookup, outing, complete }

    @State private var workspace: TutorialWorkspace?
    @State private var step = Step.translateAndListen
    @State private var translated = false
    @State private var hasPracticeBubble = true
    @State private var lookedUp = false
    @State private var guidanceObscured = false
    @State private var encounterChat: CharacterDTO?
    @State private var journey = ActivityJourneyCoordinator()
    @State private var saving = false
    @State private var error: String?
    @State private var guideHeight: CGFloat = 120

    private var prompt: String {
        switch step {
        case .translateAndListen:
            if !hasPracticeBubble { return "等旅伴回复后就可以练习，也可以直接跳过教程咕。" }
            return translated ? "长按发光的气泡，再点「播放」听整句咕。" : "长按发光的气泡，再点「翻译」试试咕。"
        case .lookup:
            return "点气泡里的英文单词看释义，也可以点小喇叭听读音嘎。"
        case .outing:
            if journey.hasOpenOuting { return "点「继续」读故事，遇到选项就选你想说的话咕。" }
            return "左右滑动选个地点，点「去这里逛逛」咕。"
        case .complete:
            return "练习结束！接下来可以自由探索这座城市咕。"
        }
    }

    var body: some View {
        Group {
            if let workspace {
                switch step {
                case .translateAndListen, .lookup:
                    NavigationStack {
                        ChatView(character: workspace.character, deps: workspace.chatDependencies(
                            environment: environment, focus: "chat.bubble", onEvent: chatEvent))
                    }
                case .outing, .complete:
                    ActivitiesView(journey: journey, deps: workspace.homeDependencies(environment: environment),
                        storageNamespace: workspace.id.uuidString, isVisible: encounterChat == nil,
                        onClose: finish, onChat: { encounterChat = $0 },
                        storage: workspace.activityStorage, onCompleteOuting: { step = .complete })
                }
            } else if error != nil {
                ContentUnavailableView("暂时无法打开练习", systemImage: "book.closed")
            } else {
                ProgressView("正在准备练习").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlayPreferenceValue(TutorialTargetPreference.self) { targets in
            GeometryReader { geometry in
                if !guidanceObscured && encounterChat == nil {
                    let message = targets["chat.bubble"].map { geometry[$0] }
                    let menu = targets["chat.bubbleMenu"].map { geometry[$0] }
                    let latestBeat = targets["activity.latestBeat"].map { geometry[$0] }
                    let controls = targets.filter { $0.key.hasPrefix("activity.controls.") }
                        .map { geometry[$0.value] }
                        .reduce(CGRect.null) { $0.union($1) }
                    if let y = guideY(in: geometry.size, message: message, menu: menu, beat: latestBeat, controls: controls) {
                        guide(prompt: targets["activity.controls.finish"] != nil && step == .outing
                              ? "可以加为好友，也可以点「回到城市地点」结束练习咕。" : prompt)
                            .frame(width: min(340, max(0, geometry.size.width - 32)))
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { guideHeight = $0 }
                            .position(x: geometry.size.width / 2, y: y)
                    }
                }
            }
        }
        .background(Color.dsBackground)
        .task {
            guard workspace == nil else { return }
            do { workspace = try await TutorialWorkspace.make(character: character) }
            catch { self.error = "练习暂时无法打开，可以跳过后开始旅程。" }
        }
        .fullScreenCover(item: $encounterChat) { person in
            if let workspace {
                NavigationStack {
                    ChatView(character: person, deps: workspace.chatDependencies(environment: environment, onEvent: { _ in }))
                        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("返回") { encounterChat = nil } } }
                }
            }
        }
        .alert("暂时无法出发", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(workspace == nil ? "跳过教程" : "再试一次", action: finish)
            Button("关闭", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func guide(prompt: String) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                BrandMascotView(pose: step == .complete ? .celebrate : .guide, size: 48, showsShadow: false)
                Text(prompt)
                    .font(.callout.weight(.medium)).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12).padding(.leading, 8).padding(.trailing, 14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.dsSkyDeep.opacity(0.18)))
            .shadow(color: .black.opacity(0.09), radius: 12, y: 5)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tutorial.guide")
            .allowsHitTesting(false)

            Button(action: finish) {
                Image(systemName: step == .complete ? "checkmark" : "forward.end")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44).background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain).disabled(saving)
            .accessibilityLabel(step == .complete ? "完成教程" : "跳过教程")
            .accessibilityIdentifier(step == .complete ? "tutorial.finish" : "tutorial.skip")
        }
    }

    private func guideY(in size: CGSize, message: CGRect?, menu: CGRect?, beat: CGRect?, controls: CGRect) -> CGFloat? {
        let half = guideHeight / 2
        let viewport = CGRect(origin: .zero, size: size)
        let message = message.flatMap { $0.intersects(viewport) ? $0 : nil }
        let clearance = half + 12
        let reading = journey.hasOpenOuting
        let chatting = step == .translateAndListen || step == .lookup
        let top = half + (reading || chatting ? 62 : 12)
        let bottom = size.height - half - (chatting ? 62 : 12)
        guard bottom >= top else { return nil }
        let preferred = message.map { $0.minY - clearance - 12 }
            ?? size.height * (reading ? 0.25 : 0.64)
        let obstacles = [menu, message, beat, controls].compactMap { $0 }.filter { $0.intersects(viewport) }
        let candidates = [preferred, top, bottom] + obstacles.flatMap { [$0.minY - clearance, $0.maxY + clearance] }
        return candidates.map { min(bottom, max(top, $0)) }
            .filter { y in obstacles.allSatisfy { y <= $0.minY - clearance || y >= $0.maxY + clearance } }
            .min(by: { abs($0 - preferred) < abs($1 - preferred) })
    }

    private func chatEvent(_ event: String) {
        switch event {
        case "hasBubble": hasPracticeBubble = true
        case "noBubble": hasPracticeBubble = false
        case "translation": translated = true
        case "manualPlayback" where step == .translateAndListen && translated: step = .lookup
        case "word" where step == .lookup: lookedUp = true
        case "presented": guidanceObscured = true
        case "dismissed":
            guidanceObscured = false
            if lookedUp && step == .lookup {
                lookedUp = false
                step = .outing
            }
        default: break
        }
    }

    private func finish() {
        guard !saving else { return }
        saving = true
        Task {
            await TutorialSpeech.resolve(environment.speech).stopSpeaking()
            if await onFinish() {
                journey.reset()
                await workspace?.cleanup()
            } else {
                error = "旅伴选择还没有保存成功，请重试。"
            }
            saving = false
        }
    }
}

@MainActor
private final class TutorialWorkspace {
    private static let practiceSentence = "That sounds lovely. Tell me more!"
    let id = UUID()
    let session = ChatTutorialSession()
    let outings: TutorialOutingGateway
    let activityStorage: UserDefaults
    var storageName: String { "lingotrip.tutorial.\(id.uuidString)" }
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

    private init(container: ModelContainer, character: CharacterDTO, outings: TutorialOutingGateway) throws {
        self.character = character
        guard let storage = UserDefaults(suiteName: "lingotrip.tutorial.\(id.uuidString)") else {
            throw TutorialFailure.unavailable
        }
        activityStorage = storage
        self.outings = outings
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
        let id = try await roster.addCharacter(card: character.card, difficulty: character.difficultyLevel, isFriend: true)
        guard let localCharacter = try await roster.character(id: id) else { throw TutorialFailure.unavailable }
        let cityID = character.card.regionID
        let outings = try await Task.detached {
            try TutorialOutingGateway(cityID: cityID)
        }.value
        let result = try TutorialWorkspace(container: container, character: localCharacter, outings: outings)
        _ = try await economy.updateProfile {
            $0.currentRegionID = character.card.regionID
            $0.difficultyLevel = character.difficultyLevel
            $0.hasCompletedOnboarding = true
        }
        let conversation = try await result.chat.openConversation(characterID: id)
        _ = try await result.chat.appendMessage(conversationID: conversation.id, role: .assistant,
            text: practiceSentence, createdAt: .now)
        return result
    }
    func cleanup() async {
        activityStorage.removePersistentDomain(forName: storageName)
        for person in (try? await roster.allCharacters()) ?? [] {
            for file in (try? await chat.clearConversationHistory(characterID: person.id)) ?? [] {
                VoiceMessageStorage.delete(fileName: file)
            }
        }
    }

    func chatDependencies(environment: AppEnvironment, focus: String? = nil, onEvent: @escaping @MainActor @Sendable (String) -> Void) -> ChatDependencies {
        let regionCatalog = environment.regionCatalog
        var dependencies = ChatDependencies(tutorial: .init(session: session, focus: focus,
            preparedTranslations: [Self.practiceSentence: "听起来很棒，再跟我说说！"], onEvent: onEvent),
            chatStore: chat, rosterStore: roster,
            favorites: favorites, llm: environment.llmRouter, dictionary: environment.dictionary,
            grammarPoints: environment.grammarPoints, speech: TutorialSpeech.resolve(environment.speech),
            translator: environment.translator,
            audioSession: environment.audioSession,
            memoryStore: memory, itemStore: items, economyStore: economy, progression: progression,
            voiceMedia: voice, regionName: { regionCatalog.region(id: $0)?.nameZh ?? $0 })
        if case .signedIn = environment.authSession.phase, environment.onboardingPreviewMode == nil {
            dependencies.sharedGrammarAnalysis = environment.sharedGrammarAnalyzer
        }
        return dependencies
    }

    func homeDependencies(environment: AppEnvironment) -> HomeDependencies {
        HomeDependencies(economyStore: economy, itemStore: items,
            ticketStubStore: stubs, storyProgress: stories, regionCatalog: environment.regionCatalog,
            rosterStore: roster, favorites: favorites, dictionary: environment.dictionary,
            grammarPoints: environment.grammarPoints, speech: TutorialSpeech.resolve(environment.speech),
            outingGateway: outings, activityReleaseID: outings.catalog.releaseId)
    }
}
private enum TutorialFailure: Error { case unavailable }
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

/// Layout/state UI tests do not require the simulator's host audio device.
/// The separate audio integration test continues to use the real service.
private enum TutorialSpeech {
    static func resolve(_ live: any SpeechService) -> any SpeechService {
        #if DEBUG
        if ProcessInfo.processInfo.environment["UI_TEST_TUTORIAL_SILENT"] == "1" {
            return Silent()
        }
        #endif
        return live
    }
    #if DEBUG
    private struct Silent: SpeechService {
        func speak(_ request: SpeechRequest) async {}
        func stopSpeaking() async {}
    }
    #endif
}
