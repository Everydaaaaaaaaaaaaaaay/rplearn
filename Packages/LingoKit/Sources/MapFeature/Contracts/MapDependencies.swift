import DomainKit
import PersistenceKit

public struct MapDependencies: Sendable {
    public let economyStore: EconomyStore
    public let itemStore: ItemStore
    public let stubStore: TicketStubStore
    public let travelService: TravelService
    public let economyService: EconomyService
    public let regionCatalog: RegionCatalog

    public init(
        economyStore: EconomyStore,
        itemStore: ItemStore,
        stubStore: TicketStubStore,
        travelService: TravelService,
        economyService: EconomyService,
        regionCatalog: RegionCatalog
    ) {
        self.economyStore = economyStore
        self.itemStore = itemStore
        self.stubStore = stubStore
        self.travelService = travelService
        self.economyService = economyService
        self.regionCatalog = regionCatalog
    }
}

public enum MapDestination: Hashable {
    case ticketStubs
}
