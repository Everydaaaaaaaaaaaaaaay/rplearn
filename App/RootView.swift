import AuthFeature
import BackendKit
import BillingKit
import ChatFeature
import CoreKit
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
import UserNotifications

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
        if ProcessInfo.processInfo.environment["UI_TEST_HOME_DESTINATION"] == "activities" {
            var path = NavigationPath()
            path.append(HomeDestination.activities)
            _homePath = State(initialValue: path)
        } else if ProcessInfo.processInfo.environment["UI_TEST_HOME_DESTINATION"] == "mainline" {
            var path = NavigationPath()
            path.append(HomeDestination.mainline)
            _homePath = State(initialValue: path)
        } else if ProcessInfo.processInfo.environment["UI_TEST_HOME_DESTINATION"] == "cityStories" {
            var path = NavigationPath()
            path.append(HomeDestination.cityStories)
            _homePath = State(initialValue: path)
        }
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
                await reloadUnreadCount()
            }
            .task {
                if ProactiveMessageRoute.consumeNotificationTap() {
                    selectedTab = .messages
                }
                try? await UNUserNotificationCenter.current().setBadgeCount(unreadCount)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task {
                    if case .signedIn(let identity) = environment.authSession.phase {
                        guard identity.userID == activeUserID else {
                            await handleAuthenticationPhase()
                            return
                        }
                        do {
                            try await environment.userState.synchronize()
                            try await environment.contentSync.synchronize()
                            await environment.voiceMedia.synchronize()
                            await environment.billing.synchronize()
                        } catch {
                            if environment.authSession.handleAuthenticationFailure(error) {
                                return
                            }
                            Log.app.warning("后台同步暂未完成，继续使用本地状态：\(error)")
                        }
                    }
                    await environment.refreshProactiveMessages(requestAuthorization: false)
                    await reloadUnreadCount()
                    stateRevision += 1
                }
            }
            .onChange(of: selectedTab) { _, tab in
                guard tab == .messages else { return }
                Task {
                    await environment.refreshProactiveMessages(requestAuthorization: false)
                    stateRevision += 1
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .proactiveMessagesDidChange)) { _ in
                Task {
                    await reloadUnreadCount()
                    stateRevision += 1
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .didOpenProactiveMessage)) { _ in
                _ = ProactiveMessageRoute.consumeNotificationTap()
                selectedTab = .messages
            }
            .onChange(of: unreadCount) { _, count in
                Task { try? await UNUserNotificationCenter.current().setBadgeCount(count) }
            }
            .onReceive(NotificationCenter.default.publisher(for: ConversationReadState.didChange)) { _ in
                Task { await reloadUnreadCount() }
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
        return phaseID
    }

    private func handleAuthenticationPhase() async {
        switch environment.authSession.phase {
        case .loading:
            // 会话恢复在后台进行，本地界面无需等待。
            return
        case .signedOut:
            activeUserID = nil
            do {
                try await environment.activateGuest()
                stateRevision += 1
            } catch {
                Log.app.error("本地旅程载入失败：\(error)")
            }
        case .signedIn(let identity):
            showSignIn = false
            guard activeUserID != identity.userID else { return }
            do {
                _ = try await environment.activateUser(identity)
                guard case .signedIn(let currentIdentity) = environment.authSession.phase,
                      currentIdentity.userID == identity.userID
                else { return }
                activeUserID = identity.userID
                stateRevision += 1
            } catch {
                if environment.authSession.handleAuthenticationFailure(error) {
                    return
                }
                activeUserID = nil
                Log.app.warning("账号空间暂未载入，继续使用完整游客模式：\(error)")
                do {
                    try await environment.activateGuest()
                    stateRevision += 1
                } catch {
                    Log.app.error("游客空间回退失败：\(error)")
                }
            }
        }
    }

    private var appContent: some View {
        tabs
            .id(stateRevision)
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
                    MainlineListView(deps: homeDeps) { chapter in
                        homePath.append(chapter)
                    }
                case .cityStories:
                    CityStoryListView(deps: homeDeps) { chapter in
                        homePath.append(chapter)
                    }
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
                onProactiveMessagesChanged: { enabled in
                    Task { await environment.proactiveMessages.setEnabled(enabled) }
                },
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
            travelService: travelService,
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
            favorites: environment.favoritesStore,
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

    private func reloadUnreadCount() async {
        guard let friends = try? await environment.rosterStore.friends(),
              let summaries = try? await environment.chatStore.conversationSummaries()
        else { return }
        let friendIDs = Set(friends.map(\.id))
        unreadCount = summaries
            .filter { friendIDs.contains($0.characterID) }
            .reduce(into: 0) { total, summary in
                total += ConversationReadState.unreadCount(
                    conversationID: summary.conversationID,
                    assistantMessageDates: summary.assistantMessageDates
                )
            }
    }
}

#Preview {
    RootView(environment: AppEnvironment())
}
