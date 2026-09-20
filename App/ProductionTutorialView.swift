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

/// All learning state is disposable; inference uses the regular service so free
/// exploration behaves like the app. No tutorial roster or memories are synced.
@MainActor
struct ProductionTutorialView: View {
    let character: CharacterDTO
    let environment: AppEnvironment
    let onFinish: @MainActor () async -> Bool
    @State private var workspace: TutorialWorkspace?
    @State private var step = 0
    @State private var translated = false
    @State private var listened = false
    @State private var lookedUp = false
    @State private var finishedEncounter = false
    @State private var encounterStarted = false
    @State private var atEncounterSummary = false
    @State private var guidanceObscured = false
    @State private var hasPracticeBubble = true
    @State private var activity: SceneActivity?
    @State private var encounterChat: CharacterDTO?
    @StateObject private var journey = ActivityJourneyCoordinator()
    @State private var saving = false
    @State private var error: String?
    @State private var speechStarts = 0
    @State private var guideHeight: CGFloat = 120
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ready: Bool {
        !guidanceObscured && encounterChat == nil && (step == 0 ? translated && listened : step == 1 ? lookedUp : step == 2 ? finishedEncounter : true)
    }
    private var prompt: String {
        if step < 2, !hasPracticeBubble {
            return "可以先聊一句，等旅伴回复后再练习；右侧也能直接结束教程咕。"
        }
        switch step {
        case 0: return translated ? "长按发光的气泡，再点「播放」听整句咕。" : "长按发光的气泡，再点「翻译」试试咕。"
        case 1: return "点气泡里的英文单词看释义，也可以点小喇叭听读音嘎。"
        case 2:
            if finishedEncounter || atEncounterSummary { return "加好友或道别都由你决定，这次练习不会留下记录咕。" }
            if encounterStarted { return "轻点空白读下去，遇到选项就选你想说的话咕。" }
            if activity != nil { return "点「出发」，看看这次会遇见谁咕。" }
            return "点亮着的任意一个「行动」，先选你想做的事咕。"
        default: return "地图里的机票通向别的城市，还有新故事等着你，接下来就自由探索嘎。"
        }
    }

