import AuthFeature
import BackendKit
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
    @State private var activeUserID: UUID?
    @State private var activationAttempt = 0
    @State private var activationError: String?
    @State private var usingOfflineCache = false
    @State private var stateRevision = 0
    @Environment(\.scenePhase) private var scenePhase

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
        Group {
            switch environment.authSession.phase {
            case .loading:
                ProgressView("正在恢复旅程…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.dsBackground)
            case .signedOut:
                SignInView(session: environment.authSession)
            case .signedIn(let identity):
                if activeUserID == identity.userID {
                    authenticatedContent
                } else {
                    userStateGate(identity)
                }
            }
        }
        .onChange(of: environment.authSession.phase) { _, phase in
            if case .signedOut = phase {
                activeUserID = nil
                activationError = nil
                usingOfflineCache = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, activeUserID != nil else { return }
            Task {
                do {
                    try await environment.userState.synchronize()
                    usingOfflineCache = false
                    stateRevision += 1
                } catch {
                    if environment.authSession.handleAuthenticationFailure(error) {
                        return
                    }
                    usingOfflineCache = true
                }
            }
        }
    }

    private func userStateGate(_ identity: AuthIdentity) -> some View {
        VStack(spacing: 16) {
            if let activationError {
                Image(systemName: "wifi.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(Color.dsSunset)
                Text("无法载入旅程")
                    .font(.headline)
                Text(activationError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("重试") { activationAttempt += 1 }
                    .buttonStyle(.duoPrimary)
                    .frame(maxWidth: 240)
            } else {
                ProgressView("正在同步旅程…")
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsBackground)
        .task(id: "\(identity.userID.uuidString)-\(activationAttempt)") {
            activationError = nil
            do {
                let activation = try await environment.activateUser(identity)
                usingOfflineCache = activation == .offlineCache
                activeUserID = identity.userID
            } catch {
                if environment.authSession.handleAuthenticationFailure(error) {
                    return
                }
                activationError = error.localizedDescription
            }
        }
    }

    private var authenticatedContent: some View {
        tabs
            .id(stateRevision)
            .safeAreaInset(edge: .top, spacing: 0) {
                if usingOfflineCache {
                    Label("离线模式 · 联网后将自动同步", systemImage: "wifi.slash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.dsSunset)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                }
            }
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
                router: environment.llmRouter,
                economyStore: environment.economyStore,
                economyService: environment.economyService,
                profileCommands: environment.userState,
                memoryStore: environment.memoryStore,
                rosterStore: environment.rosterStore,
                chatStore: environment.chatStore,
                speech: environment.speech,
                authSession: environment.authSession,
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
            economyStore: environment.economyStore,
            progression: environment.userState
        )
    }

    private var storyDeps: StoryDependencies {
        StoryDependencies(
            storyProgress: environment.storyProgressStore,
            progression: environment.userState,
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
