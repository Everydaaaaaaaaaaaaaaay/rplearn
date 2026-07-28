import Foundation
import Testing
@testable import PersistenceKit

@Suite("EconomyStore")
struct EconomyStoreTests {
    private func makeStore() throws -> EconomyStore {
        EconomyStore(modelContainer: try ModelContainerFactory.makeContainer(inMemory: true))
    }

    @Test("默认档案：10 好友位、free 订阅、出题开")
    func defaultProfile() async throws {
        let store = try makeStore()
        let profile = try await store.profile()
        #expect(profile.friendSlotLimit == 10)
        #expect(profile.subscriptionTier == .free)
        #expect(profile.quizGloballyEnabled)
        #expect(profile.coins == 0)
        #expect(!profile.hasCompletedOnboarding)
    }

    @Test("金币增减与余额不足")
    func coins() async throws {
        let store = try makeStore()
        #expect(try await store.addCoins(100) == 100)
        #expect(try await store.spendCoins(30) == 70)
        await #expect(throws: EconomyStore.EconomyError.insufficientCoins) {
            try await store.spendCoins(1000)
        }
        // 失败不动余额
        #expect(try await store.profile().coins == 70)
    }

    @Test("档案更新会完整保存学习者资料与地区")
    func profileUpdate() async throws {
        let store = try makeStore()
        let placementDate = Date(timeIntervalSince1970: 1_774_972_800)
        _ = try await store.updateProfile { profile in
            profile.displayName = "旅人"
            profile.currentRegionID = "london"
            profile.starterRegionID = "london"
            profile.hasCompletedOnboarding = true
            profile.difficultyLevel = .senior2
            profile.learningGoal = .studyAbroad
            profile.studyStage = .seniorHigh
            profile.proficiencySource = .placement
            profile.placementScore = 72
            profile.placementCompletedAt = placementDate
            profile.hasCompletedProfileSetup = true
        }
        try await store.unlockRegion("london")
        try await store.unlockRegion("london") // 幂等
        let profile = try await store.profile()
        #expect(profile.displayName == "旅人")
        #expect(profile.currentRegionID == "london")
        #expect(profile.starterRegionID == "london")
        #expect(profile.unlockedRegionIDs == ["london"])
        #expect(profile.hasCompletedOnboarding)
        #expect(profile.difficultyLevel == .senior2)
        #expect(profile.learningGoal == .studyAbroad)
        #expect(profile.studyStage == .seniorHigh)
        #expect(profile.proficiencySource == .placement)
        #expect(profile.placementScore == 72)
        #expect(profile.placementCompletedAt == placementDate)
        #expect(profile.hasCompletedProfileSetup)
    }
}
