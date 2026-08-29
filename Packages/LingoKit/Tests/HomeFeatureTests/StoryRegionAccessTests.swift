import PersistenceKit
import Testing
@testable import HomeFeature

@Suite("StoryRegionAccess")
struct StoryRegionAccessTests {
    @Test("当前城市、主线城市与已解锁异地剧情均可打开，未到访支线城市仍锁定")
    func accessStates() {
        let profile = UserProfileDTO(
            displayName: "Traveler",
            currentRegionID: "london",
            starterRegionID: "london",
            coins: 0,
            subscriptionTier: .free,
            friendSlotLimit: 3,
            quizGloballyEnabled: true,
            unlockedRegionIDs: ["london", "melbourne"],
            difficultyLevel: .senior1,
            hasCompletedOnboarding: true
        )

        let current = StoryRegionAccess(regionID: "london", profile: profile)
        let unlockedAway = StoryRegionAccess(regionID: "melbourne", profile: profile)
        let defaultMainline = StoryRegionAccess(regionID: "newyork", profile: profile)
        let locked = StoryRegionAccess(regionID: "toronto", profile: profile)

        #expect(current == .current)
        #expect(current.canOpen)
        #expect(unlockedAway == .unlockedAway)
        #expect(unlockedAway.canOpen)
        #expect(defaultMainline == .unlockedAway)
        #expect(defaultMainline.canOpen)
        #expect(locked == .locked)
        #expect(!locked.canOpen)
    }
}
