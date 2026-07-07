import CoreKit
import Foundation
import PersistenceKit

/// 支付网关：正式上线时替换为 StoreKit 2 实现（plan.md 决策 4）。
public protocol PurchaseGateway: Sendable {
    /// 购买/切换订阅。抛错表示购买失败。
    func purchaseSubscription(_ tier: SubscriptionTier) async throws
    func restorePurchases() async throws -> SubscriptionTier?
}

/// 本地模拟网关：立即成功，不接真实支付。
public struct LocalPurchaseGateway: PurchaseGateway {
    public init() {}

    public func purchaseSubscription(_ tier: SubscriptionTier) async throws {
        Log.app.info("本地模拟订阅购买：\(tier.rawValue)")
    }

    public func restorePurchases() async throws -> SubscriptionTier? {
        nil
    }
}

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

/// 经济系统：金币、订阅（本地模拟）、道具定价、订阅配额。
public struct EconomyService: Sendable {
    /// 金币定价。
    public enum Price {
        public static let universalTicket = 500
        public static let countryTicket = 300
    }

    private let economyStore: EconomyStore
    private let itemStore: ItemStore
    private let gateway: any PurchaseGateway

    public init(economyStore: EconomyStore, itemStore: ItemStore, gateway: any PurchaseGateway = LocalPurchaseGateway()) {
        self.economyStore = economyStore
        self.itemStore = itemStore
        self.gateway = gateway
    }

    // MARK: - 订阅

    public func subscribe(to tier: SubscriptionTier) async throws -> UserProfileDTO {
        try await gateway.purchaseSubscription(tier)
        return try await economyStore.updateProfile { profile in
            profile.subscriptionTier = tier
        }
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
