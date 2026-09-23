import Foundation
import Observation
import BackendKit
import CoreKit
import DictKit
import DomainKit
import LLMKit
import MediaKit
import PersistenceKit
import SpeechKit
import SwiftUI

/// One disposable tutorial owns the allowance, including reopened chats and calls.
@MainActor @Observable
public final class ChatTutorialSession {
    public private(set) var sentMessages = 0
    public let limit: Int
    public init(limit: Int = 5) { self.limit = max(0, limit) }
    public func reserveMessage() -> Bool {
        guard sentMessages < limit else { return false }
        sentMessages += 1
        return true
    }
    public func releaseFailedMessage() { sentMessages = max(0, sentMessages - 1) }
}

public struct ChatTutorialConfiguration: Sendable {
    public let session: ChatTutorialSession
    public let focus: String?
    public let onEvent: @MainActor @Sendable (String) -> Void
    public init(session: ChatTutorialSession, focus: String? = nil,
                onEvent: @escaping @MainActor @Sendable (String) -> Void) {
        self.session = session; self.focus = focus; self.onEvent = onEvent
    }
}

/// ChatFeature 所需依赖，由组合根注入。
public struct ChatDependencies: Sendable {
    /// Per-view-model owner token; excludes distant scheduled replies until they become active.
    public var learningReplyActivity: (@MainActor @Sendable (UUID, Bool) -> Void)? = nil
    public var learningEnabled: (@MainActor @Sendable () -> Bool)? = nil
    public var learningRecorder: (@MainActor @Sendable (UUID, UUID, ConversationLearningObservation) -> Void)? = nil

    /// Optional prototype telemetry; nil in normal app assembly.
    public var learningObserver: (@MainActor @Sendable (ConversationLearningObservation) -> Void)? = nil

    #if DEBUG
    /// Set only by the app's isolated in-memory marketing workspace.
    public var marketingMotionCapture = false
    #endif
    public var learningAccessory: (@MainActor @Sendable (CharacterDTO, Bool, Bool) -> AnyView)?
    public var learningInstruction: (@MainActor @Sendable (UUID) -> String?)?
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
    public let translator: TranslationService

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
        translator: TranslationService,
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
        self.translator = translator

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
