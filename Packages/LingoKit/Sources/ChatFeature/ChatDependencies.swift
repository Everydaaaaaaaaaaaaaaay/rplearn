import Foundation
import BackendKit
import CoreKit
import DictKit
import DomainKit
import LLMKit
import MediaKit
import PersistenceKit
import SpeechKit

public struct ChatTutorialConfiguration: Sendable {
    public let onEvent: @MainActor @Sendable (String) -> Void
    public init(onEvent: @escaping @MainActor @Sendable (String) -> Void) { self.onEvent = onEvent }
}

/// ChatFeature 所需依赖，由组合根注入。
public struct ChatDependencies: Sendable {
    public let tutorial: ChatTutorialConfiguration?
    public let accessClient: BackendClient?
    public let onShowAccess: @MainActor @Sendable () -> Void
    public let chatStore: ChatStore
    public let rosterStore: RosterStore
    public let favorites: FavoritesStore
    public let llm: any LLMClient
    public let dictionary: DictDatabase
    public let grammarPoints: GrammarPointStore
    public let speech: any SpeechService
    public let exampleTranslationActions: DictExampleTranslationActions
    public let audioSession: AudioSessionCoordinator
    public let memoryStore: MemoryStore
    public let itemStore: ItemStore
    public let economyStore: EconomyStore
    public let progression: any ProgressionRewardGateway
    public let voiceMedia: VoiceMediaCoordinator
    public let npcRegistry: (any PublicNPCRegistry)?
    public let regionName: @Sendable (String) -> String
    public let now: @Sendable () -> Date
    public let replyDelayScale: Double

    public init(
        tutorial: ChatTutorialConfiguration? = nil,
        accessClient: BackendClient? = nil,
        onShowAccess: @escaping @MainActor @Sendable () -> Void = {},
        chatStore: ChatStore,
        rosterStore: RosterStore,
        favorites: FavoritesStore,
        llm: any LLMClient,
        dictionary: DictDatabase,
        grammarPoints: GrammarPointStore,
        speech: any SpeechService,
        exampleTranslationActions: DictExampleTranslationActions,
        audioSession: AudioSessionCoordinator,
        memoryStore: MemoryStore,
        itemStore: ItemStore,
        economyStore: EconomyStore,
        progression: any ProgressionRewardGateway,
        voiceMedia: VoiceMediaCoordinator,
        npcRegistry: (any PublicNPCRegistry)? = nil,
        regionName: @escaping @Sendable (String) -> String = {
            $0.replacingOccurrences(of: "_", with: " ").capitalized
        },
        now: @escaping @Sendable () -> Date = { .now },
        replyDelayScale: Double = 1
    ) {
        self.tutorial = tutorial
        self.accessClient = accessClient
        self.onShowAccess = onShowAccess
        self.chatStore = chatStore
        self.rosterStore = rosterStore
        self.favorites = favorites
        self.llm = llm
        self.dictionary = dictionary
        self.grammarPoints = grammarPoints
        self.speech = speech
        self.exampleTranslationActions = exampleTranslationActions
        self.audioSession = audioSession
        self.memoryStore = memoryStore
        self.itemStore = itemStore
        self.economyStore = economyStore
        self.progression = progression
        self.voiceMedia = voiceMedia
        self.npcRegistry = npcRegistry
        self.regionName = regionName
        self.now = now
        self.replyDelayScale = max(0, replyDelayScale)
    }
}
