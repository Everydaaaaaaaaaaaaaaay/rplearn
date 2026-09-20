import BackendKit
import BillingKit
import CoreKit
import DesignSystem
import DictKit
import DomainKit
import Foundation
import LLMKit
import MediaKit
import PersistenceKit
import SpeechKit
import SwiftData
import SyncKit
import UIKit

/// 组合根：持有全部服务实例并向下注入。后续单元逐步填充。
@MainActor
@Observable
final class AppEnvironment {
    let keychain: KeychainStore
    let backendClient: BackendClient
    let authSession: AuthSession
    let llmRouter: LLMRouter
    let dictionaryExampleTranslations: BackendDictionaryExampleTranslationResolver
    private struct LaunchResources: Sendable {
        let dictionary: DictDatabase
        let grammarPoints: GrammarPointStore
        let regionCatalog: RegionCatalog
    }

    private var resources: LaunchResources?
    private let resourcesTask: Task<LaunchResources, Never>
    var resourcesReady: Bool { resources != nil }
    var dictionary: DictDatabase { requiredResources.dictionary }
    var grammarPoints: GrammarPointStore { requiredResources.grammarPoints }
    var regionCatalog: RegionCatalog { requiredResources.regionCatalog }

    private var requiredResources: LaunchResources {
        guard let resources else { preconditionFailure("启动资源尚未就绪") }
        return resources
    }

    func prepareResources() async {
        guard resources == nil else { return }
        let startedAt = ContinuousClock.now
        resources = await resourcesTask.value
        Log.app.info("启动耗时：等待随包资源 \(String(describing: startedAt.duration(to: .now)), privacy: .public)")
    }

    private(set) var workspace: AccountWorkspace?

    var modelContainer: ModelContainer { requiredWorkspace.modelContainer }
    var accountCacheStore: AccountCacheStore { requiredWorkspace.accountCacheStore }
    var contentSyncStore: ContentSyncStore { requiredWorkspace.contentSyncStore }
    var voiceMediaQueueStore: VoiceMediaQueueStore { requiredWorkspace.voiceMediaQueueStore }
    var chatStore: ChatStore { requiredWorkspace.chatStore }
    var npcAvatars: PublicNPCAvatarCoordinator { requiredWorkspace.npcAvatars }
    var rosterStore: RosterStore { requiredWorkspace.rosterStore }
    var economyStore: EconomyStore { requiredWorkspace.economyStore }
    var favoritesStore: FavoritesStore { requiredWorkspace.favoritesStore }
    var memoryStore: MemoryStore { requiredWorkspace.memoryStore }
    var itemStore: ItemStore { requiredWorkspace.itemStore }
    var storyProgressStore: StoryProgressStore { requiredWorkspace.storyProgressStore }
    var ticketStubStore: TicketStubStore { requiredWorkspace.ticketStubStore }
    var localUserState: LocalUserStateCoordinator { requiredWorkspace.localUserState }
    var localTravelService: TravelService { requiredWorkspace.localTravelService }
    var localEconomyService: EconomyService { requiredWorkspace.localEconomyService }
    var travelService: TravelService { requiredWorkspace.travelService }
    var userState: BackendUserStateCoordinator { requiredWorkspace.userState }
    var contentSync: BackendContentSyncCoordinator { requiredWorkspace.contentSync }
    var voiceMedia: VoiceMediaCoordinator { requiredWorkspace.voiceMedia }
    var proactiveMessages: ProactiveMessageCoordinator { requiredWorkspace.proactiveMessages }
    var billing: BillingController { requiredWorkspace.billing }
    var economyService: EconomyService { requiredWorkspace.economyService }

    /// nil = 尚未加载；true = 需要走首启引导。
    var needsOnboarding: Bool?
    let audioSession: AudioSessionCoordinator
    let speech: AdaptiveSpeechService
    let translator: TranslationService

