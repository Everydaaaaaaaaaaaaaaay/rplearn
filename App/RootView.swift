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
import PersistenceKit
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

    @State private var unreadCount = 0
    @State private var selectedTab: AppTab = .messages
    @State private var homePath = NavigationPath()
    @State private var activeHomeDestination: HomeDestination?
    @State private var mePath: [MeDestination] = []
    @State private var activationError: String?
    @State private var showUsage = false
    @State private var showLondonEpisode = false
    @State private var activeSceneActivity: SceneActivity?
    @State private var activeActivityChat: CharacterDTO?
    @State private var showPlacementTest = false
    @State private var showOnboardingPlacement = false
    @State private var placementCompletionRevision = 0
    @State private var activeUserID: UUID?
    @State private var stateRevision = 0
    @State private var shouldRefreshAfterBackground = false
    @State private var isInitialContentReady = false
    @State private var completedForcedOnboarding = false
    @State private var completedForcedWelcome = false
    @AppStorage("onboarding.welcome.completed.v1") private var welcomeCompleted = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(environment: AppEnvironment) {
        self.environment = environment
        #if DEBUG
        let requested = ProcessInfo.processInfo.environment["UI_TEST_TAB"]
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
                (
                    environment.needsOnboarding == true
                        || (forcesOnboardingForUITest && !completedForcedOnboarding)
                )
                    && !showPlacementTest
            },
            set: { newValue in
                if !newValue { environment.needsOnboarding = false }
            }
        )
    }

    private var requiredActiveAccountID: UUID {
        guard let activeUserID,
              environment.workspace?.userID == activeUserID
        else {
            preconditionFailure("Account UI requested without its active workspace")
        }
        return activeUserID
    }
    private var forcesOnboardingForUITest: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["UI_TEST_ONBOARDING_STORY"] == "1"
            || ProcessInfo.processInfo.environment["UI_TEST_ONBOARDING_WELCOME"] == "1"
            || ProcessInfo.processInfo.environment["UI_TEST_ONBOARDING_SELECTION"] == "1"
        #else
        false
        #endif
    }

    var body: some View {
        launchContent
            .fullScreenCover(isPresented: $showLondonEpisode) {
                #if DEBUG
                LondonEpisodeView(
                    deps: storyDeps,
                    storageNamespace: activeUserID?.uuidString ?? "inactive",
                    resourceName: ProcessInfo.processInfo.environment[
                        "UI_TEST_DEPARTURE_RESOURCE"
                    ] ?? "departures_london_v1"
                )
                #endif
            }
            .overlay {
                if let activationError {
                    VStack(spacing: 16) {
                        Text("旅程尚未载入").font(.headline)
                        Text(activationError).font(.subheadline)
                        Button("重试") { Task { await handleAuthenticationPhase() } }
                        Button("退出此账号") {
                            Task { await environment.authSession.logout() }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
                }
            }
            .sheet(isPresented: $showUsage) {
                if environment.workspace != nil {
                    UsageAccessView(
                        backend: environment.backendClient,
                        billing: environment.billing
                    )
                }
            }
            .task(id: authenticationTaskID) {
                await handleAuthenticationPhase()
                guard environment.workspace != nil else { return }
                await reloadUnreadCount()
                if environment.needsOnboarding != nil,
                   selectedTab != .home || activeHomeDestination != nil || !homePath.isEmpty {
                    isInitialContentReady = true
                }
                await refreshProactiveMessagesAfterInterfaceSettles(
                    requestAuthorization: true
                )
            }
            .task(id: "\(authenticationTaskID)-\(scenePhase)-\(activeUserID?.uuidString ?? "none")") {
                guard scenePhase == .active, environment.workspace != nil else { return }
                switch environment.authSession.phase {
                case .signedIn(let identity):
                    guard identity.userID == activeUserID else { return }
                case .signedOut:
                    guard bypassesAuthenticationForUITesting else { return }
                case .loading:
                    return
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
                guard phase == .active, shouldRefreshAfterBackground else { return }
                shouldRefreshAfterBackground = false
                Task {
                    guard environment.workspace != nil else { return }
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
                      environment.workspace != nil,
                      !Self.disablesBackgroundRefreshForUITesting
                else { return }
                Task {
                    await environment.refreshProactiveMessages(requestAuthorization: false)
                }
            }
            .onChange(of: activeUserID) { _, _ in
                activeSceneActivity = nil
                activeActivityChat = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .proactiveMessagesDidChange)) { _ in
                guard environment.workspace != nil else { return }
                Task { await reloadUnreadCount() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .roleplayConversationDidChange)) { _ in
                guard environment.workspace != nil else { return }
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
                guard environment.workspace != nil else { return }
                Task { await reloadUnreadCount() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .rosterContactDidChange)) { _ in
                guard environment.workspace != nil else { return }
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
            bypassesAuthenticationForUITesting ? "ui-fixture" : "signed-out"
        case .signedIn(let identity):
            "account-\(identity.userID.uuidString)"
        }
        return phaseID
    }

    private func handleAuthenticationPhase() async {
        activationError = nil
        #if DEBUG
        if bypassesAuthenticationForUITesting,
           case .signedOut = environment.authSession.phase {
            do {
                activeUserID = try await environment.activateUITestWorkspace()
                stateRevision += 1
                if ProcessInfo.processInfo.environment["UI_TEST_LONDON_EPISODE"] == "1" {
                    showLondonEpisode = true
                }
            } catch {
                activationError = error.localizedDescription
            }
            return
        }
        #endif
        switch environment.authSession.phase {
        case .loading:
            return
        case .signedOut:
            await environment.deactivateAccount()
            activeUserID = nil
            unreadCount = 0
            isInitialContentReady = false
        case .signedIn(let identity):
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
                Log.app.warning("账号载入失败，保留当前旅程等待重试：\(error)")
            }
        }
    }

    @ViewBuilder
    private var launchContent: some View {
        if showsWelcome {
            WelcomeJourneyView {
                welcomeCompleted = true
                completedForcedWelcome = true
            }
        } else {
            switch environment.authSession.phase {
            case .loading:
                launchLoading
            case .signedOut:
                if bypassesAuthenticationForUITesting,
                   activeUserID != nil,
                   environment.workspace != nil {
                    appContent
                } else if bypassesAuthenticationForUITesting {
                    launchLoading
                } else {
                    SignInView(session: environment.authSession)
                }
            case .signedIn(let identity):
                if activeUserID == identity.userID,
                   environment.workspace?.userID == identity.userID {
                    appContent
                } else {
                    launchLoading
                }
            }
        }
    }

    private var launchLoading: some View {
        ZStack {
            Color("BrandLaunchBackground").ignoresSafeArea()
            ProgressView()
                .tint(.dsSky)
                .accessibilityLabel("正在载入旅程")
        }
    }

    private var showsWelcome: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["UI_TEST_ONBOARDING_WELCOME"] == "1" {
            return !completedForcedWelcome
        }
        if ProcessInfo.processInfo.environment["UI_TEST_ONBOARDING_WELCOME"] == "0"
            || ProcessInfo.processInfo.environment["UI_TEST_SKIP_ONBOARDING"] == "1" {
            return false
        }
        #endif
        return !welcomeCompleted
    }

    private var bypassesAuthenticationForUITesting: Bool {
        #if DEBUG
        let processEnvironment = ProcessInfo.processInfo.environment
        if processEnvironment["UI_TEST_REQUIRE_AUTHENTICATION"] == "1" {
            return false
        }
        return processEnvironment["UI_TEST_SKIP_ONBOARDING"] == "1"
            || processEnvironment["UI_TEST_ONBOARDING_WELCOME"] != nil
            || processEnvironment["UI_TEST_ONBOARDING_SELECTION"] == "1"
            || processEnvironment["UI_TEST_ONBOARDING_STORY"] == "1"
            || processEnvironment["UI_TEST_SOCIAL_FIXTURE"] == "1"
        #else
        return false
        #endif
    }

    @ViewBuilder
    private var appContent: some View {
        if let accountID = activeUserID,
           environment.workspace?.userID == accountID {
            tabs
            .fullScreenCover(isPresented: $showPlacementTest) {
                placementTestView(isOnboarding: false)
            }
            .fullScreenCover(isPresented: showsOnboarding) {
                OnboardingFlowView(
                    accountID: accountID,
                    deps: OnboardingDependencies(
                        economyStore: environment.economyStore,
                        profileCommands: profileCommands,
                        rosterStore: environment.rosterStore,
                        scriptURL: Bundle.main.url(forResource: "onboarding_chat", withExtension: "json")!
                    ),
                    placementCompletionRevision: placementCompletionRevision,
                    onRequestPlacement: { showOnboardingPlacement = true }
                ) { character in
                    #if DEBUG
                    if ProcessInfo.processInfo.environment[
                        "UI_TEST_ONBOARDING_SELECTION_FAILURE"
                    ] == "1" {
                        return false
                    }
                    #endif
                    guard await environment.completeOnboarding(
                        selected: character,
                        onboardingCommands: onboardingCommands
                    ) else { return false }
                    completedForcedOnboarding = true
                    stateRevision += 1
                    await refreshProactiveMessagesAfterInterfaceSettles(
                        requestAuthorization: true
                    )
                    return true
                }
                .interactiveDismissDisabled()
                .fullScreenCover(isPresented: $showOnboardingPlacement) {
                    placementTestView(isOnboarding: true)
                }
            }
        } else {
            launchLoading
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
            showsNavigationBar: activeHomeDestination != .map
                && (activeHomeDestination != .activities || activeActivityChat != nil),
            backLabel: activeActivityChat == nil ? "返回" : "返回城市活动"
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
            ZStack {
                ActivitiesView(
                    deps: homeDeps,
                    storageNamespace: activityStorageNamespace,
                    isVisible: selectedTab == .home && !showLondonEpisode && activeActivityChat == nil,
                    activity: $activeSceneActivity,
                    onClose: closeHomeDestination,
                    onChat: { character in
                        withAnimation(sceneContentAnimation) { activeActivityChat = character }
                    }
                )
                .id(activeUserID?.uuidString ?? "inactive")
                .opacity(activeActivityChat == nil ? 1 : 0)
                .allowsHitTesting(activeActivityChat == nil)
                .accessibilityHidden(activeActivityChat != nil)
                if let character = activeActivityChat {
                    // Use the existing scene navigation host, not a nested stack
                    // whose toolbar is suppressed by the outer photographic page.
                    ChatView(character: character, deps: chatDeps)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                }
            }
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
        return activeUserID?.uuidString ?? "inactive"
    }
    private func closeHomeDestination() {
        guard activeHomeDestination != nil else { return }
        withAnimation(sceneContentAnimation) {
            if activeActivityChat != nil {
                activeActivityChat = nil
                return
            }
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
            ConversationListView(
                accountID: requiredActiveAccountID,
                deps: chatDeps,
                reloadToken: stateRevision
            )
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
                accountID: requiredActiveAccountID,
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
        LondonEpisodeView(
            deps: storyDeps,
            storageNamespace: activeUserID?.uuidString ?? "inactive",
            resourceName: storyID
        )
            .navigationBarBackButtonHidden()
            .toolbar(.hidden, for: .tabBar)
            .dsTabBarHidden()
    }

    private var homeDeps: HomeDependencies {
        HomeDependencies(
            access: journeyAccess,
            economyStore: environment.economyStore,
            itemStore: environment.itemStore,
            ticketStubStore: environment.ticketStubStore,
            storyProgress: environment.storyProgressStore,
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
        let regionCatalog = environment.regionCatalog
        return ChatDependencies(
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
            npcRegistry: environment.backendClient,
            regionName: { regionID in
                regionCatalog.region(id: regionID)?.nameZh
                    ?? regionID.replacingOccurrences(of: "_", with: " ").capitalized
            }
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
        JourneyAccess()
    }

    private var profileCommands: any ProfileCommandGateway {
        bypassesAuthenticationForUITesting ? environment.localUserState : environment.userState
    }

    private var onboardingCommands: any OnboardingCommandGateway {
        bypassesAuthenticationForUITesting ? environment.localUserState : environment.userState
    }

    private var progression: any ProgressionRewardGateway {
        bypassesAuthenticationForUITesting ? environment.localUserState : environment.userState
    }

    private var travelService: TravelService {
        bypassesAuthenticationForUITesting
            ? environment.localTravelService
            : environment.travelService
    }

    private var economyService: EconomyService {
        bypassesAuthenticationForUITesting
            ? environment.localEconomyService
            : environment.economyService
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
