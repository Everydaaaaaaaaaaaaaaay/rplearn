import CoreKit
import DictKit
import DomainKit
import Foundation
import LLMKit
import PersistenceKit
import SpeechKit
import SwiftData

/// 组合根：持有全部服务实例并向下注入。后续单元逐步填充。
@MainActor
@Observable
final class AppEnvironment {
    let keychain: KeychainStore
    let llmSettings: LLMSettingsStore
    let llmRouter: LLMRouter
    let dictionary: DictDatabase
    let grammarPoints: GrammarPointStore
    let regionCatalog: RegionCatalog

    let modelContainer: ModelContainer
    let chatStore: ChatStore
    let rosterStore: RosterStore
    let economyStore: EconomyStore
    let favoritesStore: FavoritesStore
    let memoryStore: MemoryStore
    let itemStore: ItemStore

    /// nil = 尚未加载；true = 需要走首启引导。
    var needsOnboarding: Bool?

    let audioSession: AudioSessionCoordinator
    let speech: AppleTTSService
    let translator: TranslationService

    init() {
        let keychain = KeychainStore()
        self.keychain = keychain
        let settings = LLMSettingsStore(keychain: keychain)
        self.llmSettings = settings
        self.llmRouter = LLMRouter {
            try await MainActor.run { try settings.currentConfiguration() }
        }

        // 随包资源缺失/损坏属于构建错误，直接崩溃暴露。
        let dictURL = Bundle.main.url(forResource: "ecdict_lite", withExtension: "sqlite")!
        self.dictionary = try! DictDatabase(databaseURL: dictURL)
        let grammarURL = Bundle.main.url(forResource: "grammar_points", withExtension: "json")!
        self.grammarPoints = try! GrammarPointStore(url: grammarURL)
        let regionsURL = Bundle.main.url(forResource: "regions", withExtension: "json")!
        self.regionCatalog = try! RegionCatalog(url: regionsURL)

        let container = try! ModelContainerFactory.makeContainer()
        self.modelContainer = container
        self.chatStore = ChatStore(modelContainer: container)
        self.rosterStore = RosterStore(modelContainer: container)
        self.economyStore = EconomyStore(modelContainer: container)
        self.favoritesStore = FavoritesStore(modelContainer: container)
        self.memoryStore = MemoryStore(modelContainer: container)
        self.itemStore = ItemStore(modelContainer: container)

        let audioSession = AudioSessionCoordinator()
        self.audioSession = audioSession
        self.speech = AppleTTSService(audioSession: audioSession)
        self.translator = TranslationService(llm: llmRouter)

        Log.app.info("AppEnvironment initialized")
        bootstrap()
    }

    /// 首启引导数据：确保用户档案存在并导入 3 主角色（幂等），并判定是否需要首启引导。
    private func bootstrap() {
        Task {
            do {
                let profile = try await economyStore.profile()
                let seedsURL = Bundle.main.url(forResource: "main_characters", withExtension: "json")!
                let cards = try SeedData.mainCharacterCards(url: seedsURL)
                try await rosterStore.importMainCharactersIfNeeded(cards: cards)
                needsOnboarding = !profile.hasCompletedOnboarding
            } catch {
                Log.app.error("bootstrap 失败：\(error)")
                needsOnboarding = false
            }
        }
    }

    /// 首启引导完成：写当前地区/解锁地区/完成标记。
    func completeOnboarding(selected character: CharacterDTO) async {
        do {
            _ = try await economyStore.updateProfile { profile in
                profile.currentRegionID = character.card.regionID
                if !profile.unlockedRegionIDs.contains(character.card.regionID) {
                    profile.unlockedRegionIDs.append(character.card.regionID)
                }
                profile.hasCompletedOnboarding = true
            }
            needsOnboarding = false
        } catch {
            Log.app.error("完成首启引导失败：\(error)")
        }
    }
}
