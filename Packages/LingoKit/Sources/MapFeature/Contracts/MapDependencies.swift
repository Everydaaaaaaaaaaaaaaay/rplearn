import DomainKit
import PersistenceKit

public struct MapDependencies: Sendable {
    public let presentationCache: JourneyPresentationCache?
    public let mapCache: WorldMapCache?
    public let access: JourneyAccess
    public let economyStore: EconomyStore
    public let itemStore: ItemStore
    public let stubStore: TicketStubStore
    public let travelService: TravelService
    public let economyService: EconomyService
    public let regionCatalog: RegionCatalog
    public let storyProgress: StoryProgressStore

    public init(
        access: JourneyAccess = JourneyAccess(),
        economyStore: EconomyStore,
        itemStore: ItemStore,
        stubStore: TicketStubStore,
        travelService: TravelService,
        economyService: EconomyService,
        regionCatalog: RegionCatalog,
        storyProgress: StoryProgressStore,
        presentationCache: JourneyPresentationCache? = nil,
        mapCache: WorldMapCache? = nil
    ) {
        self.access = access
        self.presentationCache = presentationCache
        self.mapCache = mapCache
        self.economyStore = economyStore
        self.itemStore = itemStore
        self.stubStore = stubStore
        self.travelService = travelService
        self.economyService = economyService
        self.regionCatalog = regionCatalog
        self.storyProgress = storyProgress
    }
}

public enum MapDestination: Hashable {
    case ticketStubs
}
