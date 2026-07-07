import Foundation
import Testing
@testable import DomainKit
@testable import PersistenceKit

@Suite("EconomyService")
struct EconomyServiceTests {
    private struct Fixture {
        let economyStore: EconomyStore
        let itemStore: ItemStore
        let service: EconomyService
    }

    private struct FailingGateway: PurchaseGateway {
        struct Failure: Error {}
        func purchaseSubscription(_ tier: SubscriptionTier) async throws {
            throw Failure()
        }
        func restorePurchases() async throws -> SubscriptionTier? { nil }
    }

    private func makeFixture(gateway: any PurchaseGateway = LocalPurchaseGateway()) throws -> Fixture {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let economyStore = EconomyStore(modelContainer: container)
        let itemStore = ItemStore(modelContainer: container)
        return Fixture(
            economyStore: economyStore,
            itemStore: itemStore,
            service: EconomyService(economyStore: economyStore, itemStore: itemStore, gateway: gateway)
        )
    }

    @Test("本地模拟订阅切换写入档案")
    func subscribeUpdatesProfile() async throws {
        let fixture = try makeFixture()
        let profile = try await fixture.service.subscribe(to: .plus)
        #expect(profile.subscriptionTier == .plus)
        #expect(try await fixture.economyStore.profile().subscriptionTier == .plus)
    }

    @Test("网关失败不改档案")
    func gatewayFailureKeepsProfile() async throws {
        let fixture = try makeFixture(gateway: FailingGateway())
        await #expect(throws: Error.self) {
            _ = try await fixture.service.subscribe(to: .pro)
        }
        #expect(try await fixture.economyStore.profile().subscriptionTier == .free)
    }

    @Test("订阅配额表", arguments: [
        (SubscriptionTier.free, 12, 8, 5),
        (SubscriptionTier.plus, 24, 20, 15),
        (SubscriptionTier.pro, 40, 40, 40),
    ])
    func quotaTable(tier: SubscriptionTier, raw: Int, shortMid: Int, long: Int) {
        let quota = EconomyService.memoryQuota(for: tier)
        #expect(quota == MemoryQuota(rawWindow: raw, shortMid: shortMid, long: long))
    }

    @Test("金币购票：扣款并发券，余额不足抛错")
    func buyTicket() async throws {
        let fixture = try makeFixture()
        _ = try await fixture.economyStore.addCoins(600)
        let ticket = try await fixture.service.buyTicket(type: .ticketUniversal)
        #expect(ticket.source == .purchase)
        #expect(try await fixture.economyStore.profile().coins == 100)

        await #expect(throws: EconomyStore.EconomyError.insufficientCoins) {
            _ = try await fixture.service.buyTicket(type: .ticketUniversal)
        }
        #expect(try await fixture.itemStore.unconsumedTickets().count == 1)
    }
}