    private var requiredWorkspace: AccountWorkspace {
        guard let workspace else {
            preconditionFailure("Account-scoped service requested before account activation")
        }
        return workspace
    }

    init() {
        // 文件读取与解码不占用主线程；同时允许账号恢复独立进行。
        resourcesTask = Task.detached(priority: .userInitiated) {
            let bundle = Bundle.main
            return LaunchResources(
                dictionary: try! DictDatabase(databaseURL: bundle.url(forResource: "learner_dictionary", withExtension: "sqlite")!),
                grammarPoints: try! GrammarPointStore(url: bundle.url(forResource: "grammar_points", withExtension: "json")!),
                regionCatalog: try! RegionCatalog(url: bundle.url(forResource: "regions", withExtension: "json")!)
            )
        }
        // 语音按需可用，预热由首屏后的任务统一调度。
        let audioSession = AudioSessionCoordinator()
        self.audioSession = audioSession
        let speech = AdaptiveSpeechService(audioSession: audioSession)
        self.speech = speech

        let keychain = KeychainStore()
        self.keychain = keychain
        LLMSettingsStore.purgeLegacyClientConfiguration(keychain: keychain)
        let backendClient = BackendClient(
            configuration: .live,
            credentialStore: KeychainAuthCredentialStore(keychain: keychain),
            guestCredentialStore: KeychainAuthCredentialStore(keychain: keychain, isGuest: true),
            guestInstallationKey: try? GuestInstallationStore(keychain: keychain).loadOrCreate()
        )
        self.backendClient = backendClient
        let deviceID =
            (try? DeviceIdentifierStore(keychain: keychain).loadOrCreate())
            ?? UUID().uuidString.lowercased()
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String
        self.authSession = AuthSession(
            client: backendClient,
            device: BackendDevice(
                appVersion: version,
                deviceID: deviceID,
                deviceName: UIDevice.current.name
            )
        )
        self.llmRouter = LLMRouter(
            client: BackendLLMProvider(backend: backendClient)
        )
        self.translator = TranslationService(llm: llmRouter)
        self.dictionaryExampleTranslations = BackendDictionaryExampleTranslationResolver(
            backend: backendClient, guestID: deviceID
        )

        Log.app.info("AppEnvironment initialized")
        Task { await authSession.bootstrap() }
    }

