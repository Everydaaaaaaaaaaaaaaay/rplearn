import CoreKit
import DictKit
import DomainKit
import LLMKit
import MediaKit
import PersistenceKit
import SpeechKit

/// ChatFeature 所需依赖，由组合根注入。
public struct ChatDependencies: Sendable {
    public let chatStore: ChatStore
    public let rosterStore: RosterStore
    public let favorites: FavoritesStore
    public let llm: any LLMClient
    public let dictionary: DictDatabase
    public let grammarPoints: GrammarPointStore
    public let speech: any SpeechService
    public let translator: TranslationService
    public let audioSession: AudioSessionCoordinator
    public let memoryStore: MemoryStore
    public let itemStore: ItemStore
    public let economyStore: EconomyStore
    public let progression: any ProgressionRewardGateway
    public let voiceMedia: VoiceMediaCoordinator

    public init(
        chatStore: ChatStore,
        rosterStore: RosterStore,
        favorites: FavoritesStore,
        llm: any LLMClient,
        dictionary: DictDatabase,
        grammarPoints: GrammarPointStore,
        speech: any SpeechService,
        translator: TranslationService,
        audioSession: AudioSessionCoordinator,
        memoryStore: MemoryStore,
        itemStore: ItemStore,
        economyStore: EconomyStore,
        progression: any ProgressionRewardGateway,
        voiceMedia: VoiceMediaCoordinator
    ) {
        self.chatStore = chatStore
        self.rosterStore = rosterStore
        self.favorites = favorites
        self.llm = llm
        self.dictionary = dictionary
        self.grammarPoints = grammarPoints
        self.speech = speech
        self.translator = translator
        self.audioSession = audioSession
        self.memoryStore = memoryStore
        self.itemStore = itemStore
        self.economyStore = economyStore
        self.progression = progression
        self.voiceMedia = voiceMedia
    }
}
