import AuthFeature
import BackendKit
import BillingKit
import ChatFeature
import LearningFeature
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
    private static let proactiveRefreshDelay = Duration.seconds(5)

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
    @State private var visitedTabs: Set<AppTab> = []
    @State private var messagesPath = NavigationPath()
    @State private var contactsPath = NavigationPath()
    @State private var messagesNavigationRevision = 0
    @State private var contactsNavigationRevision = 0
    @State private var homePath = NavigationPath()
    @State private var activeHomeDestination: HomeDestination?
    @State private var mePath: [MeDestination] = []
    @State private var activationError: String?
    @State private var showUsage = false
    @State private var showLondonEpisode = false
    @StateObject private var activityJourney = ActivityJourneyCoordinator()
    @State private var activeSceneActivity: SceneActivity?
    @State private var activeActivityChat: CharacterDTO?
    @State private var showPlacementTest = false
    @State private var showEnglishJourney = false
    @State private var showOnboardingPlacement = false
    private enum IntroductionMode: String, Identifiable {
        case introduction, tutorial
        var id: String { rawValue }
    }
    @State private var introductionMode: IntroductionMode?
    #if DEBUG
    @State private var captureCharacter: CharacterDTO?
    #endif
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
        case "me", "subscription", "learning", "favorites", "learning-test": .me
        default:
            ProcessInfo.processInfo.environment["UI_TEST_HOME_DESTINATION"] == nil
                ? .messages
                : .home
        }
        _selectedTab = State(initialValue: initial)
        if requested == "favorites", ProcessInfo.processInfo.environment["UI_TEST_MARKETING_CAPTURE"] == "1" {
            _mePath = State(initialValue: [.favorites])
        }
        if requested == "learning" {
            _showEnglishJourney = State(initialValue: true)
        }
        if requested == "learning-test" {
            _mePath = State(initialValue: [.learningTrial])
        }
        if requested == "subscription" {
            _mePath = State(initialValue: [.subscription])
        }
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
            _selectedTab = State(initialValue: .me)
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
        configuredRootContent
            .dictionaryPopupServices(DictionaryPopupServices(examples: environment.exampleTranslationActions))
    }

    private var configuredRootContent: some View {
        launchContent
            #if DEBUG
            .preferredColorScheme(ProcessInfo.processInfo.environment["UI_TEST_CAPTURE_APPEARANCE"].map { $0 == "dark" ? .dark : .light })
            .fullScreenCover(item: $captureCharacter) { character in
                NavigationStack {
                    if ProcessInfo.processInfo.environment["UI_TEST_NATIVE_CAPTURE"] == "profile" {
                        CharacterProfileView(character: character,
                            regionName: environment.regionCatalog.region(id: character.card.regionID)?.nameZh ?? "",
                            rosterStore: environment.rosterStore,
                            chatBuilder: { AnyView(ChatView(character: $0, deps: chatDeps)) },
                            callBuilder: { AnyView(ChatView(character: $0, deps: chatDeps, startsInRealtimeConversation: true)) })
                    } else if ProcessInfo.processInfo.environment["UI_TEST_TAB"] == "practice-preview" {
                        LearningPracticePreview(character: character)
                    } else if ProcessInfo.processInfo.environment["UI_TEST_TAB"] == "unit-challenge" {
                        let preview = DebugLearningPreviewService(characterID: character.id, roleKey: "oliver")
                        if let attempt = try? preview.previewAttempt(kind: ProcessInfo.processInfo.environment["UI_TEST_LEARNING_QUESTION"] ?? "choice") {
                            LearningChallengeView(attempt: attempt, character: character, service: preview)
                        }
                    } else if ProcessInfo.processInfo.environment["UI_TEST_TAB"] == "role-learning" {
                        Self.debugLearningPage(character)
                            .navigationTitle("角色学习")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar(.visible, for: .navigationBar)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button { captureCharacter = nil } label: { Image(systemName: "chevron.left") }
                                        .accessibilityLabel("返回消息")
                                }
                            }
                    } else {
                        ChatView(character: character, deps: chatDeps)
                    }
                }
            }
            #endif
            .environment(\.userAvatar, environment.workspace?.userAvatar)
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
                #if DEBUG
                if ["chat", "profile"].contains(ProcessInfo.processInfo.environment["UI_TEST_NATIVE_CAPTURE"] ?? ""),
                   ProcessInfo.processInfo.environment["UI_TEST_WELCOME_CAPTURE"] == "1",
                   bypassesAuthenticationForUITesting {
                    captureCharacter = try? await environment.rosterStore.allCharacters().first {
                        $0.isMainCharacter && $0.card.regionID == "melbourne"
                    }
                }
                #endif
                await reloadUnreadCount()
                if environment.needsOnboarding != nil,
                   selectedTab != .home || activeHomeDestination != nil || !homePath.isEmpty {
                    isInitialContentReady = true
                }
                await refreshProactiveMessagesAfterInterfaceSettles(
                    requestAuthorization: true
                )
            }
            .task(id: "\(authenticationTaskID)-\(scenePhase)-\(activeUserID?.uuidString ?? "none")", priority: .utility) {
                guard scenePhase == .active, environment.workspace != nil else { return }
                switch environment.authSession.phase {
                case .signedIn(let identity):
                    guard identity.userID == activeUserID else { return }
                case .signedOut:
                    guard bypassesAuthenticationForUITesting else { return }
                case .loading:
                    return
                }
                do { try await Task.sleep(for: .seconds(4)) }
                catch { return }
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
            .task(id: activeUserID) {
                guard let account = environment.workspace,
                      account.userID == activeUserID,
                      case .signedIn(let identity) = environment.authSession.phase,
                      identity.userID == account.userID else { return }
                do {
                    try await Task.sleep(for: .seconds(1))
                    async let userState: Void = account.userState.synchronize()
                    async let content: Void = account.contentSync.synchronize()
                    _ = try await (userState, content)
                    try Task.checkCancellation()
                    guard environment.workspace === account else { return }
                    try await environment.refreshAccountPresentation(account)
                    guard !Task.isCancelled, environment.workspace === account else { return }
                    stateRevision += 1
                    await reloadUnreadCount()
                } catch is CancellationError {
                } catch {
                    guard !Task.isCancelled, environment.workspace === account else { return }
                    if !environment.authSession.handleAuthenticationFailure(error) {
                        Log.app.warning("启动后同步暂未完成，保留本地旅程：\(error)")
                    }
                }
            }
            .task(id: activeUserID.map { "billing-\($0)" }, priority: .utility) {
                guard let account = environment.workspace,
                      account.userID == activeUserID,
                      case .signedIn = environment.authSession.phase else { return }
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
                guard !Task.isCancelled, environment.workspace === account else { return }
                await account.billing.synchronize()
            }
            .task(id: isInitialContentReady && scenePhase == .active, priority: .utility) {
                guard isInitialContentReady, scenePhase == .active else { return }
                do { try await Task.sleep(for: .seconds(3)) }
                catch { return }
                guard !Task.isCancelled else { return }
                await environment.speech.prepareForLaunch()
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
                activityJourney.reset()
                activeSceneActivity = nil
                activeActivityChat = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .memoryKnowledgeDidChange)) { _ in
                Task { await environment.workspace?.proactiveMessages.learnerProfileDidChange() }
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
        await environment.prepareResources()
        guard !Task.isCancelled else { return }
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
        if !environment.resourcesReady {
            launchLoading
        } else if showsWelcome {
            WelcomeJourneyView(dictionary: environment.dictionary, grammar: environment.grammarPoints) {
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
            #if DEBUG
            .task(id: "\(accountID.uuidString)-\(stateRevision)-\(environment.needsOnboarding == false)") {
                // 内存账号可能先挂载、后导入角色；等导入完成，避免冷启动丢失预览展示。
                guard ["role-learning", "unit-challenge", "practice-preview"].contains(ProcessInfo.processInfo.environment["UI_TEST_TAB"] ?? ""),
                      bypassesAuthenticationForUITesting, environment.needsOnboarding == false else { return }
                captureCharacter = try? await environment.rosterStore.allCharacters().first { $0.isMainCharacter }
            }
            #endif
            .fullScreenCover(item: $introductionMode) { mode in
                JourneyIntroductionView(deps: OnboardingDependencies(
                    economyStore: environment.economyStore,
                    profileCommands: profileCommands,
                    rosterStore: environment.rosterStore,
                    scriptURL: Bundle.main.url(forResource: "onboarding_chat", withExtension: "json")!,
                    dictionary: environment.dictionary,
                    grammarPoints: environment.grammarPoints,
                    tutorial: tutorialPresenter
                ), startsWithTutorial: mode == .tutorial)
            }
            .fullScreenCover(isPresented: showsOnboarding) {
                OnboardingFlowView(
                    accountID: accountID,
                    deps: OnboardingDependencies(
                        economyStore: environment.economyStore,
                        profileCommands: profileCommands,
                        rosterStore: environment.rosterStore,
                        scriptURL: Bundle.main.url(forResource: "onboarding_chat", withExtension: "json")!,
                        dictionary: environment.dictionary,
                        grammarPoints: environment.grammarPoints,
                        tutorial: tutorialPresenter
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
        TabView(selection: Binding(
            get: { selectedTab },
            set: { tab in
                returnTabToRoot(tab)
                selectedTab = tab
            }
        )) {
            deferredTab(.messages) { messagesStack }
                .tag(AppTab.messages)
                .tabItem {
                    Label("信息", systemImage: "bubble.left.and.bubble.right")
                }
                .badge(unreadCount)
            deferredTab(.contacts) { contactsStack }
                .tag(AppTab.contacts)
                .tabItem {
                    Label("联系人", systemImage: "person.2")
                }
            deferredTab(.home) { homeStack }
                .tag(AppTab.home)
                .tabItem {
                    Label("活动", systemImage: "figure.walk")
                }
                .badge(activityJourney.hasUnreadResult ? "•" : nil)
            deferredTab(.me) { meStack }
                .tag(AppTab.me)
                .tabItem {
                    Label("我的", systemImage: "person")
                }
        }
        .onChange(of: selectedTab) { previous, current in
            visitedTabs.formUnion([previous, current])
        }
        .tint(.dsSky)
        .background {
            if #available(iOS 27.0, *) {
                TabSceneTransitionInstaller()
            }
            if !DSPlatformVisualPolicy.usesLiquidGlass {
                LegacyTabBarAppearanceInstaller()
            }
        }
    }

    /// 首次选中才创建页面；已访问页面继续保留，避免切换时重建状态。
    @ViewBuilder
    private func deferredTab<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        if selectedTab == tab || visitedTabs.contains(tab) {
            content()
        } else {
            Color.clear
        }
    }

    /// 点击事件独立于 selectedTab 的变化，因此重复点击当前标签也会返回入口。
    private func returnTabToRoot(_ tab: AppTab) {
        switch tab {
        case .messages:
            messagesPath = NavigationPath()
            messagesNavigationRevision += 1
        case .contacts:
            contactsPath = NavigationPath()
            contactsNavigationRevision += 1
        case .home:
            homePath = NavigationPath()
            activeHomeDestination = nil
            activeActivityChat = nil
        case .me:
            showPlacementTest = false
            showEnglishJourney = false
            mePath.removeAll()
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
                    journey: activityJourney,
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
                if activityJourney.isPreparing {
                    activeHomeDestination = nil
                } else {
                    activityJourney.reset()
                    activeSceneActivity = nil
                }
                return
            }
            activeHomeDestination = nil
            homePath = NavigationPath()
        }
    }
    private var messagesStack: some View {
        ZStack {
            NavigationStack(path: $messagesPath) {
                ConversationListView(
                    accountID: requiredActiveAccountID,
                    deps: chatDeps,
                    reloadToken: stateRevision
                )
            }
            .id(messagesNavigationRevision)
        }
    }

    private var contactsStack: some View {
        let regionCatalog = environment.regionCatalog
        return ZStack {
            NavigationStack(path: $contactsPath) {
                RosterView(
                    deps: RosterDependencies(
                        rosterStore: environment.rosterStore,
                        economyStore: environment.economyStore,
                        npcRegistry: environment.backendClient,
                        chatStore: environment.chatStore,
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
            .id(contactsNavigationRevision)
        }
    }

    private var meStack: some View {
        NavigationStack(path: $mePath) {
            myPage()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: MeDestination.self) { destination in
                    meDestinationView(destination)
                        .navigationTitle(meNavigationTitle(for: destination))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar(.visible, for: .navigationBar)
                }
                .navigationDestination(isPresented: $showEnglishJourney) { englishJourneyView }
                .navigationDestination(isPresented: $showPlacementTest) { placementTestView(isOnboarding: false) }
        }
    }

    private func myPage(section: MyPageSection? = nil) -> some View {
        MyPageView(
            accessClient: environment.backendClient,
            economyStore: environment.economyStore,
            economyService: economyService,
            rosterStore: environment.rosterStore,
            authSession: environment.authSession,
            billing: environment.billing,
            reloadToken: stateRevision,
            onCalibrateLevel: { showEnglishJourney = true },
            onOpenFavorites: { openMe(.favorites) },
            onOpenSettings: { openMe(.settings) },
            onOpenMemory: { openMe(.memory) },
            section: section,
            onOpenAccount: { openMe(.account) },
            onOpenSubscription: { openMe(.subscription) }
        )
        .id("me-root")
        #if DEBUG
        .safeAreaInset(edge: .bottom) {
            if section == nil && !bypassesAuthenticationForUITesting {
                Button { openMe(.learningTrial) } label: {
                    Label("学习实测 · 切换档位做题", systemImage: "book.pages")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(12)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 20).padding(.vertical, 8)
                .background(.regularMaterial)
                .accessibilityIdentifier("me.learning-trial")
            }
        }
        #endif
    }

    private func meNavigationTitle(for destination: MeDestination) -> String {
        return switch destination {
        case .favorites: "收藏夹"
        case .settings: "设置"
        case .photoCredits: "城市背景照片"
        case .memory: "记忆档案"
        case .account: "个人资料"
        case .subscription: "会员订阅"
        #if DEBUG
        case .learningTrial: "学习实测"
        #endif
        }
    }

    private func openMe(_ destination: MeDestination) {
        mePath.append(destination)
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
                onOpenPhotoCredits: { openMe(.photoCredits) },
                onOpenIntroduction: { introductionMode = .introduction },
                onOpenTutorial: { introductionMode = .tutorial }
            )

        case .photoCredits:
            CityScenePhotoCreditsView()

        case .account:
            myPage(section: .account)
        case .subscription:
            myPage(section: .subscription)
        #if DEBUG
        case .learningTrial:
            LearningTrialView(environment: environment)
        #endif
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
        }
    }


    private func placementTestView(isOnboarding: Bool, chooseLevel: Bool = false) -> some View {
        PlacementTestView(
            deps: PlacementDependencies(
                questionBankURL: Bundle.main.url(
                    forResource: "placement_questions",
                    withExtension: "json"
                )!,
                economyStore: environment.economyStore,
                profileCommands: profileCommands,
                speech: environment.speech,
                audioSession: environment.audioSession,
                levelChangeSummary: { [client = environment.backendClient, preview = bypassesAuthenticationForUITesting] level in
                    #if DEBUG
                    if preview { return "界面预览：目标水平保留 0 颗星、0 点。此操作仅修改本地预览档案，不写入账号。" }
                    #endif
                    let journey = try await client.learningJourney()
                    guard let target = journey.levels.first(where: { $0.level == level.rawValue }) else { throw URLError(.cannotParseResponse) }
                    let supply = target.publishedUnitCount == 0 ? "该水平目前没有已发布单元，聊天满条后需等待题库准备。" : "各旅伴的可用挑战以角色学习页为准；题库不足时会保留聊天进度。"
                    return "目标水平已保留 \(target.stars) 颗星、\(target.points) 点。其他水平的进度也会保留。\n\n\(supply)"
                }
            ),
            usesNativeNavigation: !isOnboarding,
            startsWithLevelSelection: !isOnboarding && chooseLevel,
            onComplete: { updated in
                stateRevision += 1
                Task {
                    if isOnboarding {
                        showOnboardingPlacement = false
                        placementCompletionRevision += 1
                    } else { showPlacementTest = false; showEnglishJourney = false }
                    await environment.applyLearnerProfile(updated)
                }
            },
            onCancel: {
                if isOnboarding {
                    showOnboardingPlacement = false
                } else {
                    showPlacementTest = false; showEnglishJourney = false
                }
            }
        )
    }

    private var englishJourneyView: some View {
        placementTestView(isOnboarding: false)
    }

    @ViewBuilder
    private func storyView(storyID: String) -> some View {
        if MainlineCatalog.chapters.contains(where: { $0.storyID == storyID }) {
            MainlineStoryGate(storyID: storyID, service: mainlineClient) { unguardedStoryView(storyID: storyID) }
        } else { unguardedStoryView(storyID: storyID) }
    }

    private func unguardedStoryView(storyID: String) -> some View {
        LondonEpisodeView(
            deps: storyDeps,
            storageNamespace: activeUserID?.uuidString ?? "inactive",
            resourceName: storyID
        )
            .navigationBarBackButtonHidden()
            .toolbar(.hidden, for: .tabBar)
            .dsTabBarHidden()
    }

    private var mainlineClient: any MainlineServing {
        #if DEBUG
        if bypassesAuthenticationForUITesting { return DebugLearningPreviewService(characterID: UUID(), roleKey: "oliver", profile: environment.economyStore) }
        #endif
        return environment.backendClient
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
            mainline: mainlineClient,
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

    private var tutorialPresenter: TutorialPresenter {
        { character, finish in
            AnyView(ProductionTutorialView(character: character, environment: environment, onFinish: finish))
        }
    }

    private var chatDeps: ChatDependencies {
        let regionCatalog = environment.regionCatalog
        var dependencies = ChatDependencies(
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
        #if DEBUG
        if bypassesAuthenticationForUITesting {
            dependencies.learningPage = { character, visible in AnyView(Self.debugLearningPage(character, isVisible: visible)) }
        }
        #endif
        dependencies.learningChat = bypassesAuthenticationForUITesting ? nil : environment.workspace?.learningChat
        let backend = environment.backendClient
        let tracker = environment.workspace?.learningChat
        let learningAudioSession = environment.audioSession
        let learningSpeech = environment.speech
        let learningEconomyStore = environment.economyStore
        if !bypassesAuthenticationForUITesting {
            dependencies.learningPage = { character, visible in
                AnyView(CharacterLearningView(character: character, service: backend, isVisible: visible,
                    audioSession: learningAudioSession, speech: learningSpeech,
                    currentRegionID: { try? await learningEconomyStore.profile().currentRegionID },
                    beforePlayback: { await learningSpeech.stopSpeaking() },
                    cycleChanged: { await tracker?.challengeCompleted(characterID: character.id) }))
            }
        }
        #if DEBUG
        dependencies.debugFillLearning = { [preview = bypassesAuthenticationForUITesting] characterID in
            if preview {
                await DebugLearningFillStore.shared.fill(characterID)
            } else {
                let state = try await backend.learningCharacter(characterID)
                try await backend.debugFillLearning(characterID, cycleID: state.cycleId, requestID: UUID())
                await tracker?.refresh(characterID: characterID)
            }
        }
        dependencies.marketingMotionCapture = activeUserID == UUID(uuidString: "019c0123-4567-789a-8bcd-ef01234567f0")
            && bypassesAuthenticationForUITesting
            && ProcessInfo.processInfo.environment["UI_TEST_MARKETING_CAPTURE"] == "1"
            && ProcessInfo.processInfo.environment["UI_TEST_MARKETING_MOTION"] == "1"
        #endif
        return dependencies
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
            audioSession: environment.audioSession)
    }

    private var favoritesDeps: FavoritesDependencies {
        FavoritesDependencies(
            favorites: environment.favoritesStore,
            dictionary: environment.dictionary,
            grammarPoints: environment.grammarPoints,
            speech: environment.speech)
    }

    #if DEBUG
    private static func debugLearningPage(_ character: CharacterDTO, isVisible: Bool = true) -> some View {
        CharacterLearningView(character: character, service: DebugLearningPreviewService(characterID: character.id,
            roleKey: character.card.name.components(separatedBy: " ").first?.lowercased() ?? "oliver"), isVisible: isVisible,
            currentRegionID: { ProcessInfo.processInfo.environment["UI_TEST_REGION"] ?? "london" })
            .safeAreaInset(edge: .top, spacing: 0) {
                Text("界面预览 · 示例进度，不计入账号")
                    .font(.caption).foregroundStyle(.secondary).padding(8).frame(maxWidth: .infinity)
                    .background(Color.dsBackground)
            }
    }
    #endif

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