    /// 首启引导数据：确保用户档案存在并导入 3 主角色（幂等），并判定是否需要首启引导。
    func activateUser(_ identity: AuthIdentity) async throws -> UserStateActivation {
        let startedAt = ContinuousClock.now
        defer { Log.app.info("启动耗时：账号工作区 \(String(describing: startedAt.duration(to: .now)), privacy: .public)") }
        needsOnboarding = nil
        await deactivateAccount()

        let defaults = UserDefaults.standard
        let legacyOwnerID = defaults.string(forKey: "backend.state.cached-owner.v1")
            .flatMap(UUID.init(uuidString:))
        let legacyWasGuest = defaults.bool(forKey: "backend.state.guest-owner.v1")
        let preparation = try await Task.detached(priority: .userInitiated) {
            try AccountStoreLocation.prepare(
                for: identity.userID,
                legacyOwnerID: legacyOwnerID,
                legacyWasGuest: legacyWasGuest
            )
        }.value
        let storeURL = preparation.storeURL
        let databaseStartedAt = ContinuousClock.now
        let container = try await Task.detached(priority: .userInitiated) {
            try ModelContainerFactory.makeContainer(storeURL: storeURL)
        }.value
        Log.app.info("启动耗时：打开账号数据库 \(String(describing: databaseStartedAt.duration(to: .now)), privacy: .public)")
        let account = await AccountWorkspace(
            userID: identity.userID,
            modelContainer: container,
            backend: backendClient,
            llm: llmRouter
        )
        try Task.checkCancellation()
        workspace = account

        do {
            let shouldCaptureGuestProfile: Bool
            if preparation.importedLegacyStore {
                shouldCaptureGuestProfile = await account.userState.shouldCaptureGuestProfileForImport()
            } else {
                shouldCaptureGuestProfile = false
            }
            let guestProfile = shouldCaptureGuestProfile
                ? try? await account.economyStore.profile()
                : nil
            let hasGuestNPCs = guestProfile != nil
                ? try await account.rosterStore.allCharacters().contains(where: { !$0.isMainCharacter })
                : false
            if let guestProfile,
               guestProfile.hasCompletedProfileSetup
                    || guestProfile.hasCompletedOnboarding
                    || hasGuestNPCs {
                try await account.contentSyncStore.archiveGuestJourneyIfNeeded(
                    profile: guestProfile,
                    beforeLogin: true
                )
                do {
                    try await account.userState.activateAnonymous(
                        legacyProfile: guestProfile,
                        completedStories: try await account.storyProgressStore.completedStoryIDs(),
                        hadStarterTicket: try await account.itemStore.hasTicket(source: .quest)
                    )
                } catch let error as BackendClientError where error.code == "GUEST_ALREADY_CLAIMED" || error == .signedOut {
                    // The claim endpoint below verifies whether this is the same destination account.
                }
                try await backendClient.claimGuestJourney()
            }
            let stateStartedAt = ContinuousClock.now
            let activation = try await account.userState.activate(userID: identity.userID, preferCache: true)
            Log.app.info("启动耗时：用户状态 \(String(describing: stateStartedAt.duration(to: .now)), privacy: .public)，路径 \(String(describing: activation), privacy: .public)")
            if let guestProfile {
                _ = try await account.userState.importGuestLearnerProfileIfNeeded(guestProfile)
            }
            await account.billing.activate(identity: identity, refreshImmediately: false)
            let profile = try await account.economyStore.profile()
            try await importMainCharacters(into: account)
            let contentStartedAt = ContinuousClock.now
            let contentActivation = try await account.contentSync.activate(userID: identity.userID, preferCache: true)
            Log.app.info("启动耗时：内容激活 \(String(describing: contentStartedAt.duration(to: .now)), privacy: .public)，路径 \(String(describing: contentActivation), privacy: .public)")
            try await reconcileMainCharacters(profile: profile)
            await account.voiceMedia.activate(userID: identity.userID)
            needsOnboarding = !profile.hasCompletedOnboarding
            return activation
        } catch {
            await deactivateAccount()
            throw error
        }
    }

    func deactivateAccount() async {
        needsOnboarding = nil
        guard let current = workspace else { return }
        current.billing.deactivate()
        await current.contentSync.deactivate()
        await current.voiceMedia.deactivate()
        await current.proactiveMessages.deactivate()
        workspace = nil
    }

