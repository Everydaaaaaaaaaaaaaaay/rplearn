import CoreKit
import DictKit
import DomainKit
import LLMKit
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

    public init(
        chatStore: ChatStore,
        rosterStore: RosterStore,
        favorites: FavoritesStore,
        llm: any LLMClient,
        dictionary: DictDatabase,
        grammarPoints: GrammarPointStore,
        speech: any SpeechService,
        translator: TranslationService,
        audioSession: AudioSessionCoordinator
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
    }
}
