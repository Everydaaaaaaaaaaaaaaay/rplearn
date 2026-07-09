import ChatFeature
import DomainKit
import FavoritesFeature
import HomeFeature
import MapFeature
import OnboardingFeature
import SettingsFeature
import SpeechKit
import StoryFeature
import SwiftUI

struct RootView: View {
    let environment: AppEnvironment

    @AppStorage("suppressVoiceUpgradePrompt") private var suppressVoicePrompt = false
    @State private var showVoiceUpgrade = false

    private var showsOnboarding: Binding<Bool> {
        Binding(
            get: { environment.needsOnboarding == true },
            set: { newValue in
                if !newValue {
                    environment.needsOnboarding = false
                }
            }
        )
    }

    var body: some View {
        tabs
            .fullScreenCover(isPresented: showsOnboarding) {
                OnboardingFlowView(
                    deps: OnboardingDependencies(
                        rosterStore: environment.rosterStore,
                        scriptURL: Bundle.main.url(forResource: "onboarding_chat", withExtension: "json")!
                    )
                ) { character in
                    Task {
                        await environment.completeOnboarding(selected: character)
                    }
                }
                .interactiveDismissDisabled()
            }
            .sheet(isPresented: $showVoiceUpgrade) {
                VoiceUpgradeSheet(
                    onPreview: {
                        Task {
                            await environment.speech.speak(
                                "Hello! This is how I sound. Nice to meet you.",
                                language: "en-US"
                            )
                        }
                    },
                    onNeverRemind: { suppressVoicePrompt = true }
                )
            }
            .task {
                await maybePromptVoiceUpgrade()
            }
    }

    /// 仅有机械音、未被永久关闭、且不在引导流程中时，弹出语音升级引导。
    private func maybePromptVoiceUpgrade() async {
        guard !suppressVoicePrompt,
              environment.needsOnboarding != true,
              !AppleTTSService.bestAvailableEnglishQuality().isNatural
        else { return }
        // 等主界面稳定后再弹，避免与启动/引导动画抢镜。
        try? await Task.sleep(for: .seconds(0.6))
        guard environment.needsOnboarding != true else { return }
        showVoiceUpgrade = true
    }

    private var tabs: some View {
        TabView {
            NavigationStack {
                HomeView(
                    deps: HomeDependencies(
                        economyStore: environment.economyStore,
                        storyProgress: environment.storyProgressStore,
                        regionCatalog: environment.regionCatalog,
                        rosterStore: environment.rosterStore,
                        chatStore: environment.chatStore,
                        llm: environment.llmRouter
                    ),
                    encounterChatBuilder: { character in
                        AnyView(ChatView(character: character, deps: chatDeps))
                    }
                )
                .navigationDestination(for: MainlineChapter.self) { chapter in
                    AVGStoryView(
                        storyID: chapter.storyID,
                        scriptURL: Bundle.main.url(forResource: chapter.storyID, withExtension: "json")!,
                        deps: StoryDependencies(
                            storyProgress: environment.storyProgressStore,
                            economyStore: environment.economyStore,
                            itemStore: environment.itemStore,
                            dictionary: environment.dictionary,
                            grammarPoints: environment.grammarPoints,
                            speech: environment.speech
                        )
                    )
                }
                .navigationDestination(for: HomeDestination.self) { destination in
                    switch destination {
                    case .map:
                        MapView(
                            deps: MapDependencies(
                                economyStore: environment.economyStore,
                                itemStore: environment.itemStore,
                                stubStore: environment.ticketStubStore,
                                travelService: environment.travelService,
                                economyService: environment.economyService,
                                regionCatalog: environment.regionCatalog
                            )
                        )
                    case .ticketStubs:
                        TicketStubsView(
                            stubStore: environment.ticketStubStore,
                            regionCatalog: environment.regionCatalog
                        )
                    }
                }
            }
            .tabItem {
                Label("主页", systemImage: "house")
            }

            NavigationStack {
                ConversationListView(deps: chatDeps)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink {
                                FavoritesView(deps: favoritesDeps)
                            } label: {
                                Image(systemName: "star")
                            }
                            .accessibilityLabel("收藏夹")
                        }
                    }
            }
            .tabItem {
                Label("消息", systemImage: "bubble.left.and.bubble.right")
            }

            NavigationStack {
                SettingsView(
                    settings: environment.llmSettings,
                    router: environment.llmRouter,
                    economyStore: environment.economyStore,
                    economyService: environment.economyService,
                    memoryStore: environment.memoryStore,
                    rosterStore: environment.rosterStore,
                    chatStore: environment.chatStore,
                    speech: environment.speech
                )
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
        }
    }

    private var chatDeps: ChatDependencies {
        ChatDependencies(
            chatStore: environment.chatStore,
            rosterStore: environment.rosterStore,
            favorites: environment.favoritesStore,
            llm: environment.llmRouter,
            dictionary: environment.dictionary,
            grammarPoints: environment.grammarPoints,
            speech: environment.speech,
            translator: environment.translator,
            audioSession: environment.audioSession,
            memoryStore: environment.memoryStore,
            itemStore: environment.itemStore,
            economyStore: environment.economyStore
        )
    }

    private var favoritesDeps: FavoritesDependencies {
        FavoritesDependencies(
            favorites: environment.favoritesStore,
            dictionary: environment.dictionary,
            grammarPoints: environment.grammarPoints,
            speech: environment.speech
        )
    }
}

#Preview {
    RootView(environment: AppEnvironment())
}
