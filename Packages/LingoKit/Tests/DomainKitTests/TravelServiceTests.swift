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
    private let capeTownMainline = Region(
        id: "capetown", nameEn: "Cape Town", nameZh: "开普敦", countryCode: "ZA",
        countryNameEn: "South Africa", countryNameZh: "南非", role: .mainline,
        taglineZh: "-", landmarks: [], activities: []
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
        #expect(!TravelService.requiresTicket(to: capeTownMainline, profile: lockedProfile))
    }

    @Test("默认开放的主线城市无需机票即可首次前往")
    func mainlineTravelIsFree() async throws {
        let fixture = try await makeFixture()

        let result = try await fixture.service.travel(to: capeTownMainline)

        #expect(!result.unlockedNow)
        #expect(result.ticketStub == nil)
        #expect(try await fixture.economyStore.profile().currentRegionID == "capetown")
        #expect(try await fixture.economyStore.profile().unlockedRegionIDs.contains("capetown"))
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

        let result = try await fixture.service.travel(to: melbourne, using: ticket)
        #expect(result.unlockedNow)
        #expect(result.fromRegionID == "london")
        #expect(result.toRegionID == "melbourne")
        #expect(result.ticketStub?.fromRegionID == "london")
        #expect(result.ticketStub?.toRegionID == "melbourne")
        #expect(result.ticketStub?.serialNumber.hasPrefix("LT-") == true)

        let profile = try await fixture.economyStore.profile()
        #expect(profile.currentRegionID == "melbourne")
        #expect(profile.unlockedRegionIDs.contains("melbourne"))
        #expect(try await fixture.itemStore.unconsumedTickets().isEmpty)
        #expect(try await fixture.stubStore.all().count == 1)
    }

    @Test("已解锁地区可自由往返，不消耗机票也不重复生成票根")
    func revisitUnlockedRegionsForFree() async throws {
        let fixture = try await makeFixture()
        try await fixture.economyStore.unlockRegion("melbourne")
        _ = try await fixture.itemStore.addTicket(type: .ticketUniversal, source: .story)

        let outbound = try await fixture.service.travel(to: melbourne)
        let inbound = try await fixture.service.travel(to: london)

        #expect(!outbound.unlockedNow)
        #expect(outbound.ticketStub == nil)
        #expect(outbound.fromRegionID == "london")
        #expect(outbound.toRegionID == "melbourne")
        #expect(!inbound.unlockedNow)
        #expect(inbound.ticketStub == nil)
        #expect(inbound.fromRegionID == "melbourne")
        #expect(inbound.toRegionID == "london")
        #expect(try await fixture.economyStore.profile().currentRegionID == "london")
        #expect(try await fixture.itemStore.unconsumedTickets().count == 1)
        #expect(try await fixture.stubStore.all().isEmpty)
    }

    @Test("首次解锁后往返同一城市只保留一张票根")
    func onlyFirstArrivalCreatesStub() async throws {
        let fixture = try await makeFixture()
        let ticket = try await fixture.itemStore.addTicket(
            type: .ticketUniversal,
            source: .story
        )

        let firstArrival = try await fixture.service.travel(
            to: melbourne,
            using: ticket
        )
        let returnTrip = try await fixture.service.travel(to: london)
        let revisit = try await fixture.service.travel(to: melbourne)

        #expect(firstArrival.ticketStub != nil)
        #expect(returnTrip.ticketStub == nil)
        #expect(revisit.ticketStub == nil)
        #expect(try await fixture.stubStore.all().count == 1)
    }

    @Test("相同目的地的服务端首次抵达重试保持唯一")
    func serverArrivalCacheIsUniquePerDestination() async throws {
        let fixture = try await makeFixture()
        let first = try await fixture.stubStore.cacheFirstServerArrival(
            id: UUID(),
            fromRegionID: "london",
            toRegionID: "melbourne",
            usedAt: Date(timeIntervalSince1970: 100)
        )
        let duplicate = try await fixture.stubStore.cacheFirstServerArrival(
            id: UUID(),
            fromRegionID: "newyork",
            toRegionID: "melbourne",
            usedAt: Date(timeIntervalSince1970: 200)
        )

        #expect(duplicate.id == first.id)
        #expect(duplicate.fromRegionID == "london")
        #expect(try await fixture.stubStore.all().count == 1)
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