    #if DEBUG
    /// UI screenshots and interaction tests use an explicit in-memory fixture. Production builds
    /// have no signed-out workspace and therefore cannot enter the application as a guest.
    func activateUITestWorkspace() async throws -> UUID {
        if let workspace { return workspace.userID }
        let userID = UUID(uuidString: "019c0123-4567-789a-8bcd-ef01234567f0")!
        let container = try await Task.detached(priority: .userInitiated) {
            try ModelContainerFactory.makeContainer(inMemory: true)
        }.value
        let account = await AccountWorkspace(
            userID: userID,
            modelContainer: container,
            backend: backendClient,
            llm: llmRouter
        )
        try Task.checkCancellation()
        workspace = account
        try await importMainCharacters(into: account)
        // Exercise the real profile-driven backgrounds without touching a persisted account.
        if let regionID = ProcessInfo.processInfo.environment["UI_TEST_CITY_TAB_REGION"],
           regionCatalog.region(id: regionID) != nil {
            _ = try await account.economyStore.updateProfile { $0.currentRegionID = regionID }
        }
        let profile = try await account.economyStore.profile()
        try await account.rosterStore.configureMainCharacters(
            unlockedRegionIDs: Set(MainlineCatalog.journeys.map(\.starterRegionID)),
            difficulty: profile.difficultyLevel
        )
        if ProcessInfo.processInfo.environment["UI_TEST_WELCOME_CAPTURE"] == "1",
           ProcessInfo.processInfo.environment["UI_TEST_MARKETING_CAPTURE"] != "1",
           let ruby = try await account.rosterStore.allCharacters().first(where: { $0.card.regionID == "melbourne" && $0.isMainCharacter }) {
            let conversation = try await account.chatStore.openConversation(characterID: ruby.id)
            var lines: [(MessageRole, String)] = [
                (.assistant, "How did your first day go? Found any good coffee yet?"),
                (.user, "Not yet! I went for a walk by the river instead."),
                (.assistant, "Good choice. That’s my favourite place to clear my head."),
                (.user, "I’d love to find a quiet café tomorrow."),
                (.assistant, "There’s a cosy little place near the river. Big windows, good coffee, no loud music."),
                (.assistant, "Want me to send you the name?")
            ]
            if ProcessInfo.processInfo.environment["UI_TEST_DICTIONARY_EXAMPLES"] == "1" {
                lines = [(.assistant, "Just finished my coffee. Which would you prefer, tea or coffee?")]
            }
            if ProcessInfo.processInfo.environment["UI_TEST_SHARED_EXAMPLES"] == "1" {
                lines = [(.assistant, "The coffee smells wonderful today.")]
            }
            if ProcessInfo.processInfo.environment["UI_TEST_RUNTIME_EXAMPLES"] == "1" {
                lines = [(.assistant, "Murmuration was the word we discussed today.")]
            }
            for (index, line) in lines.enumerated() {
                _ = try await account.chatStore.appendMessage(conversationID: conversation.id,
                    role: line.0, text: line.1, createdAt: Date().addingTimeInterval(Double(index - lines.count) * 60))
            }
        }
        if ProcessInfo.processInfo.environment["UI_TEST_MARKETING_CAPTURE"] == "1" {
            try await seedMarketingCapture(into: account)
        }
        needsOnboarding = ProcessInfo.processInfo.environment["UI_TEST_SKIP_ONBOARDING"] != "1"
        return userID
    }
    #endif

    private func importMainCharacters(into account: AccountWorkspace) async throws {
        let seedsURL = Bundle.main.url(
            forResource: "main_characters",
            withExtension: "json"
        )!
        let cards = try await Task.detached(priority: .userInitiated) {
            try SeedData.mainCharacterCards(url: seedsURL)
        }.value
        try await account.rosterStore.importMainCharactersIfNeeded(cards: cards)
    }

    private var proactiveMessageScope: String {
        "account-\(requiredWorkspace.userID.uuidString.lowercased())"
    }

    /// 首启引导完成：原子写入路线与起始城市，并开放五座主线城市。
    @discardableResult
    func completeOnboarding(
        selected character: CharacterDTO,
        onboardingCommands: any OnboardingCommandGateway
    ) async -> Bool {
        do {
            let profile = try await onboardingCommands.completeOnboarding(
                starterRegionID: character.card.regionID
            )
            try await reconcileMainCharacters(profile: profile)
            needsOnboarding = false
            return true
        } catch {
            Log.app.error("完成首启引导失败：\(error)")
            return false
        }
    }

    func refreshProactiveMessages(requestAuthorization: Bool) async {
        guard needsOnboarding == false else { return }
        await proactiveMessages.activate(
            scope: proactiveMessageScope,
            requestAuthorization: requestAuthorization
        )
    }

    /// 自评或答题校准完成后，让角色显示、后续提示词与尚未发送的主动消息立即使用新等级。
    func applyLearnerProfile(_ profile: UserProfileDTO) async {
        do {
            if profile.hasCompletedOnboarding {
                try await reconcileMainCharacters(profile: profile)
            } else {
                try await rosterStore.configureMainCharacters(
                    unlockedRegionIDs: [],
                    difficulty: profile.difficultyLevel
                )
            }
            await proactiveMessages.learnerProfileDidChange()
            if needsOnboarding == false {
                await refreshProactiveMessages(requestAuthorization: false)
            }
        } catch {
            Log.app.warning("学习者等级已保存，角色难度刷新将在下次启动重试：\(error)")
        }
    }

