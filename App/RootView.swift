import ChatFeature
import DesignSystem
import DomainKit
import FavoritesFeature
import HomeFeature
import MapFeature
import OnboardingFeature
import RosterFeature
import SettingsFeature
import SpeechKit
import StoryFeature
import SwiftUI

enum AppTab: Hashable {
    case home
    case map
    case messages
    case me
}

struct RootView: View {
    let environment: AppEnvironment

    @AppStorage("suppressVoiceUpgradePrompt") private var suppressVoicePrompt = false
    @AppStorage("lingotrip.unread.count") private var unreadCount = 0
    @State private var selectedTab: AppTab = .home
    @State private var showVoiceUpgrade = false

    init(environment: AppEnvironment) {
        self.environment = environment
        #if DEBUG
        let requested = ProcessInfo.processInfo.environment["UI_TEST_TAB"]
        let initial: AppTab = switch requested {
        case "map": .map
        case "messages": .messages
        case "me": .me
        default: .home
        }
        _selectedTab = State(initialValue: initial)
        #endif
    }

    private var showsOnboarding: Binding<Bool> {
        Binding(
            get: { environment.needsOnboarding == true },
            set: { newValue in
                if !newValue { environment.needsOnboarding = false }
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
                    Task { await environment.completeOnboarding(selected: character) }
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
            .task { await maybePromptVoiceUpgrade() }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            homeStack
                .tag(AppTab.home)
                .tabItem {
                    Label("首页", systemImage: "house")
                }
            mapStack
                .tag(AppTab.map)
                .tabItem {
                    Label("地图", systemImage: "map")
                }
            messagesStack
                .tag(AppTab.messages)
                .tabItem {
                    Label("消息", systemImage: "bubble.left.and.bubble.right")
                }
                .badge(unreadCount)
            meStack
                .tag(AppTab.me)
                .tabItem {
                    Label("我的", systemImage: "person")
                }
        }
        .tint(.dsSky)
    }

    private var homeStack: some View {
        NavigationStack {
            HomeView(
                deps: homeDeps,
                chatBuilder: { character in AnyView(ChatView(character: character, deps: chatDeps)) },
                onOpenMessages: {
                    selectedTab = .messages
                }
            )
            .navigationDestination(for: MainlineChapter.self) { chapter in
                storyView(chapter)
            }
            .navigationDestination(for: HomeDestination.self) { destination in
                switch destination {
                case .mainline:
                    MainlineListView(deps: homeDeps)
                case .activities:
                    ActivitiesView(
                        deps: homeDeps,
                        chatBuilder: { character in AnyView(ChatView(character: character, deps: chatDeps)) }
                    )
                }
            }
        }
    }

    private var mapStack: some View {
        NavigationStack {
            MapView(deps: mapDeps)
        }
    }

    private var messagesStack: some View {
        NavigationStack {
            ConversationListView(deps: chatDeps)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            RosterView(
                                deps: RosterDependencies(
                                    rosterStore: environment.rosterStore,
                                    economyStore: environment.economyStore
                                ),
                                chatBuilder: { character in
                                    AnyView(ChatView(character: character, deps: chatDeps))
                                }
                            )
                        } label: {
                            Image(systemName: "person.2.fill")
                        }
                        .accessibilityLabel("好友")
                    }
                }
        }
    }

    private var meStack: some View {
        NavigationStack {
            MyPageView(
                settings: environment.llmSettings,
                router: environment.llmRouter,
                economyStore: environment.economyStore,
                economyService: environment.economyService,
                memoryStore: environment.memoryStore,
                rosterStore: environment.rosterStore,
                chatStore: environment.chatStore,
                speech: environment.speech,
                favoritesBuilder: { AnyView(FavoritesView(deps: favoritesDeps)) }
            )
        }
    }

    private func storyView(_ chapter: MainlineChapter) -> some View {
        AVGStoryView(
            storyID: chapter.storyID,
            scriptURL: Bundle.main.url(forResource: chapter.storyID, withExtension: "json")!,
            deps: storyDeps
        )
    }

    private var homeDeps: HomeDependencies {
        HomeDependencies(
            economyStore: environment.economyStore,
            storyProgress: environment.storyProgressStore,
            regionCatalog: environment.regionCatalog,
            rosterStore: environment.rosterStore,
            chatStore: environment.chatStore,
            llm: environment.llmRouter
        )
    }

    private var mapDeps: MapDependencies {
        MapDependencies(
            economyStore: environment.economyStore,
            itemStore: environment.itemStore,
            stubStore: environment.ticketStubStore,
            travelService: environment.travelService,
            economyService: environment.economyService,
            regionCatalog: environment.regionCatalog
        )
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

    private var storyDeps: StoryDependencies {
        StoryDependencies(
            storyProgress: environment.storyProgressStore,
            economyStore: environment.economyStore,
            itemStore: environment.itemStore,
            dictionary: environment.dictionary,
            grammarPoints: environment.grammarPoints,
            speech: environment.speech
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

    private func maybePromptVoiceUpgrade() async {
        guard !suppressVoicePrompt,
              environment.needsOnboarding != true,
              !AppleTTSService.bestAvailableEnglishQuality().isNatural
        else { return }
        try? await Task.sleep(for: .seconds(0.6))
        guard environment.needsOnboarding != true else { return }
        showVoiceUpgrade = true
    }
}

#Preview {
    RootView(environment: AppEnvironment())
}
