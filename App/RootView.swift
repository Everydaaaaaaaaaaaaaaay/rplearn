import AuthFeature
import BackendKit
import BillingKit
import ChatFeature
import CoreKit
import DesignSystem
import DictKit
import DomainKit
import FavoritesFeature
import HomeFeature
import MapFeature
import OnboardingFeature
import PlacementFeature
import RosterFeature
import SettingsFeature
import SpeechKit
import StoryFeature
import SwiftUI
import UserNotifications

struct RootView: View {
    private static let proactiveRefreshDelay = Duration.milliseconds(900)

    private static var disablesBackgroundRefreshForUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] == "1"
        #else
        false
        #endif
    }

    let environment: AppEnvironment

    @AppStorage("lingotrip.unread.count") private var unreadCount = 0
    @State private var selectedTab: AppTab = .messages
    @State private var homePath = NavigationPath()
    @State private var activeHomeDestination: HomeDestination?
    @State private var mePath: [MeDestination] = []
    @State private var activationError: String?
    @State private var showUsage = false
    @State private var signInAfterUsage = false
    @State private var showSignIn = false
    @State private var loginReason: String?
    @State private var showLondonEpisode = false
    @State private var activeSceneActivity: SceneActivity?
    @State private var showPlacementTest = false
    @State private var showOnboardingPlacement = false
    @State private var placementCompletionRevision = 0
    @State private var activeUserID: UUID?
    @State private var isGuestReady = false
    @State private var stateRevision = 0
    @State private var shouldRefreshAfterBackground = false
    @State private var isInitialContentReady = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(environment: AppEnvironment) {
        self.environment = environment
        #if DEBUG
        let requested = ProcessInfo.processInfo.environment["UI_TEST_TAB"]
        if ProcessInfo.processInfo.environment["UI_TEST_LONDON_EPISODE"] == "1" {
            _showLondonEpisode = State(initialValue: true)
        }
        let initial: AppTab = switch requested {
        case "messages": .messages
        case "contacts": .contacts
        case "home", "map": .home
        case "me": .me
        case "relationship": .relationshipLab
        default:
            ProcessInfo.processInfo.environment["UI_TEST_HOME_DESTINATION"] == nil
                ? .messages
                : .home
        }
        _selectedTab = State(initialValue: initial)
        if requested == "map" {
            _activeHomeDestination = State(initialValue: .map)
        } else if ProcessInfo.processInfo.environment["UI_TEST_HOME_DESTINATION"] == "activities" {
            _activeHomeDestination = State(initialValue: .activities)
        } else if ProcessInfo.processInfo.environment["UI_TEST_HOME_DESTINATION"] == "mainline" {
            var path = NavigationPath()
            path.append(HomeDestination.mainline)
            _homePath = State(initialValue: path)
            _activeHomeDestination = State(initialValue: .stories)
        } else if ProcessInfo.processInfo.environment["UI_TEST_HOME_DESTINATION"] == "cityStories" {
            var path = NavigationPath()
            path.append(HomeDestination.cityStories)
            _homePath = State(initialValue: path)
            _activeHomeDestination = State(initialValue: .stories)
        }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-test-placement")
            || ProcessInfo.processInfo.environment["UI_TEST_PLACEMENT"] == "1"
            || ProcessInfo.processInfo.environment["UI_TEST_PLACEMENT_LEVEL_SELECTION"] == "1"
            || ProcessInfo.processInfo.environment["UI_TEST_PLACEMENT_QUESTION"] == "1"
        {
            _showPlacementTest = State(initialValue: true)
        }
        #endif
    }
    private var showsOnboarding: Binding<Bool> {
        Binding(
            get: {
                (environment.needsOnboarding == true || forcesOnboardingStoryForUITest)
                    && !showPlacementTest
            },
            set: { newValue in
                if !newValue { environment.needsOnboarding = false }
            }
        )
    }
    private var forcesOnboardingStoryForUITest: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["UI_TEST_ONBOARDING_STORY"] == "1"
        #else
        false
        #endif
    }

    var body: some View {
        appContent
            .fullScreenCover(isPresented: $showLondonEpisode) {
                #if DEBUG
                LondonEpisodeView(deps: storyDeps, storageNamespace: activeUserID?.uuidString ?? "guest",
                                  resourceName: ProcessInfo.processInfo.environment["UI_TEST_DEPARTURE_RESOURCE"] ?? "departures_london_v1")
                #endif
            }
            .overlay {
                if let activationError {
                    VStack(spacing: 16) {
                        Text("旅程尚未载入").font(.headline)
                        Text(activationError).font(.subheadline)
                        Button("重试") { Task { await handleAuthenticationPhase() } }
                        Button("退出此账号") { Task { await environment.authSession.logout() } }
                    }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.background)
                }
            }
            .overlay {
                if !isInitialContentReady {
                    Color("BrandLaunchBackground")
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                }
            }
            .alert("登录后继续", isPresented: Binding(
                get: { loginReason != nil }, set: { if !$0 { loginReason = nil } }
            )) {
                Button("登录") { loginReason = nil; showSignIn = true }
                Button("稍后", role: .cancel) { loginReason = nil }
            } message: {
                Text(loginReason ?? "")
            }
            .sheet(isPresented: $showUsage, onDismiss: {
                if signInAfterUsage { signInAfterUsage = false; showSignIn = true }
            }) {
                UsageAccessView(backend: environment.backendClient, billing: environment.billing) {
                    showUsage = false
                    signInAfterUsage = true
                }
            }
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
                if environment.needsOnboarding != nil,
                   selectedTab != .home || activeHomeDestination != nil || !homePath.isEmpty {
                    isInitialContentReady = true
                }
                await refreshProactiveMessagesAfterInterfaceSettles(
                    requestAuthorization: true
                )
            }
            .task(id: "\(authenticationTaskID)-\(scenePhase)-\(activeUserID?.uuidString ?? "none")-\(isGuestReady)") {
                guard scenePhase == .active else { return }
                switch environment.authSession.phase {
                case .signedIn(let identity): guard identity.userID == activeUserID else { return }
                case .signedOut: guard isGuestReady else { return }
                case .loading: return
                }
                while !Task.isCancelled {
                    await environment.npcAvatars.synchronize()
                    do { try await Task.sleep(for: .seconds(60)) }
                    catch { return }
                }
            }
            .task {
                if ProactiveMessageRoute.consumeNotificationTap() {
                    selectedTab = .messages
                }
                try? await UNUserNotificationCenter.current().setBadgeCount(unreadCount)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    shouldRefreshAfterBackground = true
                    return
                }
                // 权限弹窗只会让应用短暂 inactive。此时刷新根列表既没有必要，
                // 还可能重建当前 NavigationLink；只在真正进入后台后恢复时同步。
                guard phase == .active, shouldRefreshAfterBackground else { return }
                shouldRefreshAfterBackground = false
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
                }
            }
            .onChange(of: selectedTab) { _, tab in
                guard tab == .messages,
                      !Self.disablesBackgroundRefreshForUITesting
                else { return }
                Task {
                    await environment.refreshProactiveMessages(requestAuthorization: false)
                }
            }
            .onChange(of: activeUserID) { _, _ in
                activeSceneActivity = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .proactiveMessagesDidChange)) { _ in
                Task {
                    await reloadUnreadCount()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .roleplayConversationDidChange)) { _ in
                Task {
                    await environment.refreshProactiveMessages(requestAuthorization: false)
                    await reloadUnreadCount()
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
            .onReceive(NotificationCenter.default.publisher(for: .rosterContactDidChange)) { _ in
                stateRevision += 1
                Task {
                    await environment.refreshProactiveMessages(requestAuthorization: false)
                    await reloadUnreadCount()
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
        return phaseID
    }

    private func handleAuthenticationPhase() async {
        activationError = nil
        switch environment.authSession.phase {
        case .loading:
            // 会话恢复在后台进行，本地界面无需等待。
            return
        case .signedOut:
            activeUserID = nil
            isGuestReady = false
            do {
                try await environment.activateGuest()
                isGuestReady = true
                stateRevision += 1
            } catch {
                Log.app.error("本地旅程载入失败：\(error)")
                isInitialContentReady = true
            }
        case .signedIn(let identity):
            isGuestReady = false
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
                activationError = error.localizedDescription
                isInitialContentReady = true
                Log.app.warning("账号载入失败，保留当前旅程等待重试：\(error)")
            }
        }
    }

    private var appContent: some View {
        tabs
            .fullScreenCover(isPresented: $showPlacementTest) {
                placementTestView(isOnboarding: false)
            }
            .fullScreenCover(isPresented: showsOnboarding) {
                OnboardingFlowView(
                    deps: OnboardingDependencies(
                        economyStore: environment.economyStore,
                        profileCommands: profileCommands,
                        rosterStore: environment.rosterStore,
                        scriptURL: Bundle.main.url(forResource: "onboarding_chat", withExtension: "json")!
                    ),
                    placementCompletionRevision: placementCompletionRevision,
                    onRequestPlacement: { showOnboardingPlacement = true }
                ) { character in
                    Task {
                        guard await environment.completeOnboarding(
                            selected: character,
                            onboardingCommands: onboardingCommands
                        ) else { return }
                        stateRevision += 1
                        await refreshProactiveMessagesAfterInterfaceSettles(
                            requestAuthorization: true
                        )
                    }
                }
                .interactiveDismissDisabled()
                .fullScreenCover(isPresented: $showOnboardingPlacement) {
                    placementTestView(isOnboarding: true)
                }
            }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            messagesStack
                .tag(AppTab.messages)
                .tabItem {
                    Label("信息", systemImage: "bubble.left.and.bubble.right")
                }
                .badge(unreadCount)
            contactsStack
                .tag(AppTab.contacts)
                .tabItem {
                    Label("联系人", systemImage: "person.2")
                }
            homeStack
                .tag(AppTab.home)
                .tabItem {
                    Label("首页", systemImage: "house")
                }
            meStack
                .tag(AppTab.me)
                .tabItem {
                    Label("我的", systemImage: "person")
                }
            #if DEBUG
            relationshipLabStack
                .tag(AppTab.relationshipLab)
                .tabItem {
                    Label("测试", systemImage: "heart.text.square")
                }
            #endif
        }
        .tint(.dsSky)
        .background {
            if !DSPlatformVisualPolicy.usesLiquidGlass {
                LegacyTabBarAppearanceInstaller()
            }
        }
    }

    private var homeStack: some View {
        SceneNavigationContainer(
            isPresentingDestination: activeHomeDestination != nil,
            navigationTitle: activeHomeDestination?.navigationTitle ?? "",
            onBack: closeHomeDestination,
            navigationPath: $homePath,
            showsNavigationBar: activeHomeDestination != .activities
        ) {
            HomeView(
                deps: homeDeps,
                reloadToken: stateRevision,
                onInitialLoad: {
                    guard environment.needsOnboarding == false else { return }
                    isInitialContentReady = true
                },
                onOpenDestination: openHomeDestination
            )
            .id("home-root")
        } destination: {
            Group {
                if let destination = activeHomeDestination {
                    homeDestinationView(destination)
                        .id(destination)
                }
            }
            .navigationDestination(for: MainlineChapter.self) { chapter in
                storyView(storyID: chapter.storyID)
            }
            .navigationDestination(for: CityStoryChapter.self) { chapter in
                storyView(storyID: chapter.storyID)
            }
            .navigationDestination(for: HomeDestination.self) { destination in
                switch destination {
                case .mainline:
                    MainlineListView(deps: homeDeps) { chapter in
                        homePath.append(chapter)
                    }
                case .cityStories:
                    CityStoryListView(deps: homeDeps) { chapter in
                        homePath.append(chapter)
                    }
                case .map, .stories, .activities:
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder
    private func homeDestinationView(_ destination: HomeDestination) -> some View {
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
                storageNamespace: activityStorageNamespace,
                isVisible: selectedTab == .home && !showSignIn && !showLondonEpisode,
                activity: $activeSceneActivity,
                onClose: closeHomeDestination
            )
            .id(activeUserID?.uuidString ?? "guest")
        case .map:
            MapView(
                deps: mapDeps,
                reloadToken: stateRevision,
                onBack: closeHomeDestination
            )
        }
    }

    private func openHomeDestination(_ destination: HomeDestination) {
        guard activeHomeDestination == nil else { return }
        homePath = NavigationPath()
        withAnimation(sceneContentAnimation) {
            activeHomeDestination = destination
        }
    }

    private var activityStorageNamespace: String {
        #if DEBUG
        if let testNamespace = ProcessInfo.processInfo.environment["UI_TEST_ACTIVITY_NAMESPACE"], !testNamespace.isEmpty {
            return "ui-test.\(testNamespace)"
        }
        #endif
        return activeUserID?.uuidString ?? "guest"
    }
    private func closeHomeDestination() {
        guard activeHomeDestination != nil else { return }
        withAnimation(sceneContentAnimation) {
            if activeHomeDestination == .activities, activeSceneActivity != nil {
                activeSceneActivity = nil
                return
            }
            activeHomeDestination = nil
            homePath = NavigationPath()
        }
    }
    private var messagesStack: some View {
        NavigationStack {
            ConversationListView(deps: chatDeps, reloadToken: stateRevision)
        }
    }

    private var contactsStack: some View {
        let regionCatalog = environment.regionCatalog
        return NavigationStack {
            RosterView(
                deps: RosterDependencies(
                    rosterStore: environment.rosterStore,
                    economyStore: environment.economyStore,
                    npcRegistry: environment.backendClient,
                    regionName: { regionID in
                        regionCatalog.region(id: regionID)?.nameZh
                            ?? regionID.replacingOccurrences(of: "_", with: " ").capitalized
                    }
                ),
                reloadToken: stateRevision,
                chatBuilder: { character in
                    AnyView(ChatView(character: character, deps: chatDeps))
                },
                callBuilder: { character in
                    AnyView(
                        ChatView(
                            character: character,
                            deps: chatDeps,
                            startsInRealtimeConversation: true
                        )
                    )
                }
            )
        }
    }

    private var meStack: some View {
        SceneNavigationContainer(
            isPresentingDestination: !mePath.isEmpty,
            navigationTitle: meNavigationTitle,
            onBack: closeMeDestination
        ) {
            meRootView
        } destination: {
            Group {
                if let destination = mePath.last {
                    meDestinationView(destination)
                        .id(destination)
                }
            }
        }
    }

    private var meRootView: some View {
        MyPageView(
            accessClient: environment.backendClient,
            economyStore: environment.economyStore,
            economyService: economyService,
            rosterStore: environment.rosterStore,
            authSession: environment.authSession,
            billing: environment.billing,
            reloadToken: stateRevision,
            isSignedIn: usesCloudState,
            onSignIn: { showSignIn = true },
            onCalibrateLevel: { showPlacementTest = true },
            onOpenFavorites: { openMe(.favorites) },
            onOpenSettings: { openMe(.settings) },
            onOpenMemory: {
                #if DEBUG
                openMe(.memory)
                #endif
            }
        )
        .id("me-root")
    }

    private var meNavigationTitle: String {
        guard let destination = mePath.last else { return "" }
        return switch destination {
        case .favorites: "收藏夹"
        case .settings: "设置"
        case .photoCredits: "城市背景照片"
        #if DEBUG
        case .memory: ""
        #endif
        }
    }

    private func openMe(_ destination: MeDestination) {
        withAnimation(sceneContentAnimation) {
            mePath.append(destination)
        }
    }

    private func closeMeDestination() {
        guard !mePath.isEmpty else { return }
        withAnimation(sceneContentAnimation) {
            _ = mePath.removeLast()
        }
    }

    /// 与原生 Tab 快速切换相同的轻量交叉淡化，不再表达左右层级位移。
    private var sceneContentAnimation: Animation {
        DSSceneTransition.animation(reduceMotion: reduceMotion)
    }

    @ViewBuilder
    private func meDestinationView(_ destination: MeDestination) -> some View {
        switch destination {
        case .favorites:
            FavoritesView(
                deps: favoritesDeps,
                onBrowseConversations: {
                    selectedTab = .messages
                    mePath.removeAll()
                }
            )

        case .settings:
            SettingsView(
                router: environment.llmRouter,
                economyStore: environment.economyStore,
                profileCommands: profileCommands,
                memoryStore: environment.memoryStore,
                rosterStore: environment.rosterStore,
                chatStore: environment.chatStore,
                speech: environment.speech,
                onProactiveMessagesChanged: { enabled in
                    Task { await environment.proactiveMessages.setEnabled(enabled) }
                },
                onOpenPhotoCredits: { openMe(.photoCredits) }
            )

        case .photoCredits:
            CityScenePhotoCreditsView()

        #if DEBUG
        case .memory:
            MemoryDebugView(
                memoryStore: environment.memoryStore,
                rosterStore: environment.rosterStore,
                economyStore: environment.economyStore,
                memoryService: MemoryService(
                    llm: environment.llmRouter,
                    chatStore: environment.chatStore,
                    memoryStore: environment.memoryStore,
                    economyStore: environment.economyStore
                )
            )
        #endif
        }
    }

    #if DEBUG
    private var relationshipLabStack: some View {
        NavigationStack {
            RelationshipLabView(
                rosterStore: environment.rosterStore,
                llm: environment.llmRouter
            )
        }
    }
    #endif

    private func placementTestView(isOnboarding: Bool) -> some View {
        PlacementTestView(
            deps: PlacementDependencies(
                questionBankURL: Bundle.main.url(
                    forResource: "placement_questions",
                    withExtension: "json"
                )!,
                economyStore: environment.economyStore,
                profileCommands: profileCommands,
                speech: environment.speech,
                audioSession: environment.audioSession
            ),
            onComplete: { updated in
                Task {
                    await environment.applyLearnerProfile(updated)
                    stateRevision += 1
                    if isOnboarding {
                        showOnboardingPlacement = false
                        placementCompletionRevision += 1
                    } else {
                        showPlacementTest = false
                    }
                }
            },
            onCancel: {
                if isOnboarding {
                    showOnboardingPlacement = false
                } else {
                    showPlacementTest = false
                }
            }
        )
    }

    private func storyView(storyID: String) -> some View {
        LondonEpisodeView(deps: storyDeps, storageNamespace: activeUserID?.uuidString ?? "guest", resourceName: storyID)
            .navigationBarBackButtonHidden()
            .toolbar(.hidden, for: .tabBar)
            .dsTabBarHidden()
    }

    private var homeDeps: HomeDependencies {
        HomeDependencies(
            access: journeyAccess,
            economyStore: environment.economyStore,
            storyProgress: environment.storyProgressStore,
            travelService: travelService,
            regionCatalog: environment.regionCatalog,
            rosterStore: environment.rosterStore,
            chatStore: environment.chatStore,
            favorites: environment.favoritesStore,
            dictionary: environment.dictionary,
            grammarPoints: environment.grammarPoints,
            speech: environment.speech,
            llm: environment.llmRouter,
            exampleTranslationActions: exampleTranslationActions,
            npcRegistry: environment.backendClient
        )
    }

    private var mapDeps: MapDependencies {
        MapDependencies(
            access: journeyAccess,
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
            accessClient: environment.backendClient,
            onShowAccess: { showUsage = true },
            chatStore: environment.chatStore,
            rosterStore: environment.rosterStore,
            favorites: environment.favoritesStore,
            llm: environment.llmRouter,
            dictionary: environment.dictionary,
            grammarPoints: environment.grammarPoints,
            speech: environment.speech,
            translator: environment.translator,
            exampleTranslationActions: exampleTranslationActions,
            audioSession: environment.audioSession,
            memoryStore: environment.memoryStore,
            itemStore: environment.itemStore,
            economyStore: environment.economyStore,
            progression: progression,
            voiceMedia: environment.voiceMedia,
            npcRegistry: environment.backendClient
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
            speech: environment.speech,
            audioSession: environment.audioSession,
            exampleTranslationActions: exampleTranslationActions
        )
    }

    private var favoritesDeps: FavoritesDependencies {
        FavoritesDependencies(
            favorites: environment.favoritesStore,
            dictionary: environment.dictionary,
            grammarPoints: environment.grammarPoints,
            speech: environment.speech,
            exampleTranslationActions: exampleTranslationActions
        )
    }

    private var journeyAccess: JourneyAccess {
        JourneyAccess(isGuest: !usesCloudState) { reason in loginReason = reason }
    }

    private var usesCloudState: Bool {
        guard let activeUserID,
              case .signedIn(let identity) = environment.authSession.phase
        else { return false }
        return identity.userID == activeUserID
    }

    private var profileCommands: any ProfileCommandGateway {
        if usesCloudState || environment.guestStateReady {
            environment.userState
        } else {
            environment.localUserState
        }
    }

    private var onboardingCommands: any OnboardingCommandGateway {
        if usesCloudState || environment.guestStateReady {
            environment.userState
        } else {
            environment.localUserState
        }
    }

    private var progression: any ProgressionRewardGateway {
        if usesCloudState || environment.guestStateReady {
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

    private func reloadUnreadCount() async {
        guard let friends = try? await environment.rosterStore.friends(),
              let summaries = try? await environment.chatStore.conversationSummaries()
        else { return }
        unreadCount = ConversationReadState.totalUnreadCount(
            friends: friends,
            summaries: summaries
        )
    }

    /// 让首屏和转场先完成，再启动需要多次网络往返的主动消息生成。
    private func refreshProactiveMessagesAfterInterfaceSettles(
        requestAuthorization: Bool
    ) async {
        guard !Self.disablesBackgroundRefreshForUITesting,
              environment.needsOnboarding == false
        else { return }
        do {
            try await Task.sleep(for: Self.proactiveRefreshDelay)
        } catch {
            return
        }
        guard !Task.isCancelled, environment.needsOnboarding == false else { return }
        await environment.refreshProactiveMessages(
            requestAuthorization: requestAuthorization
        )
    }
}