    func refreshAccountPresentation(_ account: AccountWorkspace) async throws {
        let profile = try await account.economyStore.profile()
        guard workspace === account, !Task.isCancelled else { return }
        try await reconcileMainCharacters(profile: profile, account: account)
        guard workspace === account, !Task.isCancelled else { return }
        needsOnboarding = !profile.hasCompletedOnboarding
    }

    private func reconcileMainCharacters(profile: UserProfileDTO, account: AccountWorkspace? = nil) async throws {
        guard profile.hasCompletedOnboarding else { return }
        let account = account ?? requiredWorkspace
        let starterRegionID =
            profile.starterRegionID
            ?? MainlineCatalog.journeys.first(where: { $0.starterRegionID == profile.currentRegionID })?.starterRegionID
            ?? "london"
        if profile.starterRegionID == nil {
            _ = try await account.economyStore.updateProfile {
                $0.starterRegionID = starterRegionID
            }
        }
        let completed = try await account.storyProgressStore.completedStoryIDs()
        let unlocked = MainlineCatalog.unlockedMainCharacterRegionIDs(
            starterRegionID: starterRegionID,
            completedStoryIDs: completed
        )
        try await account.rosterStore.configureMainCharacters(
            unlockedRegionIDs: unlocked,
            difficulty: profile.difficultyLevel
        )
    }
}

/// All mutable journey state lives inside one account-bound object graph. The root view swaps this
/// graph only after authentication identifies the target account, so views can never render stores
/// from the previously active account while a new account is loading.
@MainActor
final class AccountWorkspace {
    let userID: UUID
    let userAvatar: UserAvatarStore
    let modelContainer: ModelContainer
    let accountCacheStore: AccountCacheStore
    let contentSyncStore: ContentSyncStore
    let voiceMediaQueueStore: VoiceMediaQueueStore
    let chatStore: ChatStore
    let npcAvatars: PublicNPCAvatarCoordinator
    let rosterStore: RosterStore
    let economyStore: EconomyStore
    let favoritesStore: FavoritesStore
    let memoryStore: MemoryStore
    let itemStore: ItemStore
    let storyProgressStore: StoryProgressStore
    let ticketStubStore: TicketStubStore
    let localUserState: LocalUserStateCoordinator
    let localTravelService: TravelService
    let localEconomyService: EconomyService
    let travelService: TravelService
    let userState: BackendUserStateCoordinator
    let contentSync: BackendContentSyncCoordinator
    let voiceMedia: VoiceMediaCoordinator
    let proactiveMessages: ProactiveMessageCoordinator
    let billing: BillingController
    let economyService: EconomyService

