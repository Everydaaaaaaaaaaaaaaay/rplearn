import Foundation
import PersistenceKit

/// 未登录用户的本地权威状态。
///
/// 游客可以完整使用档案、剧情奖励和机票等本地玩法；登录后由
/// `BackendUserStateCoordinator` 接管这些命令，避免客户端与服务端同时修改资产。
public actor LocalUserStateCoordinator:
    ProfileCommandGateway,
    OnboardingCommandGateway,
    ProgressionRewardGateway
{
    public static func storyRewardRange(_ storyID: String) -> ClosedRange<Int> {
        let rewardID = DepartureStoryIdentity.rewardID(for: storyID) ?? storyID
        return rewardID.hasPrefix("city_") || rewardID.hasSuffix("_2") ? 100...130 : 120...180
    }

    private let economyStore: EconomyStore
    private let itemStore: ItemStore
    private let storyProgressStore: StoryProgressStore

    public init(
        economyStore: EconomyStore,
        itemStore: ItemStore,
        storyProgressStore: StoryProgressStore
    ) {
        self.economyStore = economyStore
        self.itemStore = itemStore
        self.storyProgressStore = storyProgressStore
    }

    public func updateProfile(
        _ mutate: @Sendable (inout UserProfileDTO) -> Void
    ) async throws -> UserProfileDTO {
        try await economyStore.updateProfile(mutate)
    }

    public func completeOnboarding(starterRegionID: String) async throws -> UserProfileDTO {
        try await economyStore.updateProfile { profile in
            profile.currentRegionID = starterRegionID
            profile.starterRegionID = starterRegionID
            for regionID in MainlineCatalog.journey(starterRegionID: starterRegionID).stops.map(\.regionID)
            where !profile.unlockedRegionIDs.contains(regionID) {
                profile.unlockedRegionIDs.append(regionID)
            }
            profile.hasCompletedOnboarding = true
        }
    }

    public func claimStarterTicket() async throws -> Bool {
        guard try await !itemStore.hasTicket(source: .quest) else {
            return false
        }
        _ = try await itemStore.addTicket(
            type: .ticketUniversal,
            source: .quest
        )
        return true
    }

    public func completeStory(_ storyID: String) async throws -> Bool {
        try await completeStoryReward(storyID) != nil
    }

    public func completeStoryReward(_ storyID: String) async throws -> Int? {
        let coins = Int.random(in: Self.storyRewardRange(storyID))
        return try await economyStore.claimLocalStoryReward(storyID: storyID, coins: coins) ? coins : nil
    }
}
