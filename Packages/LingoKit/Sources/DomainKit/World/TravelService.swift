import Foundation
import PersistenceKit

public struct TravelResult: Sendable, Equatable {
    public let fromRegionID: String
    public let toRegionID: String
    public let unlockedNow: Bool
    public let ticketStub: TicketStubDTO?

    public init(
        fromRegionID: String,
        toRegionID: String,
        unlockedNow: Bool,
        ticketStub: TicketStubDTO?
    ) {
        self.fromRegionID = fromRegionID
        self.toRegionID = toRegionID
        self.unlockedNow = unlockedNow
        self.ticketStub = ticketStub
    }
}

/// 地区旅行：首次前往用机票解锁并收藏唯一票根，已解锁地区可直接往返。
public struct TravelService: Sendable {
    public enum TravelError: Error, Equatable {
        case loginRequired
        case ticketRequired
        case ticketNotUsable
        case alreadyThere
    }

    public let allowsTravel: Bool
    private let economyStore: EconomyStore
    private let itemStore: ItemStore
    private let stubStore: TicketStubStore
    private let commandGateway: (any TravelCommandGateway)?

    public init(
        economyStore: EconomyStore,
        itemStore: ItemStore,
        stubStore: TicketStubStore,
        commandGateway: (any TravelCommandGateway)? = nil,
        allowsTravel: Bool = true
    ) {
        self.allowsTravel = allowsTravel
        self.economyStore = economyStore
        self.itemStore = itemStore
        self.stubStore = stubStore
        self.commandGateway = commandGateway
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
        guard region.role != .mainline else { return false }
        return profile.currentRegionID != region.id
            && !profile.unlockedRegionIDs.contains(region.id)
    }

    public func usableTickets(for region: Region) async throws -> [ItemDTO] {
        let profile = try await economyStore.profile()
        guard Self.requiresTicket(to: region, profile: profile) else { return [] }
        return try await itemStore.unconsumedTickets().filter { Self.isTicketUsable($0, for: region) }
    }

    /// 前往地区。首次解锁必须提供可用机票，已解锁地区无需机票。
    @discardableResult
    public func travel(to region: Region, using ticket: ItemDTO? = nil) async throws -> TravelResult {
        guard allowsTravel else { throw TravelError.loginRequired }
        if let commandGateway {
            let result = try await commandGateway.travel(
                targetRegionID: region.id,
                ticketID: ticket?.id
            )
            let stub: TicketStubDTO? = if result.unlockedNow {
                try await stubStore.cacheFirstServerArrival(
                    id: result.travelID,
                    fromRegionID: result.fromRegionID,
                    toRegionID: result.toRegionID,
                    usedAt: result.traveledAt
                )
            } else {
                nil
            }
            return TravelResult(
                fromRegionID: result.fromRegionID,
                toRegionID: result.toRegionID,
                unlockedNow: result.unlockedNow,
                ticketStub: stub
            )
        }
        let profile = try await economyStore.profile()
        guard profile.currentRegionID != region.id else {
            throw TravelError.alreadyThere
        }

        let unlockedNow = Self.requiresTicket(to: region, profile: profile)
        if unlockedNow {
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
        let stub: TicketStubDTO? = if unlockedNow {
            try await stubStore.addFirstArrival(
                fromRegionID: originRegionID,
                toRegionID: region.id
            )
        } else {
            nil
        }
        return TravelResult(
            fromRegionID: originRegionID,
            toRegionID: region.id,
            unlockedNow: unlockedNow,
            ticketStub: stub
        )
    }
}