    init(
        userID: UUID,
        modelContainer: ModelContainer,
        backend: BackendClient,
        llm: any LLMClient
    ) async {
        self.userID = userID
        self.userAvatar = UserAvatarStore(accountID: userID)
        self.modelContainer = modelContainer

        let stores = await Task.detached(priority: .userInitiated) {
            AccountPersistence(modelContainer: modelContainer)
        }.value
        let accountCacheStore = stores.accountCacheStore
        self.accountCacheStore = accountCacheStore
        let contentSyncStore = stores.contentSyncStore
        self.contentSyncStore = contentSyncStore
        let voiceMediaQueueStore = stores.voiceMediaQueueStore
        self.voiceMediaQueueStore = voiceMediaQueueStore
        let chatStore = stores.chatStore
        self.chatStore = chatStore
        let rosterStore = stores.rosterStore
        self.rosterStore = rosterStore
        self.npcAvatars = PublicNPCAvatarCoordinator(registry: backend, roster: rosterStore)
        let economyStore = stores.economyStore
        self.economyStore = economyStore
        self.favoritesStore = stores.favoritesStore
        self.memoryStore = stores.memoryStore
        let itemStore = stores.itemStore
        self.itemStore = itemStore
        let storyProgressStore = stores.storyProgressStore
        self.storyProgressStore = storyProgressStore
        let ticketStubStore = stores.ticketStubStore
        self.ticketStubStore = ticketStubStore

        let userState = BackendUserStateCoordinator(
            backend: backend,
            accountCache: accountCacheStore,
            economyCache: economyStore,
            itemCache: itemStore,
            ticketStubCache: ticketStubStore,
            accountStorageUserID: userID
        )
        self.userState = userState
        self.contentSync = BackendContentSyncCoordinator(
            backend: backend,
            store: contentSyncStore
        )
        self.voiceMedia = VoiceMediaCoordinator(
            backend: backend,
            chatStore: chatStore,
            queueStore: voiceMediaQueueStore,
            ownerStore: UserDefaultsVoiceMediaOwnerStore(
                key: "voice.media.owner.\(userID.uuidString.lowercased()).v1"
            )
        )
        self.proactiveMessages = ProactiveMessageCoordinator(
            accountID: userID,
            rosterStore: rosterStore,
            chatStore: chatStore,
            economyStore: economyStore,
            llm: llm,
            memoryStore: memoryStore
        )
        self.billing = BillingController(
            backend: backend,
            economyStore: economyStore,
            refreshAssets: { try await userState.synchronize() }
        )
        self.travelService = TravelService(
            economyStore: economyStore,
            itemStore: itemStore,
            stubStore: ticketStubStore,
            commandGateway: userState
        )
        self.economyService = EconomyService(
            economyStore: economyStore,
            itemStore: itemStore,
            ticketPurchaseGateway: userState
        )

        // These gateways exist only for isolated DEBUG UI fixtures. Product navigation never
        // selects them because a signed-out user has no workspace.
        let localUserState = LocalUserStateCoordinator(
            economyStore: economyStore,
            itemStore: itemStore,
            storyProgressStore: storyProgressStore
        )
        self.localUserState = localUserState
        self.localTravelService = TravelService(
            economyStore: economyStore,
            itemStore: itemStore,
            stubStore: ticketStubStore,
            allowsTravel: false
        )
        self.localEconomyService = EconomyService(
            economyStore: economyStore,
            itemStore: itemStore
        )
    }
}

/// 在后台创建仓库的 ModelContext，避免后续 actor 查询仍排队到主线程。
private struct AccountPersistence: Sendable {
    let accountCacheStore: AccountCacheStore
    let contentSyncStore: ContentSyncStore
    let voiceMediaQueueStore: VoiceMediaQueueStore
    let chatStore: ChatStore
    let rosterStore: RosterStore
    let economyStore: EconomyStore
    let favoritesStore: FavoritesStore
    let memoryStore: MemoryStore
    let itemStore: ItemStore
    let storyProgressStore: StoryProgressStore
    let ticketStubStore: TicketStubStore

    init(modelContainer: ModelContainer) {
        accountCacheStore = AccountCacheStore(modelContainer: modelContainer)
        contentSyncStore = ContentSyncStore(modelContainer: modelContainer)
        voiceMediaQueueStore = VoiceMediaQueueStore(modelContainer: modelContainer)
        chatStore = ChatStore(modelContainer: modelContainer)
        rosterStore = RosterStore(modelContainer: modelContainer)
        economyStore = EconomyStore(modelContainer: modelContainer)
        favoritesStore = FavoritesStore(modelContainer: modelContainer)
        memoryStore = MemoryStore(modelContainer: modelContainer)
        itemStore = ItemStore(modelContainer: modelContainer)
        storyProgressStore = StoryProgressStore(modelContainer: modelContainer)
        ticketStubStore = TicketStubStore(modelContainer: modelContainer)
    }
}
