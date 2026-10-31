import DictKit
import PersistenceKit
import SpeechKit

public struct AppointmentReadingServices: Sendable {
    public let dictionary: DictDatabase
    public let grammar: GrammarPointStore
    public let favorites: FavoritesStore
    public let speech: any SpeechService

    public init(dictionary: DictDatabase, grammar: GrammarPointStore, favorites: FavoritesStore, speech: any SpeechService) {
        self.dictionary = dictionary; self.grammar = grammar; self.favorites = favorites; self.speech = speech
    }
}
