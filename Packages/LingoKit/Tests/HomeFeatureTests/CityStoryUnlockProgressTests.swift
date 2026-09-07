import Foundation
import PersistenceKit
import Testing

@testable import HomeFeature

@Suite("CityStoryUnlockProgress")
struct CityStoryUnlockProgressTests {
    @Test("默认开放六篇，三张未使用机票开放全部十五篇")
    func availableTicketMilestones() {
        let initial = CityStoryUnlockProgress(
            profile: profile(),
            availableTickets: [],
            ticketStubs: []
        )
        #expect(initial.earnedTicketCount == 0)
        #expect(initial.unlockedChapterCount == 6)

        let complete = CityStoryUnlockProgress(
            profile: profile(),
            availableTickets: (0..<3).map { ticket(dayOffset: $0) },
            ticketStubs: []
        )
        #expect(complete.earnedTicketCount == 3)
        #expect(complete.unlockedChapterCount == 15)
    }

    @Test("机票消费后由票根或旧到访记录继续计数且不重复累计")
    func spentTicketsRemainCredited() {
        let progress = CityStoryUnlockProgress(
            profile: profile(
                currentRegionID: "dublin",
                unlockedRegionIDs: [
                    "london", "capetown", "newyork", "melbourne", "singapore",
                    "dublin", "edinburgh",
                ]
            ),
            availableTickets: [ticket(dayOffset: 2)],
            ticketStubs: [stub(to: "dublin")]
        )

        #expect(progress.earnedTicketCount == 3)
        #expect(progress.unlockedChapterCount == 15)
    }

    private func profile(
        currentRegionID: String = "london",
        unlockedRegionIDs: [String] = [
            "london", "capetown", "newyork", "melbourne", "singapore",
        ]
    ) -> UserProfileDTO {
        UserProfileDTO(
            displayName: "Traveler",
            currentRegionID: currentRegionID,
            starterRegionID: "london",
            coins: 0,
            subscriptionTier: .free,
            friendSlotLimit: 3,
            quizGloballyEnabled: true,
            unlockedRegionIDs: unlockedRegionIDs,
            difficultyLevel: .senior1,
            hasCompletedOnboarding: true
        )
    }

    private func ticket(dayOffset: Int) -> ItemDTO {
        ItemDTO(
            id: UUID(),
            type: .ticketUniversal,
            source: .story,
            createdAt: Date(timeIntervalSince1970: TimeInterval(dayOffset * 86_400))
        )
    }

    private func stub(to regionID: String) -> TicketStubDTO {
        TicketStubDTO(
            id: UUID(),
            fromRegionID: "london",
            toRegionID: regionID,
            usedAt: .now,
            serialNumber: "LT-123456",
            artSeed: 0
        )
    }
}
