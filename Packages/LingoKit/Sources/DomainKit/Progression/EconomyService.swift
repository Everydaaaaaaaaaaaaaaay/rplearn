import CoreKit
import Foundation
import PersistenceKit

/// 分级记忆配额（plan.md §3.5）：raw 原文窗口 / short+mid / long。
public struct MemoryQuota: Sendable, Equatable {
    public var rawWindow: Int
    public var shortMid: Int
    public var long: Int

    public init(rawWindow: Int, shortMid: Int, long: Int) {
        self.rawWindow = rawWindow
        self.shortMid = shortMid
        self.long = long
    }
}

/// 经济系统：道具定价与服务端权益对应的记忆配额。
public struct EconomyService: Sendable {
    /// 金币定价。
    public enum Price {
        public static let universalTicket = 500
        public static let countryTicket = 300
    }

    private let economyStore: EconomyStore
    private let itemStore: ItemStore
    private let ticketPurchaseGateway: (any TicketPurchaseGateway)?

    public init(
        economyStore: EconomyStore,
        itemStore: ItemStore,
        ticketPurchaseGateway: (any TicketPurchaseGateway)? = nil
    ) {
        self.economyStore = economyStore
        self.itemStore = itemStore
        self.ticketPurchaseGateway = ticketPurchaseGateway
    }

    public static func memoryQuota(for tier: SubscriptionTier) -> MemoryQuota {
        switch tier {
        case .free: MemoryQuota(rawWindow: 12, shortMid: 8, long: 5)
        case .plus: MemoryQuota(rawWindow: 24, shortMid: 20, long: 15)
        case .pro: MemoryQuota(rawWindow: 40, shortMid: 40, long: 40)
        }
    }

    // MARK: - 金币购票（2.3 地图使用）

    /// 金币购买机票：先扣款后发券。
    @discardableResult
    public func buyTicket(type: ItemType, countryCode: String? = nil) async throws -> ItemDTO {
        if let ticketPurchaseGateway {
            return try await ticketPurchaseGateway.purchaseTicket(
                type: type,
                countryCode: countryCode
            )
        }
        let price = type == .ticketUniversal ? Price.universalTicket : Price.countryTicket
        _ = try await economyStore.spendCoins(price)
        do {
            return try await itemStore.addTicket(type: type, countryCode: countryCode, source: .purchase)
        } catch {
            // 发券失败回滚金币
            _ = try? await economyStore.addCoins(price)
            throw error
        }
    }

    // MARK: - 调试

    #if DEBUG
    public func grantDebugCoins(_ amount: Int = 500) async {
        _ = try? await economyStore.addCoins(amount)
    }
    #endif
}
