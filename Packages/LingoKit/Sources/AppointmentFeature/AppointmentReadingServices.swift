import DictKit
import Foundation
import PersistenceKit
import SpeechKit

public struct AppointmentReadingServices: Sendable {
    public let dictionary: DictDatabase
    public let grammar: GrammarPointStore
    public let favorites: FavoritesStore
    public let speech: any SpeechService
    public let characterNarration: @Sendable (UUID, String) async -> SpeechRequest?

    public init(dictionary: DictDatabase, grammar: GrammarPointStore, favorites: FavoritesStore, speech: any SpeechService,
                characterNarration: @escaping @Sendable (UUID, String) async -> SpeechRequest? = { _, _ in nil }) {
        self.dictionary = dictionary; self.grammar = grammar; self.favorites = favorites; self.speech = speech
        self.characterNarration = characterNarration
    }
}
