import AuthFeature
import BackendKit
import BillingKit
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
    @State private var homePath = NavigationPath()
    @State private var showSignIn = false
    @State private var showVoiceUpgrade = false
    @State private var activeUserID: UUID?
    @State private var activationAttempt = 0
    @State private var activationError: String?
    @State private var isActivatingAccount = false
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
        appContent
            .sheet(isPresented: $showSignIn) {
                NavigationStack {
                    SignInView(session: environment.authSession)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("稍后") {
                                    showSignIn = false
                                }
                            }
                        }
                }
            }
            .task(id: authenticationTaskID) {
                await handleAuthenticationPhase()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active,
                      let activeUserID,
                      case .signedIn(let identity) = environment.authSession.phase,
                      identity.userID == activeUserID
                else { return }
                Task {
                    do {
                        try await environment.userState.synchronize()
                        try await environment.contentSync.synchronize()
                        await environment.voiceMedia.synchronize()
                        await environment.billing.synchronize()
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

    private var authenticationTaskID: String {
        let phaseID: String = switch environment.authSession.phase {
        case .loading:
            "loading"
        case .signedOut:
            "guest"
        case .signedIn(let identity):
            "account-\(identity.userID.uuidString)"
        }
        return "\(phaseID)-\(activationAttempt)"
    }

    private func handleAuthenticationPhase() async {
        switch environment.authSession.phase {
        case .loading:
            // 会话恢复在后台进行，本地界面无需等待。
            return
        case .signedOut:
            activeUserID = nil
            activationError = nil
            isActivatingAccount = false
            usingOfflineCache = false
            do {
                try await environment.activateGuest()
                stateRevision += 1
            } catch {
                activationError = "本地旅程载入失败：\(error.localizedDescription)"
            }
        case .signedIn(let identity):
            showSignIn = false
            guard activeUserID != identity.userID else { return }
            activationError = nil
            isActivatingAccount = true
            defer { isActivatingAccount = false }
            do {
                let activation = try await environment.activateUser(identity)
                guard case .signedIn(let currentIdentity) = environment.authSession.phase,
                      currentIdentity.userID == identity.userID
                else { return }
                usingOfflineCache = activation == .offlineCache
                activeUserID = identity.userID
                stateRevision += 1
            } catch {
                if environment.authSession.handleAuthenticationFailure(error) {
                    return
                }
                activeUserID = nil
                activationError = error.localizedDescription
            }
        }
    }

    private var appContent: some View {
        tabs
            .id(stateRevision)
            .safeAreaInset(edge: .top, spacing: 0) {
                if isActivatingAccount {
                    Label("正在同步云端旅程，本地功能可继续使用", systemImage: "arrow.triangle.2.circlepath.icloud")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.dsSky)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                } else if activationError != nil {
                    HStack(spacing: 8) {
                        Label("云端同步失败，当前使用本地模式", systemImage: "wifi.exclamationmark")
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Button("重试") {
                            self.activationError = nil
                            activationAttempt += 1
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.dsSunset)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
                } else if usingOfflineCache {
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
                    Task {
                        await environment.completeOnboarding(
                            selected: character,
                            onboardingCommands: onboardingCommands
                        )
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
        NavigationStack(path: $homePath) {
            HomeView(
                deps: homeDeps,
                chatBuilder: { character in AnyView(ChatView(character: character, deps: chatDeps)) },
                onOpenMessages: {
                    selectedTab = .messages
                }
            )
            .navigationDestination(for: MainlineChapter.self) { chapter in
                storyView(storyID: chapter.storyID)
            }
            .navigationDestination(for: CityStoryChapter.self) { chapter in
                storyView(storyID: chapter.storyID)
            }
            .navigationDestination(for: HomeDestination.self) { destination in
                switch destination {
                case .stories:
                    StoryHubView(deps: homeDeps)
                case .mainline:
                    MainlineListView(deps: homeDeps)
                case .cityStories:
                    CityStoryListView(deps: homeDeps)
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
            MapView(deps: mapDeps) {
                selectedTab = .home
                homePath.append(HomeDestination.mainline)
            }
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
                economyService: economyService,
                profileCommands: profileCommands,
                memoryStore: environment.memoryStore,
                rosterStore: environment.rosterStore,
                chatStore: environment.chatStore,
                speech: environment.speech,
                authSession: environment.authSession,
                billing: environment.billing,
                isSignedIn: usesCloudState,
                onSignIn: { showSignIn = true },
                favoritesBuilder: { AnyView(FavoritesView(deps: favoritesDeps)) }
            )
        }
    }

    private func storyView(storyID: String) -> some View {
        AVGStoryView(
            storyID: storyID,
            scriptURL: Bundle.main.url(forResource: storyID, withExtension: "json")!,
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
            travelService: travelService,
            economyService: economyService,
            regionCatalog: environment.regionCatalog,
            storyProgress: environment.storyProgressStore
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
            progression: progression,
            voiceMedia: environment.voiceMedia
        )
    }

    private var storyDeps: StoryDependencies {
        StoryDependencies(
            storyProgress: environment.storyProgressStore,
            progression: progression,
            rosterStore: environment.rosterStore,
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

    private var usesCloudState: Bool {
        guard let activeUserID,
              case .signedIn(let identity) = environment.authSession.phase
        else { return false }
        return identity.userID == activeUserID
    }

    private var profileCommands: any ProfileCommandGateway {
        if usesCloudState {
            environment.userState
        } else {
            environment.localUserState
        }
    }

    private var onboardingCommands: any OnboardingCommandGateway {
        if usesCloudState {
            environment.userState
        } else {
            environment.localUserState
        }
    }

    private var progression: any ProgressionRewardGateway {
        if usesCloudState {
            environment.userState
        } else {
            environment.localUserState
        }
    }

    private var travelService: TravelService {
        usesCloudState ? environment.travelService : environment.localTravelService
    }

    private var economyService: EconomyService {
        usesCloudState ? environment.economyService : environment.localEconomyService
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
