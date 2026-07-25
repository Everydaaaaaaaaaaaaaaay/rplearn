import Foundation
import PersistenceKit

/// 地区旅行：首次前往用机票解锁，已解锁地区可直接往返；每次旅行都会生成票根。
public struct TravelService: Sendable {
    public enum TravelError: Error, Equatable {
        case ticketRequired
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

    /// 机票是否可用于解锁某地区（纯函数）。
    public static func isTicketUsable(_ ticket: ItemDTO, for region: Region) -> Bool {
        guard !ticket.isConsumed else { return false }
        switch ticket.type {
        case .ticketUniversal:
            return true
        case .ticketCountry:
            return ticket.countryCode?.caseInsensitiveCompare(region.countryCode) == .orderedSame
        }
    }

    /// 只有从未到访、尚未解锁的地区需要机票。
    public static func requiresTicket(to region: Region, profile: UserProfileDTO) -> Bool {
        profile.currentRegionID != region.id
            && !profile.unlockedRegionIDs.contains(region.id)
    }

    public func usableTickets(for region: Region) async throws -> [ItemDTO] {
        let profile = try await economyStore.profile()
        guard Self.requiresTicket(to: region, profile: profile) else { return [] }
        return try await itemStore.unconsumedTickets().filter { Self.isTicketUsable($0, for: region) }
    }

    /// 前往地区。首次解锁必须提供可用机票，已解锁地区无需机票。
    @discardableResult
    public func travel(to region: Region, using ticket: ItemDTO? = nil) async throws -> TicketStubDTO {
        let profile = try await economyStore.profile()
        guard profile.currentRegionID != region.id else {
            throw TravelError.alreadyThere
        }

        if Self.requiresTicket(to: region, profile: profile) {
            guard let ticket else {
                throw TravelError.ticketRequired
            }
            guard Self.isTicketUsable(ticket, for: region) else {
                throw TravelError.ticketNotUsable
            }
            try await itemStore.consume(itemID: ticket.id)
        }

        let originRegionID = profile.currentRegionID
        _ = try await economyStore.updateProfile { p in
            p.currentRegionID = region.id
            if !p.unlockedRegionIDs.contains(originRegionID) {
                p.unlockedRegionIDs.append(originRegionID)
            }
            if !p.unlockedRegionIDs.contains(region.id) {
                p.unlockedRegionIDs.append(region.id)
            }
        }
        return try await stubStore.addStub(fromRegionID: originRegionID, toRegionID: region.id)
    }
}