    var body: some View {
        Group {
            if let workspace {
                if step < 2 {
                    NavigationStack {
                        ChatView(character: workspace.character, deps: workspace.chatDependencies(
                            environment: environment, focus: "chat.bubble", onEvent: chatEvent))
                    }
                } else {
                    ActivitiesView(journey: journey,
                        deps: workspace.homeDependencies(environment: environment) { event in
                            if event == "encounter" { encounterStarted = true; atEncounterSummary = false }
                            if event == "summary" { atEncounterSummary = true }
                            if event == "presented" { guidanceObscured = true }
                            if event == "dismissed" { guidanceObscured = false }
                            if event == "ending" || event == "friend" {
                                finishedEncounter = true
                                step = 3
                            }
                        }, storageNamespace: workspace.id.uuidString,
                        isVisible: true, activity: $activity,
                        onClose: {
                            if activity != nil { journey.reset(); activity = nil; encounterStarted = false; atEncounterSummary = false }
                            else { step = 0; translated = false; listened = false; lookedUp = false }
                        }, onChat: { encounterChat = $0 })
                        .environment(\.tutorialGuideClearance, guideHeight + 32)
                }
            } else {
                ProgressView("正在准备练习").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlayPreferenceValue(TutorialTargetPreference.self) { targets in
            GeometryReader { geometry in
                if !guidanceObscured && encounterChat == nil {
                    let entrances = targets.filter { $0.key.hasPrefix("activity.entrance.") }
                        .map { geometry[$0.value] }
                    let choosingAction = step == 2 && !finishedEncounter && activity == nil
                    let latestBeat = step == 2 ? targets["activity.latestBeat"].map { geometry[$0] } : nil
                    let target = step < 2 ? targets["chat.bubble"].map { geometry[$0] }
                        : (choosingAction ? entrances.reduce(CGRect.null) { $0.union($1) }
                           : (targets["activity.action"] ?? targets["activity.continue"]).map { geometry[$0] })
                    if choosingAction {
                        Path { path in
                            path.addRect(CGRect(origin: .zero, size: geometry.size))
                            for rect in entrances {
                                path.addRoundedRect(in: rect.insetBy(dx: -8, dy: -8), cornerSize: CGSize(width: 20, height: 20))
                            }
                        }.fill(.black.opacity(0.48), style: FillStyle(eoFill: true))
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                    guide
                        .frame(width: min(340, max(240, geometry.size.width - 32)))
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { guideHeight = $0 }
                        .position(x: geometry.size.width / 2,
                                  y: guideY(in: geometry.size, target: target, avoiding: latestBeat))
                        .animation(reduceMotion || latestBeat != nil ? nil : .smooth(duration: 0.3), value: target)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: step)
                }
            }
        }
        .background(Color.dsBackground)
        .task {
            guard workspace == nil else { return }
            do { workspace = try await TutorialWorkspace.make(character: character) }
            catch { self.error = "练习暂时无法打开，可以跳过后开始旅程。" }
        }
        .task(id: "\(step)-\(ready)") {
            guard ready, workspace != nil else { return }
            do { try await Task.sleep(for: .seconds(step == 3 ? 4 : 1.6)) } catch { return }
            guard !Task.isCancelled else { return }
            if step == 3 { finish() }
            else {
                if step == 1 { await TutorialSpeech.resolve(environment.speech).stopSpeaking() }
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35)) { step += 1 }
            }
        }
        .fullScreenCover(item: $encounterChat) { person in
            if let workspace {
                NavigationStack {
                    ChatView(character: person, deps: workspace.chatDependencies(environment: environment, onEvent: { _ in }))
                        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("返回") { encounterChat = nil } } }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .speechPlaybackDidBegin)) { _ in speechStarts += 1 }
        .onDisappear {
            // Presenting a real subpage must not destroy the practice underneath.
            guard encounterChat == nil, !guidanceObscured else { return }
            journey.reset()
            Task { await TutorialSpeech.resolve(environment.speech).stopSpeaking() }
        }
        .alert("暂时无法出发", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("再试一次", action: finish)
            Button("稍后再试", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private var guide: some View {
        HStack(spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                BrandMascotView(pose: step == 1 || step == 3 ? .reminder : .guide, size: 56, showsShadow: false)
                    .phaseAnimator([false, true]) { content, lifted in
                        content.offset(y: reduceMotion ? 0 : (lifted ? -2 : 2))
                    } animation: { _ in .easeInOut(duration: 1.6) }
                    .id(step).transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.94)))
                Text(prompt).font(.callout.weight(.medium)).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(prompt).transition(.opacity)
            }
            .padding(.vertical, 14).padding(.leading, 8).padding(.trailing, 16)
            .background(.ultraThinMaterial.opacity(0.78), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.dsSkyDeep.opacity(0.18)))
            .shadow(color: .black.opacity(0.09), radius: 12, y: 5)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tutorial.guide")
            .accessibilityValue(ProcessInfo.processInfo.environment["UI_TEST_TUTORIAL_AUDIO"] == "1" ? "audio:\(speechStarts)" : "")
            Button(action: finish) {
                Image(systemName: "forward.end").font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44).background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain).disabled(saving)
            .accessibilityLabel("跳过教程").accessibilityIdentifier("tutorial.skip")
        }
        .animation(.easeInOut(duration: 0.25), value: prompt)
    }

    private func guideY(in size: CGSize, target: CGRect?, avoiding latestBeat: CGRect?) -> CGFloat {
        let half = guideHeight / 2
        let top = half + 70, bottom = max(top, size.height - half - 70)
        let preferred: CGFloat
        if let target, !target.isNull, target.maxY > 0, target.minY < size.height {
            let above = target.minY - half - (step < 2 ? 44 : 16)
            let below = target.maxY + half + 16
            if step >= 2, below <= bottom { preferred = max(top, below) }
            else if above >= top { preferred = min(bottom, above) }
            else { preferred = min(bottom, max(top, below)) }
        } else {
            preferred = min(bottom, max(top, size.height * 0.72))
        }
        if let latestBeat, latestBeat.maxY > 0, latestBeat.minY < size.height,
           latestBeat.intersects(CGRect(x: 0, y: preferred - half - 12, width: size.width, height: guideHeight + 24)) {
            // Protect new information even when the continue control is at the
            // bottom: move over older content instead of covering the last beat.
            return max(top, min(bottom, latestBeat.minY - half - 16))
        }
        return preferred
    }

    private func chatEvent(_ event: String) {
        if event == "hasBubble" { hasPracticeBubble = true }
        if event == "noBubble" { hasPracticeBubble = false }
        if event == "translation" { translated = true }
        if event == "manualPlayback", step == 0, translated { listened = true }
        if event == "word" { lookedUp = true }
        if event == "presented" { guidanceObscured = true }
        if event == "dismissed" { guidanceObscured = false }
    }

    private func finish() {
        guard !saving else { return }
        saving = true
        Task {
            await TutorialSpeech.resolve(environment.speech).stopSpeaking()
            if await onFinish() { await workspace?.cleanupVoiceFiles() }
            else { error = "旅伴选择还没有保存成功，请重试。" }
            saving = false
        }
    }
}

@MainActor
private final class TutorialWorkspace {
    let id = UUID()
    let session = ChatTutorialSession()
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
    func cleanupVoiceFiles() async {
        UserDefaults.standard.removePersistentDomain(forName: "lingotrip.tutorial.\(id.uuidString)")
        for person in (try? await roster.allCharacters()) ?? [] {
            for file in (try? await chat.clearConversationHistory(characterID: person.id)) ?? [] {
                VoiceMessageStorage.delete(fileName: file)
            }
        }
    }

    func chatDependencies(environment: AppEnvironment, focus: String? = nil, onEvent: @escaping @MainActor @Sendable (String) -> Void) -> ChatDependencies {
        let regionCatalog = environment.regionCatalog
        return ChatDependencies(tutorial: .init(session: session, focus: focus, onEvent: onEvent), chatStore: chat, rosterStore: roster,
            favorites: favorites, llm: environment.llmRouter, dictionary: environment.dictionary,
            grammarPoints: environment.grammarPoints, speech: TutorialSpeech.resolve(environment.speech),
            translator: environment.translator,
            audioSession: environment.audioSession,
            memoryStore: memory, itemStore: items, economyStore: economy, progression: progression,
            voiceMedia: voice, regionName: { regionCatalog.region(id: $0)?.nameZh ?? $0 })
    }
    func homeDependencies(environment: AppEnvironment, onEvent: @escaping @MainActor @Sendable (String) -> Void) -> HomeDependencies {
        HomeDependencies(tutorial: .init(onEvent: onEvent), economyStore: economy, itemStore: items,
            ticketStubStore: stubs, storyProgress: stories, regionCatalog: environment.regionCatalog,
            rosterStore: roster, chatStore: chat, favorites: favorites, dictionary: environment.dictionary,
            grammarPoints: environment.grammarPoints, speech: TutorialSpeech.resolve(environment.speech), llm: environment.llmRouter)
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
