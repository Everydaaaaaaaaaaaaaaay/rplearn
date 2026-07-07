import Foundation
import PersistenceKit

/// 地区旅行：机票校验 → 消耗 → 更新当前地区/解锁 → 生成票根（plan.md §3.9）。
public struct TravelService: Sendable {
    public enum TravelError: Error, Equatable {
        case ticketNotUsable
        case alreadyThere
    }

    private let economyStore: EconomyStore
    private let itemStore: ItemStore
    private let stubStore: TicketStubStore

    public init(economyStore: EconomyStore, itemStore: ItemStore, stubStore: TicketStubStore) {
        self.economyStore = economyStore
        self.itemStore = itemStore
        self.stubStore = stubStore
    }

    /// 机票是否可用于前往某地区（纯函数）。
    public static func isTicketUsable(_ ticket: ItemDTO, for region: Region) -> Bool {
        guard !ticket.isConsumed else { return false }
        switch ticket.type {
        case .ticketUniversal:
            return true
        case .ticketCountry:
            return ticket.countryCode?.caseInsensitiveCompare(region.countryCode) == .orderedSame
        }
    }

    public func usableTickets(for region: Region) async throws -> [ItemDTO] {
        try await itemStore.unconsumedTickets().filter { Self.isTicketUsable($0, for: region) }
    }

    /// 用一张机票前往地区。返回生成的票根。
    @discardableResult
    public func travel(to region: Region, using ticket: ItemDTO) async throws -> TicketStubDTO {
        guard Self.isTicketUsable(ticket, for: region) else {
            throw TravelError.ticketNotUsable
        }
        let profile = try await economyStore.profile()
        guard profile.currentRegionID != region.id else {
            throw TravelError.alreadyThere
        }
        try await itemStore.consume(itemID: ticket.id)
        _ = try await economyStore.updateProfile { p in
            p.currentRegionID = region.id
            if !p.unlockedRegionIDs.contains(region.id) {
                p.unlockedRegionIDs.append(region.id)
            }
        }
        try await economyStore.unlockRegion(region.id)
        return try await stubStore.addStub(fromRegionID: profile.currentRegionID, toRegionID: region.id)
    }
}
