import Foundation
import Testing
@testable import DomainKit
@testable import PersistenceKit

@Suite("Local user state coordinator")
struct LocalUserStateCoordinatorTests {
    private struct Fixture {
        let economyStore: EconomyStore
        let itemStore: ItemStore
        let storyProgressStore: StoryProgressStore
        let coordinator: LocalUserStateCoordinator
    }

    private func makeFixture() throws -> Fixture {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let economyStore = EconomyStore(modelContainer: container)
        let itemStore = ItemStore(modelContainer: container)
        let storyProgressStore = StoryProgressStore(modelContainer: container)
        return Fixture(
            economyStore: economyStore,
            itemStore: itemStore,
            storyProgressStore: storyProgressStore,
            coordinator: LocalUserStateCoordinator(
                economyStore: economyStore,
                itemStore: itemStore,
                storyProgressStore: storyProgressStore
            )
        )
    }

    @Test("游客档案修改保存在本地")
    func profileUpdate() async throws {
        let fixture = try makeFixture()

        let profile = try await fixture.coordinator.updateProfile {
            $0.displayName = "本地旅行者"
            $0.hasCompletedOnboarding = true
        }

        #expect(profile.displayName == "本地旅行者")
        #expect(profile.hasCompletedOnboarding)
        #expect(try await fixture.economyStore.profile() == profile)
    }

    @Test("游客初始机票只发放一次")
    func starterTicketIsIdempotent() async throws {
        let fixture = try makeFixture()

        #expect(try await fixture.coordinator.claimStarterTicket())
        #expect(try await !fixture.coordinator.claimStarterTicket())
        #expect(try await fixture.itemStore.unconsumedTickets().count == 1)
    }

    @Test("首选伙伴原子确定起始城市与路线，并开放五座主线城市")
    func onboardingSelection() async throws {
        let fixture = try makeFixture()

        let profile = try await fixture.coordinator.completeOnboarding(
            starterRegionID: "melbourne"
        )

        #expect(profile.hasCompletedOnboarding)
        #expect(profile.currentRegionID == "melbourne")
        #expect(profile.starterRegionID == "melbourne")
        #expect(profile.unlockedRegionIDs == [
            "melbourne", "capetown", "london", "newyork", "singapore",
        ])
    }

    @Test("游客剧情奖励只发放一次")
    func storyRewardIsIdempotent() async throws {
        let fixture = try makeFixture()

        #expect(try await fixture.coordinator.completeStory("mainline_london"))
        #expect(try await !fixture.coordinator.completeStory("mainline_london"))
        #expect(
            try await fixture.economyStore.profile().coins
                == LocalUserStateCoordinator.storyCompletionReward
        )
        #expect(
            try await fixture.storyProgressStore.progress(storyID: "mainline_london")?.isCompleted
                == true
        )
    }
}
