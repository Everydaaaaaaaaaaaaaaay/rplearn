import CoreKit
import DictKit
import DomainKit
import PersistenceKit
import SpeechKit

/// StoryFeature 依赖。
public struct StoryDependencies: Sendable {
    public let storyProgress: StoryProgressStore
    public let progression: any ProgressionRewardGateway
    public let rosterStore: RosterStore
    public let favorites: FavoritesStore
    public let dictionary: DictDatabase
    public let grammarPoints: GrammarPointStore
    public let speech: any SpeechService
    public let audioSession: AudioSessionCoordinator

    public init(
        storyProgress: StoryProgressStore,
        progression: any ProgressionRewardGateway,
        rosterStore: RosterStore,
        favorites: FavoritesStore,
        dictionary: DictDatabase,
        grammarPoints: GrammarPointStore,
        speech: any SpeechService,
        audioSession: AudioSessionCoordinator) {
        self.storyProgress = storyProgress
        self.progression = progression
        self.rosterStore = rosterStore
        self.favorites = favorites
        self.dictionary = dictionary
        self.grammarPoints = grammarPoints
        self.speech = speech
        self.audioSession = audioSession
    }
}

