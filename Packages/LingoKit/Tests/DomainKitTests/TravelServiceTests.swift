import Foundation
import Testing
@testable import DomainKit
@testable import PersistenceKit

@Suite("TravelService")
struct TravelServiceTests {
    private struct Fixture {
        let economyStore: EconomyStore
        let itemStore: ItemStore
        let stubStore: TicketStubStore
        let service: TravelService
    }

    private let london = Region(
        id: "london", nameEn: "London", nameZh: "伦敦", countryCode: "GB",
        countryNameEn: "United Kingdom", countryNameZh: "英国", taglineZh: "-", landmarks: [], activities: []
    )
    private let melbourne = Region(
        id: "melbourne", nameEn: "Melbourne", nameZh: "墨尔本", countryCode: "AU",
        countryNameEn: "Australia", countryNameZh: "澳大利亚", taglineZh: "-", landmarks: [], activities: []
    )

    private func makeFixture() async throws -> Fixture {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let economyStore = EconomyStore(modelContainer: container)
        let itemStore = ItemStore(modelContainer: container)
        let stubStore = TicketStubStore(modelContainer: container)
        _ = try await economyStore.updateProfile {
            $0.currentRegionID = "london"
            $0.unlockedRegionIDs = ["london"]
        }
        return Fixture(
            economyStore: economyStore,
            itemStore: itemStore,
            stubStore: stubStore,
            service: TravelService(economyStore: economyStore, itemStore: itemStore, stubStore: stubStore)
        )
    }

    @Test("只有未解锁地区需要机票")
    func ticketRequirement() {
        let profile = UserProfileDTO(
            displayName: "Traveler",
            currentRegionID: "london",
            coins: 0,
            subscriptionTier: .free,
            friendSlotLimit: 3,
            quizGloballyEnabled: true,
            unlockedRegionIDs: ["london", "melbourne"],
            difficultyLevel: .junior3,
            hasCompletedOnboarding: true
        )

        #expect(!TravelService.requiresTicket(to: london, profile: profile))
        #expect(!TravelService.requiresTicket(to: melbourne, profile: profile))

        var lockedProfile = profile
        lockedProfile.unlockedRegionIDs.removeAll { $0 == "melbourne" }
        #expect(TravelService.requiresTicket(to: melbourne, profile: lockedProfile))
    }

    @Test("机票可用性：通用票全通、国家票匹配国家、已用票不可用")
    func ticketUsability() {
        func ticket(_ type: ItemType, country: String? = nil, consumed: Bool = false) -> ItemDTO {
            ItemDTO(
                id: UUID(), type: type, countryCode: country, source: .story,
                createdAt: .now, consumedAt: consumed ? .now : nil
            )
        }
        #expect(TravelService.isTicketUsable(ticket(.ticketUniversal), for: melbourne))
        #expect(TravelService.isTicketUsable(ticket(.ticketCountry, country: "AU"), for: melbourne))
        #expect(TravelService.isTicketUsable(ticket(.ticketCountry, country: "au"), for: melbourne))
        #expect(!TravelService.isTicketUsable(ticket(.ticketCountry, country: "GB"), for: melbourne))
        #expect(!TravelService.isTicketUsable(ticket(.ticketUniversal, consumed: true), for: melbourne))
    }

    @Test("首次旅行：消耗机票、更新当前地区并解锁、生成票根")
    func firstTravelUnlocksRegion() async throws {
        let fixture = try await makeFixture()
        let ticket = try await fixture.itemStore.addTicket(type: .ticketUniversal, source: .story)

        let stub = try await fixture.service.travel(to: melbourne, using: ticket)
        #expect(stub.fromRegionID == "london")
        #expect(stub.toRegionID == "melbourne")
        #expect(stub.serialNumber.hasPrefix("LT-"))

        let profile = try await fixture.economyStore.profile()
        #expect(profile.currentRegionID == "melbourne")
        #expect(profile.unlockedRegionIDs.contains("melbourne"))
        #expect(try await fixture.itemStore.unconsumedTickets().isEmpty)
        #expect(try await fixture.stubStore.all().count == 1)
    }

    @Test("已解锁地区可自由往返且不消耗机票")
    func revisitUnlockedRegionsForFree() async throws {
        let fixture = try await makeFixture()
        try await fixture.economyStore.unlockRegion("melbourne")
        _ = try await fixture.itemStore.addTicket(type: .ticketUniversal, source: .story)

        let outbound = try await fixture.service.travel(to: melbourne)
        let inbound = try await fixture.service.travel(to: london)

        #expect(outbound.fromRegionID == "london")
        #expect(outbound.toRegionID == "melbourne")
        #expect(inbound.fromRegionID == "melbourne")
        #expect(inbound.toRegionID == "london")
        #expect(try await fixture.economyStore.profile().currentRegionID == "london")
        #expect(try await fixture.itemStore.unconsumedTickets().count == 1)
        #expect(try await fixture.stubStore.all().count == 2)
    }

    @Test("旧档案离开当前城市后会补记为已去过")
    func recordsLegacyOriginAsUnlocked() async throws {
        let fixture = try await makeFixture()
        _ = try await fixture.economyStore.updateProfile { $0.unlockedRegionIDs = [] }
        let ticket = try await fixture.itemStore.addTicket(type: .ticketUniversal, source: .story)

        _ = try await fixture.service.travel(to: melbourne, using: ticket)

        let profile = try await fixture.economyStore.profile()
        #expect(profile.unlockedRegionIDs.contains("london"))
        #expect(profile.unlockedRegionIDs.contains("melbourne"))
    }

    @Test("首次旅行缺票、原地旅行与不匹配机票被拒绝")
    func travelRejections() async throws {
        let fixture = try await makeFixture()
        let gbTicket = try await fixture.itemStore.addTicket(type: .ticketCountry, countryCode: "GB", source: .purchase)

        await #expect(throws: TravelService.TravelError.ticketRequired) {
            try await fixture.service.travel(to: melbourne)
        }
        await #expect(throws: TravelService.TravelError.ticketNotUsable) {
            try await fixture.service.travel(to: melbourne, using: gbTicket)
        }
        await #expect(throws: TravelService.TravelError.alreadyThere) {
            try await fixture.service.travel(to: london, using: gbTicket)
        }
        // 失败不消耗机票
        #expect(try await fixture.itemStore.unconsumedTickets().count == 1)
    }
}
