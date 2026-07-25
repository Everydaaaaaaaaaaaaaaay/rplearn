import BackendKit
import BillingKit
import CoreKit
import DictKit
import DomainKit
import Foundation
import LLMKit
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
    let billing: BillingController
    let llmRouter: LLMRouter
    let dictionary: DictDatabase
    let grammarPoints: GrammarPointStore
    let regionCatalog: RegionCatalog

    let modelContainer: ModelContainer
    let accountCacheStore: AccountCacheStore
    let contentSyncStore: ContentSyncStore
    let chatStore: ChatStore
    let rosterStore: RosterStore
    let economyStore: EconomyStore
    let favoritesStore: FavoritesStore
    let memoryStore: MemoryStore
    let itemStore: ItemStore
    let storyProgressStore: StoryProgressStore
    let ticketStubStore: TicketStubStore
    let travelService: TravelService
    let userState: BackendUserStateCoordinator
    let contentSync: BackendContentSyncCoordinator

    /// nil = 尚未加载；true = 需要走首启引导。
    var needsOnboarding: Bool?

    let audioSession: AudioSessionCoordinator
    let speech: AppleTTSService
    let translator: TranslationService
    let economyService: EconomyService

    init() {
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
            client: BackendLLMProvider(backend: backendClient)
        )

        // 随包资源缺失/损坏属于构建错误，直接崩溃暴露。
        let dictURL = Bundle.main.url(forResource: "ecdict_lite", withExtension: "sqlite")!
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
        self.chatStore = ChatStore(modelContainer: container)
        self.rosterStore = RosterStore(modelContainer: container)
        self.economyStore = EconomyStore(modelContainer: container)
        self.favoritesStore = FavoritesStore(modelContainer: container)
        self.memoryStore = MemoryStore(modelContainer: container)
        self.itemStore = ItemStore(modelContainer: container)
        self.storyProgressStore = StoryProgressStore(modelContainer: container)
        let ticketStubStore = TicketStubStore(modelContainer: container)
        self.ticketStubStore = ticketStubStore
        let userState = BackendUserStateCoordinator(
            backend: backendClient,
            accountCache: accountCacheStore,
            economyCache: economyStore,
            itemCache: itemStore
        )
        self.userState = userState
        self.contentSync = BackendContentSyncCoordinator(
            backend: backendClient,
            store: contentSyncStore
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

        let audioSession = AudioSessionCoordinator()
        self.audioSession = audioSession
        self.speech = AppleTTSService(audioSession: audioSession)
        self.translator = TranslationService(llm: llmRouter)
        self.economyService = EconomyService(
            economyStore: economyStore,
            itemStore: itemStore,
            ticketPurchaseGateway: userState
        )

        Log.app.info("AppEnvironment initialized")
        Task { await authSession.bootstrap() }
    }

    /// 首启引导数据：确保用户档案存在并导入 3 主角色（幂等），并判定是否需要首启引导。
    func activateUser(_ identity: AuthIdentity) async throws -> UserStateActivation {
        needsOnboarding = nil
        let activation = try await userState.activate(userID: identity.userID)
        await billing.activate(identity: identity)
        let profile = try await economyStore.profile()
        let seedsURL = Bundle.main.url(forResource: "main_characters", withExtension: "json")!
        let cards = try SeedData.mainCharacterCards(url: seedsURL)
        try await rosterStore.importMainCharactersIfNeeded(cards: cards)
        try await contentSync.activate(userID: identity.userID)
        needsOnboarding = !profile.hasCompletedOnboarding
        return activation
    }

    /// 首启引导完成：写当前地区/解锁地区/完成标记。
    func completeOnboarding(selected character: CharacterDTO) async {
        do {
            _ = try await userState.updateProfile { profile in
                profile.hasCompletedOnboarding = true
            }
            needsOnboarding = false
        } catch {
            Log.app.error("完成首启引导失败：\(error)")
        }
    }
}
