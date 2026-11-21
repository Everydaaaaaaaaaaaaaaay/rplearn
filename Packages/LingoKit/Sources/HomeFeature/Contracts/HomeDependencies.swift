import Foundation
import BackendKit
import DictKit
import DomainKit
import PersistenceKit
import SpeechKit

public struct HomeDependencies: Sendable {
    public let presentationCache: JourneyPresentationCache?
    public let access: JourneyAccess
    public let economyStore: EconomyStore
    public let itemStore: ItemStore
    public let ticketStubStore: TicketStubStore
    public let storyProgress: StoryProgressStore
    public let regionCatalog: RegionCatalog
    public let rosterStore: RosterStore
    public let favorites: FavoritesStore
    public let dictionary: DictDatabase
    public let grammarPoints: GrammarPointStore
    public let speech: any SpeechService

    public let mainline: (any MainlineServing)?
    public let npcRegistry: (any PublicNPCRegistry)?
    public let outingGateway: (any OutingGateway)?
    public let activityReleaseID: String?
    public let appointments: (any AppointmentServing)?

    public init(
        access: JourneyAccess = JourneyAccess(),
        economyStore: EconomyStore,
        itemStore: ItemStore,
        ticketStubStore: TicketStubStore,
        storyProgress: StoryProgressStore,
        regionCatalog: RegionCatalog,
        rosterStore: RosterStore,
        favorites: FavoritesStore,
        dictionary: DictDatabase,
        grammarPoints: GrammarPointStore,
        speech: any SpeechService,
        mainline: (any MainlineServing)? = nil,
        npcRegistry: (any PublicNPCRegistry)? = nil,
        outingGateway: (any OutingGateway)? = nil,
        activityReleaseID: String? = nil,
        appointments: (any AppointmentServing)? = nil,
        presentationCache: JourneyPresentationCache? = nil
    ) {
        self.presentationCache = presentationCache
        self.access = access
        self.economyStore = economyStore
        self.itemStore = itemStore
        self.ticketStubStore = ticketStubStore
        self.storyProgress = storyProgress
        self.regionCatalog = regionCatalog
        self.rosterStore = rosterStore
        self.favorites = favorites
        self.dictionary = dictionary
        self.grammarPoints = grammarPoints
        self.speech = speech

        self.mainline = mainline
        self.npcRegistry = npcRegistry
        self.outingGateway = outingGateway
        self.activityReleaseID = activityReleaseID
        self.appointments = appointments
    }
}

public enum HomeDestination: Hashable, Sendable {
    case appointments
    case map
    case stories
    case mainline
    case cityStories
    case activities
}
