import BackendKit
import BillingKit
import CoreKit
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
    /// Temporary product policy while the app is in active development.
    private static let grantsFullGuestAccess = true

    let keychain: KeychainStore
    let backendClient: BackendClient
    let authSession: AuthSession
    let billing: BillingController
    let llmRouter: LLMRouter
    let dictionary: DictDatabase
    let grammarPoints: GrammarPointStore
    let regionCatalog: RegionCatalog

    let modelContainer: ModelContainer
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
    let localUserState: LocalUserStateCoordinator
    let localTravelService: TravelService
    let localEconomyService: EconomyService
    let travelService: TravelService
    let userState: BackendUserStateCoordinator
    let contentSync: BackendContentSyncCoordinator
    let voiceMedia: VoiceMediaCoordinator
    let proactiveMessages: ProactiveMessageCoordinator
    private var proactiveMessageScope = "guest"

    /// nil = 尚未加载；true = 需要走首启引导。
    var needsOnboarding: Bool?

    let audioSession: AudioSessionCoordinator
    let speech: AdaptiveSpeechService
    let translator: TranslationService
    let economyService: EconomyService

    init() {
        // 离线模式后台预热 Supertonic-3；实时识别统一使用 Apple 系统能力。
        let audioSession = AudioSessionCoordinator()
        self.audioSession = audioSession
        let speech = AdaptiveSpeechService(audioSession: audioSession)
        self.speech = speech
        Task.detached(priority: .userInitiated) {
            await speech.prepareForLaunch()
        }

        let keychain = KeychainStore()
        self.keychain = keychain
        LLMSettingsStore.purgeLegacyClientConfiguration(keychain: keychain)
        let backendClient = BackendClient(
            configuration: .live,
            credentialStore: KeychainAuthCredentialStore(keychain: keychain)
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
            client: BackendLLMProvider(backend: backendClient, guestID: deviceID)
        )

        // 随包资源缺失/损坏属于构建错误，直接崩溃暴露。
        let dictURL = Bundle.main.url(forResource: "learner_dictionary", withExtension: "sqlite")!
        self.dictionary = try! DictDatabase(databaseURL: dictURL)
        let grammarURL = Bundle.main.url(forResource: "grammar_points", withExtension: "json")!
        self.grammarPoints = try! GrammarPointStore(url: grammarURL)
        let regionsURL = Bundle.main.url(forResource: "regions", withExtension: "json")!
        self.regionCatalog = try! RegionCatalog(url: regionsURL)

        let container = try! ModelContainerFactory.makeContainer()
        self.modelContainer = container
        let accountCacheStore = AccountCacheStore(modelContainer: container)
        self.accountCacheStore = accountCacheStore
        let contentSyncStore = ContentSyncStore(modelContainer: container)
        self.contentSyncStore = contentSyncStore
        let chatStore = ChatStore(modelContainer: container)
        self.chatStore = chatStore
        let voiceMediaQueueStore = VoiceMediaQueueStore(modelContainer: container)
        self.voiceMediaQueueStore = voiceMediaQueueStore
        self.rosterStore = RosterStore(modelContainer: container)
        self.economyStore = EconomyStore(modelContainer: container)
        self.favoritesStore = FavoritesStore(modelContainer: container)
        self.memoryStore = MemoryStore(modelContainer: container)
        self.itemStore = ItemStore(modelContainer: container)
        self.storyProgressStore = StoryProgressStore(modelContainer: container)
        let ticketStubStore = TicketStubStore(modelContainer: container)
        self.ticketStubStore = ticketStubStore
        let localUserState = LocalUserStateCoordinator(
            economyStore: economyStore,
            itemStore: itemStore,
            storyProgressStore: storyProgressStore
        )
        self.localUserState = localUserState
        let userState = BackendUserStateCoordinator(
            backend: backendClient,
            accountCache: accountCacheStore,
            economyCache: economyStore,
            itemCache: itemStore,
            ticketStubCache: ticketStubStore
        )
        self.userState = userState
        self.contentSync = BackendContentSyncCoordinator(
            backend: backendClient,
            store: contentSyncStore
        )
        self.voiceMedia = VoiceMediaCoordinator(
            backend: backendClient,
            chatStore: chatStore,
            queueStore: voiceMediaQueueStore
        )
        self.proactiveMessages = ProactiveMessageCoordinator(
            rosterStore: rosterStore,
            chatStore: chatStore,
            economyStore: economyStore,
            llm: llmRouter
        )
        self.billing = BillingController(
            backend: backendClient,
            economyStore: economyStore
        )
        self.travelService = TravelService(
            economyStore: economyStore,
            itemStore: itemStore,
            stubStore: ticketStubStore,
            commandGateway: userState
        )
        self.localTravelService = TravelService(
            economyStore: economyStore,
            itemStore: itemStore,
            stubStore: ticketStubStore
        )

        self.translator = TranslationService(llm: llmRouter)
        self.economyService = EconomyService(
            economyStore: economyStore,
            itemStore: itemStore,
            ticketPurchaseGateway: userState
        )
        self.localEconomyService = EconomyService(
            economyStore: economyStore,
            itemStore: itemStore
        )

        Log.app.info("AppEnvironment initialized")
        Task { await authSession.bootstrap() }
    }

    /// 首启引导数据：确保用户档案存在并导入 3 主角色（幂等），并判定是否需要首启引导。
    func activateUser(_ identity: AuthIdentity) async throws -> UserStateActivation {
        needsOnboarding = nil
        let guestProfile =
            await userState.shouldCaptureGuestProfileForImport()
            ? try? await economyStore.profile()
            : nil
        let activation = try await userState.activate(userID: identity.userID)
        if let guestProfile {
            _ = try await userState.importGuestLearnerProfileIfNeeded(guestProfile)
        }
        await billing.activate(identity: identity)
        let profile = try await economyStore.profile()
        let seedsURL = Bundle.main.url(forResource: "main_characters", withExtension: "json")!
        let cards = try SeedData.mainCharacterCards(url: seedsURL)
        try await rosterStore.importMainCharactersIfNeeded(cards: cards)
        try await contentSync.activate(userID: identity.userID)
        try await reconcileMainCharacters(profile: profile)
        await voiceMedia.activate(userID: identity.userID)
        proactiveMessageScope = "account-\(identity.userID.uuidString.lowercased())"
        #if DEBUG
        if ProcessInfo.processInfo.environment["UI_TEST_SKIP_ONBOARDING"] == "1" {
            needsOnboarding = false
        } else {
            needsOnboarding = !profile.hasCompletedOnboarding
        }
        #else
        needsOnboarding = !profile.hasCompletedOnboarding
        #endif
        return activation
    }

    /// 启用不依赖账号的本地游客空间。若刚退出账号，会先隔离账号缓存。
    func activateGuest() async throws {
        needsOnboarding = nil
        billing.deactivate()
        await contentSync.deactivate()
        await voiceMedia.deactivate()
        try await userState.activateGuest()
        if Self.grantsFullGuestAccess {
            try await economyStore.applyAuthoritativeEntitlement(
                tier: .pro,
                friendSlotLimit: 30
            )
        }

        let profile = try await economyStore.profile()
        let seedsURL = Bundle.main.url(forResource: "main_characters", withExtension: "json")!
        let cards = try SeedData.mainCharacterCards(url: seedsURL)
        try await rosterStore.importMainCharactersIfNeeded(cards: cards)
        try await reconcileMainCharacters(profile: profile)
        proactiveMessageScope = "guest"
        #if DEBUG
        if ProcessInfo.processInfo.environment["UI_TEST_SKIP_ONBOARDING"] == "1" {
            needsOnboarding = false
        } else {
            needsOnboarding = !profile.hasCompletedOnboarding
        }
        #else
        needsOnboarding = !profile.hasCompletedOnboarding
        #endif
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

    private func reconcileMainCharacters(profile: UserProfileDTO) async throws {
        guard profile.hasCompletedOnboarding else { return }
        let starterRegionID =
            profile.starterRegionID
            ?? MainlineCatalog.journeys.first(where: { $0.starterRegionID == profile.currentRegionID })?.starterRegionID
            ?? "london"
        if profile.starterRegionID == nil {
            _ = try await economyStore.updateProfile {
                $0.starterRegionID = starterRegionID
            }
        }
        let completed = try await storyProgressStore.completedStoryIDs()
        let unlocked = MainlineCatalog.unlockedMainCharacterRegionIDs(
            starterRegionID: starterRegionID,
            completedStoryIDs: completed
        )
        try await rosterStore.configureMainCharacters(
            unlockedRegionIDs: unlocked,
            difficulty: profile.difficultyLevel
        )
    }
}
