import AppointmentFeature
import AuthFeature
import BackendKit
import BillingKit
import ChatFeature
import LearningFeature
import LLMKit
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
    var onExitOnboardingPreview: (() -> Void)?

    @State private var unreadCount = 0
    @State private var selectedTab: AppTab = .messages
    @State private var appointmentPresentation: AppointmentPresentation?
    @State private var appointmentCityID = ""
    @State private var appointmentCharacters: [UUID: CharacterDTO] = [:]
    @State private var memoryCharacterID: UUID?
    private struct AppointmentPresentation: Identifiable {
        let id = UUID()
        let appointmentID: UUID?
        var usesHomeZoomSource = false
        var testView: AppointmentListView? = nil
        var liveTest = false
    }
    private struct HomeRootRoute: Hashable {
        let destination: HomeDestination
    }
    private struct HomeChatRoute: Hashable {
        let character: CharacterDTO
        func hash(into hasher: inout Hasher) { hasher.combine(character.id) }
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.character.id == rhs.character.id }
    }
    @Namespace private var homeTransitionNamespace
    @State private var visitedTabs: Set<AppTab> = []
    @State private var messagesPath = NavigationPath()
    @State private var contactsPath = NavigationPath()
    @State private var messagesNavigationRevision = 0
    @State private var contactsNavigationRevision = 0
    @State private var homePath = NavigationPath()
    @State private var mePath: [MeDestination] = []
    @State private var activationError: String?
    @State private var showSubscription = false
    @State private var showLondonEpisode = false
    @State private var activityJourney = ActivityJourneyCoordinator()
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
    @State private var showsCitySceneGallery = false
    @State private var showsMascotGallery = false
    @State private var showsAppointmentTestScenarios = false
    #endif
    @State private var onboardingPreviewMode: OnboardingPreviewMode?
    @State private var placementCompletionRevision = 0
    @State private var activeUserID: UUID?
    @State private var stateRevision = 0
    @State private var shouldRefreshAfterBackground = false
    @State private var isInitialContentReady = false
    @State private var allowsWorldMapWarmup = false
    @State private var launchVeilVisible = true
    @State private var completedForcedOnboarding = false
    @State private var completedForcedWelcome = false
    @AppStorage("onboarding.welcome.completed.v1") private var welcomeCompleted = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(environment: AppEnvironment, onExitOnboardingPreview: (() -> Void)? = nil) {
        self.environment = environment
        self.onExitOnboardingPreview = onExitOnboardingPreview
        if let mode = environment.onboardingPreviewMode {
            _selectedTab = State(initialValue: mode == .placement ? .me : .messages)
            _showPlacementTest = State(initialValue: mode == .placement)
            return
        }
        #if DEBUG
        let requested = ProcessInfo.processInfo.environment["UI_TEST_TAB"]
        let initial: AppTab = switch requested {
        case "messages": .messages
        case "contacts": .contacts
        case "home", "map", "places-preview", "world-preview", "scenes-preview", "appointments-preview": .home
        case "me", "settings", "subscription", "learning", "favorites", "learning-test": .me
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
        if requested == "settings" {
            _mePath = State(initialValue: [.settings])
        }
        if requested == "subscription" {
            _mePath = State(initialValue: [.subscription])
        }
        if let path = Self.uiTestHomePath() {
            _homePath = State(initialValue: path)
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
    private var isOnboardingPreview: Bool {
        environment.onboardingPreviewMode != nil
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
            .onChange(of: isInitialContentReady) { _, ready in
                #if DEBUG
                if ready && bypassesAuthenticationForUITesting && ProcessInfo.processInfo.environment["UI_TEST_TAB"] == "appointments-preview" {
                    appointmentPresentation = AppointmentPresentation(appointmentID: nil)
                }
                if ready && bypassesAuthenticationForUITesting && ProcessInfo.processInfo.environment["UI_TEST_TAB"] == "scenes-preview" {
                    showsCitySceneGallery = true
                }
                if ready && bypassesAuthenticationForUITesting && ProcessInfo.processInfo.environment["UI_TEST_TAB"] == "mascots-preview" {
                    showsMascotGallery = true
                }
                #endif
            }
            .onChange(of: activeUserID) { _, _ in
                appointmentPresentation = nil
                appointmentCharacters = [:]
                appointmentCityID = ""
            }
            .fullScreenCover(item: $appointmentPresentation) { presentation in
                if presentation.usesHomeZoomSource {
                    appointmentPage(presentation)
                        .navigationTransition(.zoom(sourceID: HomeDestination.appointments, in: homeTransitionNamespace))
                } else {
                    appointmentPage(presentation)
                }
            }
            .overlay(alignment: .topTrailing) { onboardingPreviewExit }
            #if DEBUG
            .fullScreenCover(isPresented: $showsCitySceneGallery) { DebugCitySceneGallery() }
            .fullScreenCover(isPresented: $showsMascotGallery) { DebugMascotGallery() }
            .preferredColorScheme(ProcessInfo.processInfo.environment["UI_TEST_CAPTURE_APPEARANCE"].map { $0 == "dark" ? .dark : .light })
            .fullScreenCover(item: $captureCharacter) { character in
                NavigationStack {
                    if ProcessInfo.processInfo.environment["UI_TEST_NATIVE_CAPTURE"] == "profile" {
                        CharacterProfileView(character: character,
                            regionName: environment.regionCatalog.region(id: character.card.regionID)?.nameZh ?? "",
                            rosterStore: environment.rosterStore,
                            chatBuilder: { AnyView(ChatView(character: $0, deps: chatDeps)) },
                            callBuilder: { AnyView(ChatView(character: $0, deps: chatDeps, startsInRealtimeConversation: true)) })
                    } else if ProcessInfo.processInfo.environment["UI_TEST_TAB"] == "promotion-preview" {
                        DebugLearningPromotionPreview()
                    } else if ProcessInfo.processInfo.environment["UI_TEST_TAB"] == "achievement-preview" {
                        LearningAchievementPreview(character: character,
                            currentRegionID: { ProcessInfo.processInfo.environment["UI_TEST_REGION"] ?? "london" })
                    } else if ProcessInfo.processInfo.environment["UI_TEST_TAB"] == "practice-preview" {
                        LearningPracticePreview(character: character)
                    } else if ProcessInfo.processInfo.environment["UI_TEST_TAB"] == "unit-challenge" {
                        let preview = DebugLearningPreviewService(characterID: character.id, roleKey: "oliver")
                        if let attempt = try? preview.previewAttempt(kind: ProcessInfo.processInfo.environment["UI_TEST_LEARNING_QUESTION"] ?? "choice") {
                            LearningChallengeView(attempt: attempt, character: character, service: preview)
                        }
                    } else if ProcessInfo.processInfo.environment["UI_TEST_TAB"] == "role-learning" {
                        Self.debugLearningPage(character)
                            .navigationTitle("")
                            .toolbarBackground(.hidden, for: .navigationBar)
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
                        if environment.guestOutingProgressConflict {
                            Text("本机阅读与选择会保存为可查看的恢复副本。")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("采用服务器外出进度，继续认领") {
                                environment.adoptGuestServerProgress = true
                                Task { await handleAuthenticationPhase() }
                            }
                        } else if environment.guestOutingChoiceRequired {
                            Text("另一次外出将结束，已读内容与选择会留在足迹中。")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("继续游客的外出") {
                                environment.guestOutingToKeep = "guest"
                                Task { await handleAuthenticationPhase() }
                            }
                            Button("继续账号的外出") {
                                environment.guestOutingToKeep = "account"
                                Task { await handleAuthenticationPhase() }
                            }
                        } else {
                            Button("重试") { Task { await handleAuthenticationPhase() } }
                        }
                        Button("退出此账号") {
                            Task { await environment.authSession.logout() }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
                }
            }
            .sheet(isPresented: $showSubscription) {
                if environment.workspace != nil {
                    myPage(section: .subscription)
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
                   selectedTab != .home || !homePath.isEmpty {
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
                homePath = NavigationPath()
                #if DEBUG
                // 免登录预览在工作区激活时会切换账号；重新进入预览要求的活动页子页面。
                // 地点预览的测试自行从“出去走走”进入，不在这里恢复。
                if bypassesAuthenticationForUITesting, let path = Self.uiTestHomePath(includingActivities: false) { homePath = path }
                #endif
                allowsWorldMapWarmup = false
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
        if isOnboardingPreview {
            do {
                activeUserID = try await environment.activateOnboardingPreviewWorkspace()
                stateRevision += 1
            } catch { activationError = error.localizedDescription }
            return
        }
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

    private enum LaunchScreenPhase: Equatable {
        case loading
        case welcome
        case signIn
        case app
    }

    private var launchPhase: LaunchScreenPhase {
        if !environment.resourcesReady { return .loading }
        if isOnboardingPreview {
            return (activeUserID != nil && environment.workspace != nil) ? .app : .loading
        }
        if showsWelcome { return .welcome }
        switch environment.authSession.phase {
        case .loading:
            return .loading
        case .signedOut:
            if bypassesAuthenticationForUITesting {
                return (activeUserID != nil && environment.workspace != nil) ? .app : .loading
            }
            return .signIn
        case .signedIn(let identity):
            return (activeUserID == identity.userID && environment.workspace?.userID == identity.userID)
                ? .app
                : .loading
        }
    }

    @ViewBuilder
    private var launchContent: some View {
        Group {
            switch launchPhase {
            case .loading:
                launchLoading
            case .welcome:
                WelcomeJourneyView(dictionary: environment.dictionary, grammar: environment.grammarPoints) {
                    welcomeCompleted = true
                    completedForcedWelcome = true
                }
            case .signIn:
                SignInView(session: environment.authSession)
            case .app:
                appContent
            }
        }
        .overlay {
            if launchPhase != .loading {
                Color("BrandLaunchBackground")
                    .ignoresSafeArea()
                    .opacity(launchVeilVisible ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: launchPhase, initial: true) { _, phase in
            if phase == .loading {
                launchVeilVisible = true
            } else if launchVeilVisible {
                withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .easeOut(duration: 0.2)) {
                    launchVeilVisible = false
                }
            }
        }
    }

    private var launchLoading: some View {
        ZStack {
            Color("BrandLaunchBackground").ignoresSafeArea()
            PuffLoadingDots()
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
        if isOnboardingPreview { return true }
        #if DEBUG
        let processEnvironment = ProcessInfo.processInfo.environment
        if processEnvironment["UI_TEST_REQUIRE_AUTHENTICATION"] == "1" {
            return false
        }
        return processEnvironment["UI_TEST_SKIP_ONBOARDING"] == "1"
            || processEnvironment["UI_TEST_ONBOARDING_WELCOME"] != nil
            || processEnvironment["UI_TEST_ONBOARDING_SELECTION"] == "1"
            || processEnvironment["UI_TEST_ONBOARDING_STORY"] == "1"
        #else
        return false
        #endif
    }

    @ViewBuilder
    private var appContent: some View {
        if let accountID = activeUserID,
           environment.workspace?.userID == accountID {
            tabs
            .task(id: "destinations-\(accountID)-\(stateRevision)-\(environment.needsOnboarding == false)") {
                guard environment.needsOnboarding == false, let account = environment.workspace,
                      account.userID == accountID else { return }
                let cache = account.journeyPresentation
                await cache.refreshLocal(economy: account.economyStore, items: account.itemStore,
                    progress: account.storyProgressStore, ticketStubs: account.ticketStubStore)
                guard !Task.isCancelled else { return }
                _ = try? await cache.refreshMainline(using: mainlineClient)
            }
            .task(id: "lazy-warmup-\(accountID)-\(selectedTab == .home || visitedTabs.contains(.home))-\(isInitialContentReady)", priority: .utility) {
                guard isInitialContentReady,
                      environment.needsOnboarding == false,
                      let account = environment.workspace,
                      account.userID == accountID else { return }
                let isHomeActive = selectedTab == .home || visitedTabs.contains(.home)
                // Keep cold launch 100% dedicated to first-screen entry; warm up lazily after settling.
                do { try await Task.sleep(for: .milliseconds(isHomeActive ? 600 : 1_400)) }
                catch { return }
                guard !Task.isCancelled, environment.workspace === account else { return }
                // 信息、联系人、活动、我的与赴约都改为程序化卡通城市，不再预先解码城市照片。
                if isHomeActive {
                    allowsWorldMapWarmup = true
                }
            }
            .background {
                if allowsWorldMapWarmup,
                   let account = environment.workspace, environment.needsOnboarding == false,
                   let profile = account.journeyPresentation.profile {
                    // Mount lazily after the Activity tab settles so MapKit never slows cold launch.
                    WorldMapWarmupView(cache: account.worldMapCache,
                        region: environment.regionCatalog.region(id: profile.currentRegionID),
                        regions: environment.regionCatalog.regions)
                        .opacity(0.02).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            #if DEBUG
            .task(id: "\(accountID.uuidString)-\(stateRevision)-\(environment.needsOnboarding == false)") {
                // 内存账号可能先挂载、后导入角色；等导入完成，避免冷启动丢失预览展示。
                guard ["role-learning", "unit-challenge", "practice-preview", "achievement-preview", "promotion-preview"].contains(ProcessInfo.processInfo.environment["UI_TEST_TAB"] ?? ""),
                      bypassesAuthenticationForUITesting, environment.needsOnboarding == false else { return }
                captureCharacter = try? await environment.rosterStore.allCharacters().first { $0.isMainCharacter }
            }
            #endif
            .fullScreenCover(item: $onboardingPreviewMode) { mode in
                OnboardingPreviewView(mode: mode)
            }
            .fullScreenCover(item: $introductionMode) { mode in
                switch mode {
                case .introduction:
                    JourneyIntroductionView(deps: OnboardingDependencies(
                        economyStore: environment.economyStore,
                        profileCommands: profileCommands,
                        rosterStore: environment.rosterStore,
                        scriptURL: Bundle.main.url(forResource: "onboarding_chat", withExtension: "json")!,
                        dictionary: environment.dictionary,
                        grammarPoints: environment.grammarPoints
                    ))
                case .tutorial:
                    TutorialReplayView(environment: environment)
                }
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
                        grammarPoints: environment.grammarPoints
                    ),
                    placementCompletionRevision: placementCompletionRevision,
                    onRequestPlacement: { showOnboardingPlacement = true },
                    tutorial: tutorialPresenter
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
                .overlay(alignment: .topTrailing) { onboardingPreviewExit }
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
                if tab == selectedTab {
                    returnTabToRoot(tab)
                } else {
                    selectedTab = tab
                }
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
        .tint(PuffCandy.sky.base)
        .sensoryFeedback(.selection, trigger: selectedTab)
        .background {
            NavigationTouchShieldInstaller()
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

    #if DEBUG
    /// 预览与界面测试要求直接打开的活动页子页面。
    private static func uiTestHomePath(includingActivities: Bool = true) -> NavigationPath? {
        let environment = ProcessInfo.processInfo.environment
        let requested = environment["UI_TEST_TAB"]
        var path = NavigationPath()
        if requested == "map" {
            path.append(HomeRootRoute(destination: .map))
        } else if ["places-preview", "world-preview"].contains(requested ?? "") || environment["UI_TEST_HOME_DESTINATION"] == "activities" {
            guard includingActivities else { return nil }
            path.append(HomeRootRoute(destination: .activities))
        } else if environment["UI_TEST_HOME_DESTINATION"] == "mainline" {
            path.append(HomeRootRoute(destination: .stories))
            path.append(HomeDestination.mainline)
        } else if environment["UI_TEST_HOME_DESTINATION"] == "cityStories" {
            path.append(HomeRootRoute(destination: .stories))
            path.append(HomeDestination.cityStories)
        } else {
            return nil
        }
        return path
    }
    #endif

    /// 点击事件独立于 selectedTab 的变化，因此重复点击当前标签也会返回入口。
    private func returnTabToRoot(_ tab: AppTab) {
        switch tab {
        case .messages:
            if !messagesPath.isEmpty { messagesPath = NavigationPath() }
            messagesNavigationRevision += 1
        case .contacts:
            if !contactsPath.isEmpty { contactsPath = NavigationPath() }
            contactsNavigationRevision += 1
        case .home:
            if !homePath.isEmpty { homePath = NavigationPath() }
        case .me:
            if showPlacementTest { showPlacementTest = false }
            if showEnglishJourney { showEnglishJourney = false }
            if !mePath.isEmpty { mePath.removeAll() }
        }
    }

    private var usesTabDesignPreview: Bool {
        #if DEBUG
        bypassesAuthenticationForUITesting
            && ProcessInfo.processInfo.environment["UI_TEST_TAB_DESIGN_PREVIEW"] == "1"
        #else
        false
        #endif
    }

    private var homeRootContent: some View {
        HomeView(
            deps: homeDeps,
            reloadToken: stateRevision,
            isVisible: selectedTab == .home && homePath.isEmpty && appointmentPresentation == nil,
            activityNamespace: activityStorageNamespace,
            transitionNamespace: homeTransitionNamespace,
            onInitialLoad: {
                guard environment.needsOnboarding == false else { return }
                isInitialContentReady = true
            },
            onOpenDestination: openHomeDestination,
            onOpenAppointment: {
                appointmentPresentation = AppointmentPresentation(appointmentID: $0, usesHomeZoomSource: true)
            }
        )
        .id("home-root")
    }

    private var homeStack: some View {
        NavigationStack(path: $homePath) {
            homeRootContent
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: HomeRootRoute.self) { route in
                    homeDestinationView(route.destination)
                        .id(route.destination)
                        .navigationTitle(route.destination.navigationTitle)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar(route.destination == .stories ? .visible : .hidden, for: .navigationBar)
                        .navigationTransition(.zoom(sourceID: route.destination, in: homeTransitionNamespace))
                        .dsKeepsNavigationBarVisible(route.destination == .stories)
                }
                .navigationDestination(for: HomeDestination.self) { destination in
                    Group {
                        switch destination {
                        case .mainline:
                            MainlineListView(deps: homeDeps) { chapter in
                                homePath.append(chapter)
                            }
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar(.visible, for: .navigationBar)
                        case .cityStories:
                            CityStoryListView(deps: homeDeps) { chapter in
                                homePath.append(chapter)
                            }
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar(.visible, for: .navigationBar)
                        case .map, .stories, .activities, .appointments:
                            EmptyView()
                        }
                    }
                    .navigationTransition(.zoom(sourceID: destination, in: homeTransitionNamespace))
                    .dsKeepsNavigationBarVisible(destination == .mainline || destination == .cityStories)
                }
                .navigationDestination(for: MainlineChapter.self) { chapter in
                    storyView(storyID: chapter.storyID)
                }
                .navigationDestination(for: CityStoryChapter.self) { chapter in
                    storyView(storyID: chapter.storyID)
                }
                .navigationDestination(for: HomeChatRoute.self) { route in
                    ChatView(character: route.character, deps: chatDeps)
                }
        }
        .environment(\.puffZoomNamespace, homeTransitionNamespace)
        .onChange(of: homePath.isEmpty) { _, isEmpty in
            if isEmpty, activityJourney.hasOpenOuting, !activityJourney.isPreparing {
                activityJourney.reset()
            }
        }
    }

    @ViewBuilder
    private func appointmentPage(_ presentation: AppointmentPresentation) -> some View {
        let reading = AppointmentReadingServices(dictionary: environment.dictionary, grammar: environment.grammarPoints,
            favorites: environment.favoritesStore, speech: environment.speech,
            characterNarration: { [roster = environment.rosterStore] id, text in
                guard let character = try? await roster.character(id: id) else { return nil }
                let hint = SpeechVoiceHint(stableID: character.id.uuidString.lowercased(),
                    gender: character.card.gender.rawValue, nationality: character.card.nationality,
                    supertonicVoice: character.card.resolvedReadingVoice)
                return StoryVoiceCasting.request(text: text, speaker: character.card.name, fallback: hint,
                    language: AccentMapper.language(forNationality: character.card.nationality))
            })
        let close = { appointmentPresentation = nil }
        #if DEBUG
        if presentation.liveTest {
            LiveAppointmentTestView(dictionary: environment.dictionary, grammar: environment.grammarPoints,
                speech: environment.speech, onClose: close)
                .dictionaryPopupServices(DictionaryPopupServices(examples: .init(translate: { _ in nil })))
        } else if let testView = presentation.testView {
            testView.dictionaryPopupServices(DictionaryPopupServices(examples: .init(translate: { _ in nil })))
        } else if bypassesAuthenticationForUITesting && (ProcessInfo.processInfo.environment["UI_TEST_TAB"] == "appointments-preview" || usesTabDesignPreview) {
            if ProcessInfo.processInfo.environment["UI_TEST_APPOINTMENT_SCENARIO"] == "summary-design" {
                AppointmentSummaryDesignPreview(onClose: close)
            } else {
                AppointmentListView.previewFixture(
                    scenario: ProcessInfo.processInfo.environment["UI_TEST_APPOINTMENT_SCENARIO"] ?? "confirmed",
                    readingServices: reading, onClose: close,
                    onChat: { _ in close() }, onMemory: { _ in close() })
            }
        } else {
            liveAppointmentPage(presentation, reading: reading)
        }
        #else
        liveAppointmentPage(presentation, reading: reading)
        #endif
    }

    private func liveAppointmentPage(_ presentation: AppointmentPresentation, reading: AppointmentReadingServices) -> some View {
        let workspace = environment.workspace
        let coordinator = workspace.map { AppointmentCoordinator(backend: environment.backendClient, sync: $0.contentSync) }
        return AppointmentListView(client: environment.backendClient, currentCityID: appointmentCityID,
            storageNamespace: activeUserID?.uuidString ?? "inactive", initialAppointmentID: presentation.appointmentID,
            readingServices: reading, settle: { id in try await coordinator?.settle(id) },
            onClose: { appointmentPresentation = nil },
            characterName: { appointmentCharacters[$0]?.displayName ?? "旅伴" },
            characterCards: appointmentCharacters.mapValues(\.card),
            onChat: { id in
                appointmentPresentation = nil
                Task { @MainActor in
                    guard let character = try? await environment.rosterStore.character(id: id) else { return }
                    selectedTab = .home
                    var path = NavigationPath()
                    path.append(HomeRootRoute(destination: .activities))
                    path.append(HomeChatRoute(character: character))
                    homePath = path
                }
            }, onMemory: { characterID in
                appointmentPresentation = nil
                memoryCharacterID = characterID
                selectedTab = .me
                openMe(.memory)
            })
            .task {
                let accountID = activeUserID
                let cityID = try? await environment.economyStore.profile().currentRegionID
                let characters = try? await environment.rosterStore.allCharacters()
                guard !Task.isCancelled, activeUserID == accountID else { return }
                appointmentCityID = cityID ?? ""
                if let characters {
                    appointmentCharacters = Dictionary(uniqueKeysWithValues: characters.map { ($0.id, $0) })
                }
            }
            .overlay {
                if case .signedOut = environment.authSession.phase {
                    PuffEmptyState("登录后保存约定", bird: .gugu, pose: .wave) {
                        Button("前往账号") {
                            appointmentPresentation = nil
                            selectedTab = .me
                            openMe(.account)
                        }.buttonStyle(PuffCandyButtonStyle(.sky))
                        Button("返回活动") { appointmentPresentation = nil }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("appointment.signIn.close")
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.dsBackground)
                }
            }
    }

    // Keep each route's concrete type behind the navigation boundary. Combining
    // every scene in one ViewBuilder crashes Swift's runtime metadata decoder
    // on device when the story hub is first presented. The caller owns route identity.
    private func homeDestinationView(_ destination: HomeDestination) -> AnyView {
        switch destination {
        case .appointments:
            return AnyView(EmptyView())
        case .stories:
            return AnyView(StoryHubView(deps: homeDeps))
        case .mainline:
            return AnyView(MainlineListView(deps: homeDeps) { chapter in
                homePath.append(chapter)
            })
        case .cityStories:
            return AnyView(CityStoryListView(deps: homeDeps) { chapter in
                homePath.append(chapter)
            })
        case .activities:
            return AnyView(
                ActivitiesView(
                    journey: activityJourney,
                    deps: homeDeps,
                    storageNamespace: activityStorageNamespace,
                    isVisible: selectedTab == .home && !showLondonEpisode && homePath.count == 1,
                    onClose: closeHomeDestination,
                    onChat: { character in
                        homePath.append(HomeChatRoute(character: character))
                    }
                )
                .id(activeUserID?.uuidString ?? "inactive")
            )
        case .map:
            return AnyView(MapView(
                deps: mapDeps,
                reloadToken: stateRevision,
                onBack: closeHomeDestination
            ))
        }
    }

    private func openHomeDestination(_ destination: HomeDestination) {
        if destination == .appointments {
            appointmentPresentation = AppointmentPresentation(appointmentID: nil, usesHomeZoomSource: true)
            return
        }
        guard homePath.isEmpty else { return }
        homePath.append(HomeRootRoute(destination: destination))
    }

    private var activityStorageNamespace: String {
        #if DEBUG
        if isWorldOutingPreview {
            return "debug.world-outing.preview.v1." + (ProcessInfo.processInfo.environment["UI_TEST_ACTIVITY_NAMESPACE"] ?? "manual")
        }
        if isPlaceOutingPreview {
            return "debug.place-outing.preview.v1." + (ProcessInfo.processInfo.environment["UI_TEST_ACTIVITY_NAMESPACE"] ?? "manual")
        }
        if let testNamespace = ProcessInfo.processInfo.environment["UI_TEST_ACTIVITY_NAMESPACE"], !testNamespace.isEmpty {
            return "ui-test.\(testNamespace)"
        }
        #endif
        return activeUserID?.uuidString ?? "inactive"
    }
    private func closeHomeDestination() {
        guard !homePath.isEmpty else { return }
        if activityJourney.hasOpenOuting {
            if activityJourney.isPreparing {
                homePath.removeLast()
            } else {
                withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .smooth(duration: 0.30, extraBounce: 0)) {
                    activityJourney.reset()
                }
            }
            return
        }
        homePath.removeLast()
    }
    private var messagesStack: some View {
        ZStack {
            NavigationStack(path: $messagesPath) {
                ConversationListView(
                    accountID: requiredActiveAccountID,
                    deps: chatDeps,
                    reloadToken: stateRevision,
                    resetToken: messagesNavigationRevision
                )
            }
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
                    resetToken: contactsNavigationRevision,
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
            isVisible: selectedTab == .me,
            regionCatalog: environment.regionCatalog,
            onCalibrateLevel: { showEnglishJourney = true },
            onOpenFavorites: { openMe(.favorites) },
            onOpenSettings: { openMe(.settings) },
            section: section,
            onOpenAccount: { openMe(.account) },
            onOpenSubscription: { openMe(.subscription) }
        )
        .id("me-root")
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

    private var learningTrialAction: (@MainActor () -> Void)? {
        #if DEBUG
        { openMe(.learningTrial) }
        #else
        nil
        #endif
    }

    private var appointmentTestAction: (@MainActor () -> Void)? {
        #if DEBUG
        { showsAppointmentTestScenarios = true }
        #else
        nil
        #endif
    }

    #if DEBUG
    private func startAppointmentTest(_ scenario: String) {
        let reading = (try? ModelContainerFactory.makeContainer(inMemory: true)).map { container in
            AppointmentReadingServices(dictionary: environment.dictionary, grammar: environment.grammarPoints,
                favorites: FavoritesStore(modelContainer: container), speech: environment.speech)
        }
        let close = { appointmentPresentation = nil }
        let test = AppointmentListView.previewFixture(scenario: scenario, readingServices: reading,
            onClose: close, backLabel: "返回设置", onChat: { _ in close() }, onMemory: { _ in close() })
        appointmentPresentation = AppointmentPresentation(appointmentID: nil, testView: test)
    }
    #endif

    private func openMe(_ destination: MeDestination) {
        mePath.append(destination)
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
                onOpenTutorial: { introductionMode = .tutorial },
                onTestInitialPlacement: initialPlacementTestAction,
                onTestFirstLoginFlow: firstLoginTestAction,
                onTestAppointments: appointmentTestAction,
                onOpenLearningTrial: learningTrialAction
            )
            #if DEBUG
            .confirmationDialog("测试原生赴约", isPresented: $showsAppointmentTestScenarios, titleVisibility: .visible) {
                Button("真实赴约") { appointmentPresentation = .init(appointmentID: nil, liveTest: true) }
                Button("模拟断线恢复") { startAppointmentTest("reconnect") }
                Button("模拟回执丢失") { startAppointmentTest("retry") }
            } message: {
                Text("真实赴约使用独立测试账号和服务端剧情。模拟场景用于验证重试交互。")
            }
            #endif

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
                ),
                initialCharacterID: memoryCharacterID
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
                    if preview { return "测试档案：目标水平保留 0 颗星、0 点。此操作仅修改本次测试档案。" }
                    let journey = try await client.learningJourney()
                    guard let target = journey.levels.first(where: { $0.level == level.rawValue }) else { throw URLError(.cannotParseResponse) }
                    let supply = target.publishedUnitCount == 0 ? "该水平目前没有已发布单元，聊天满条后需等待题库准备。" : "各旅伴的可用挑战以角色学习页为准；题库不足时会保留聊天进度。"
                    return "目标水平已保留 \(target.stars) 颗星、\(target.points) 点。其他水平的进度也会保留。\n\n\(supply)"
                }
            ),
            usesNativeNavigation: !isOnboarding,
            startsWithLevelSelection: !isOnboarding && chooseLevel,
            startsWithQuestions: isOnboarding || isOnboardingPreview,
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
                    placementCompletionRevision += 1
                } else {
                    showPlacementTest = false; showEnglishJourney = false
                }
            }
        )
        .overlay(alignment: .topTrailing) { onboardingPreviewExit }
    }

    private var initialPlacementTestAction: (@MainActor () -> Void)? {
        guard !isOnboardingPreview else { return nil }
        return { onboardingPreviewMode = .placement }
    }

    private var firstLoginTestAction: (@MainActor () -> Void)? {
        guard !isOnboardingPreview else { return nil }
        return { onboardingPreviewMode = .completeFlow }
    }

    @ViewBuilder
    private var onboardingPreviewExit: some View {
        if let onExitOnboardingPreview {
            Button("结束测试", action: onExitOnboardingPreview)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(.regularMaterial, in: Capsule())
                .padding(8)
                .accessibilityIdentifier("onboarding-test.exit")
        }
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

    private var homeAppointmentService: (any AppointmentServing)? {
        guard case .signedIn = environment.authSession.phase else { return nil }
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
            favorites: environment.favoritesStore,
            dictionary: environment.dictionary,
            grammarPoints: environment.grammarPoints,
            speech: environment.speech,
            mainline: mainlineClient,
            npcRegistry: isPlaceOutingPreview ? nil : environment.backendClient,
            outingGateway: placeOutingGateway,
            activityReleaseID: placeOutingReleaseID,
            appointments: homeAppointmentService,
            presentationCache: activityPresentationCache
        )
    }

    private var activityPresentationCache: JourneyPresentationCache? {
        #if DEBUG
        if isPlaceOutingPreview, ProcessInfo.processInfo.environment["UI_TEST_ACTIVITY_CATALOG_RETRY"] == "1" {
            return nil
        }
        #endif
        return environment.workspace?.journeyPresentation
    }

    private var isPlaceOutingPreview: Bool {
        #if DEBUG
        bypassesAuthenticationForUITesting && ProcessInfo.processInfo.environment["UI_TEST_TAB"] == "places-preview"
        #else
        false
        #endif
    }
    private var isWorldOutingPreview: Bool {
        #if DEBUG
        bypassesAuthenticationForUITesting && (usesTabDesignPreview || ProcessInfo.processInfo.environment["UI_TEST_TAB"] == "world-preview"
            || ProcessInfo.processInfo.environment["UI_TEST_WORLD_GATEWAY"] == "1")
        #else
        false
        #endif
    }
    private var placeOutingGateway: any OutingGateway {
        #if DEBUG
        if isPlaceOutingPreview { return DebugPlaceOutingGateway.shared }
        if isWorldOutingPreview { return DebugPlaceOutingGateway.world }
        #endif
        return environment.backendClient
    }
    private var placeOutingReleaseID: String? {
        #if DEBUG
        if isPlaceOutingPreview { return "debug-places-preview-v1" }
        #endif
        return CityActivityRelease.bundled()?.releaseId
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
            storyProgress: environment.storyProgressStore,
            presentationCache: environment.workspace?.journeyPresentation,
            mapCache: environment.workspace?.worldMapCache
        )
    }

    private var tutorialPresenter: TutorialPresenter {
        { character, finish in
            AnyView(ProductionTutorialView(character: character, environment: environment, onFinish: finish))
        }
    }

    private var chatDeps: ChatDependencies {
        let regionCatalog = environment.regionCatalog
        var llm: any LLMClient = environment.llmRouter
        var replyDelayScale = 1.0
        #if DEBUG
        if bypassesAuthenticationForUITesting,
           ProcessInfo.processInfo.environment["UI_TEST_CHAT_TIMELINE_WORKFLOW"] == "1" {
            llm = DebugChatTimelineProvider()
            replyDelayScale = 0
        }
        #endif
        var dependencies = ChatDependencies(
            accessClient: environment.backendClient,
            onShowAccess: { showSubscription = true },
            chatStore: environment.chatStore,
            rosterStore: environment.rosterStore,
            favorites: environment.favoritesStore,
            llm: llm,
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
            },
            replyDelayScale: replyDelayScale
        )
        if !bypassesAuthenticationForUITesting {
            dependencies.sharedGrammarAnalysis = environment.sharedGrammarAnalyzer
        }
        #if DEBUG
        if bypassesAuthenticationForUITesting,
           ProcessInfo.processInfo.environment["UI_TEST_GRAMMAR_FIXTURE"] != nil {
            dependencies.sharedGrammarAnalysis = { sentence, _ in
                try await SharedGrammarRequest.analyze { operationID in
                    try await DebugGrammarAnalysisFixture.shared.analyze(sentence: sentence, operationID: operationID)
                }
            }
        }
        #endif
        #if DEBUG
        if bypassesAuthenticationForUITesting {
            dependencies.learningPage = { character, visible, openSettings in AnyView(Self.debugLearningPage(character, isVisible: visible, onOpenChatSettings: openSettings)) }
        }
        #endif
        dependencies.storyProgress = environment.storyProgressStore
        if !bypassesAuthenticationForUITesting, case .signedIn = environment.authSession.phase, let workspace = environment.workspace {
            dependencies.sharedChat = workspace.contentSync
            let appointments = AppointmentCoordinator(backend: environment.backendClient, sync: workspace.contentSync)
            dependencies.refreshAppointments = { characterID, conversationID, detect in
                try await appointments.refresh(characterID: characterID, conversationID: conversationID, detect: detect)
            }
            dependencies.appointmentContext = { characterID in
                (try? await AsyncDeadline.run(timeout: .seconds(3)) { await appointments.context(characterID: characterID) }) ?? nil
            }
            dependencies.onOpenAppointment = { id in
                appointmentPresentation = AppointmentPresentation(appointmentID: id)
            }
        }
        dependencies.learningChat = bypassesAuthenticationForUITesting ? nil : environment.workspace?.learningChat
        let backend = environment.backendClient
        let tracker = environment.workspace?.learningChat
        let learningAudioSession = environment.audioSession
        let learningSpeech = environment.speech
        let learningEconomyStore = environment.economyStore
        let learningUserState = environment.userState
        let learningWorkspace = environment.workspace
        if !bypassesAuthenticationForUITesting {
            dependencies.learningPage = { character, visible, openSettings in
                AnyView(CharacterLearningView(character: character, service: backend, isVisible: visible,
                    audioSession: learningAudioSession, speech: learningSpeech,
                    currentRegionID: { try? await learningEconomyStore.profile().currentRegionID },
                    beforePlayback: { await learningSpeech.stopSpeaking() },
                    cycleChanged: { await tracker?.challengeCompleted(characterID: character.id) },
                    promotionCompleted: {
                        try await learningUserState.synchronize()
                        guard environment.workspace === learningWorkspace else { throw CancellationError() }
                        let profile = try await learningEconomyStore.profile()
                        await environment.applyLearnerProfile(profile)
                    }, onOpenChatSettings: openSettings))
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
        dependencies.showsTimelineEventPreview = bypassesAuthenticationForUITesting
            && ProcessInfo.processInfo.environment["UI_TEST_WELCOME_CAPTURE"] == "1"
            && ProcessInfo.processInfo.environment["UI_TEST_CHAT_TIMELINE_EVENTS"] == "1"
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
    private static func debugLearningPage(_ character: CharacterDTO, isVisible: Bool = true,
                                          onOpenChatSettings: (@MainActor @Sendable () -> Void)? = nil) -> some View {
        CharacterLearningView(character: character, service: DebugLearningPreviewService(characterID: character.id,
            roleKey: character.card.name.components(separatedBy: " ").first?.lowercased() ?? "oliver"), isVisible: isVisible,
            currentRegionID: { ProcessInfo.processInfo.environment["UI_TEST_REGION"] ?? "london" },
            onOpenChatSettings: onOpenChatSettings)
            .safeAreaInset(edge: .top, spacing: 0) {
                Text("界面预览 · 示例进度，不计入账号")
                    .font(.caption).foregroundStyle(.secondary).padding(8).frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial, ignoresSafeAreaEdges: [])
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
              !isOnboardingPreview,
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
