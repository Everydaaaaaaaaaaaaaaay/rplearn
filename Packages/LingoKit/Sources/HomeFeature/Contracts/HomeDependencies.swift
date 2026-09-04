import BackendKit
import DictKit
import DomainKit
import LLMKit
import PersistenceKit
import SpeechKit

public struct HomeDependencies: Sendable {
    public let economyStore: EconomyStore
    public let storyProgress: StoryProgressStore
    public let travelService: TravelService
    public let regionCatalog: RegionCatalog
    public let rosterStore: RosterStore
    public let chatStore: ChatStore
    public let favorites: FavoritesStore
    public let dictionary: DictDatabase
    public let grammarPoints: GrammarPointStore
    public let speech: any SpeechService
    public let llm: any LLMClient
    public let exampleTranslationActions: DictExampleTranslationActions
    public let npcRegistry: (any PublicNPCRegistry)?

    public init(
        economyStore: EconomyStore,
        storyProgress: StoryProgressStore,
        travelService: TravelService,
        regionCatalog: RegionCatalog,
        rosterStore: RosterStore,
        chatStore: ChatStore,
        favorites: FavoritesStore,
        dictionary: DictDatabase,
        grammarPoints: GrammarPointStore,
        speech: any SpeechService,
        llm: any LLMClient,
        exampleTranslationActions: DictExampleTranslationActions,
        npcRegistry: (any PublicNPCRegistry)? = nil
    ) {
        self.economyStore = economyStore
        self.storyProgress = storyProgress
        self.travelService = travelService
        self.regionCatalog = regionCatalog
        self.rosterStore = rosterStore
        self.chatStore = chatStore
        self.favorites = favorites
        self.dictionary = dictionary
        self.grammarPoints = grammarPoints
        self.speech = speech
        self.llm = llm
        self.exampleTranslationActions = exampleTranslationActions
        self.npcRegistry = npcRegistry
    }
}

public enum HomeDestination: Hashable, Sendable {
    case map
    case stories
    case mainline
    case cityStories
    case activities
}
