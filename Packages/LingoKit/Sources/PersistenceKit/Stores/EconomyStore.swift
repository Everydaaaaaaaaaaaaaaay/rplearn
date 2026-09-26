import CoreKit
import Foundation
import SwiftData

/// 经济/档案仓库：用户档案（单例行）、金币、订阅、地区解锁。
@ModelActor
public actor EconomyStore {
    public enum EconomyError: Error {
        case insufficientCoins
    }

    /// 取用户档案，没有则创建默认档案。
    public func profile() throws -> UserProfileDTO {
        try dto(from: fetchOrCreateProfile())
    }

    public func updateProfile(_ mutate: @Sendable (inout UserProfileDTO) -> Void) throws -> UserProfileDTO {
        let entity = try fetchOrCreateProfile()
        var profile = try dto(from: entity)
        mutate(&profile)
        entity.displayName = profile.displayName
        entity.currentRegionID = profile.currentRegionID
        entity.subscriptionTierRaw = profile.subscriptionTier.rawValue
        entity.friendSlotLimit = profile.friendSlotLimit
        entity.unlockedRegionIDs = profile.unlockedRegionIDs
        entity.difficultyLevelRaw = profile.difficultyLevel.rawValue
        entity.hasCompletedOnboarding = profile.hasCompletedOnboarding
        entity.learningGoalRaw = profile.learningGoal.rawValue
        entity.studyStageRaw = profile.studyStage?.rawValue
        entity.proficiencySourceRaw = profile.proficiencySource.rawValue
        entity.placementScore = profile.placementScore
        entity.placementCompletedAt = profile.placementCompletedAt
        entity.hasCompletedProfileSetup = profile.hasCompletedProfileSetup
        try fetchOrCreateJourneyState().starterRegionID = profile.starterRegionID
        // 金币不经此通道改动，走 addCoins/spendCoins 保证不为负。
        try modelContext.save()
        return try dto(from: entity)
    }

    @discardableResult
    public func addCoins(_ amount: Int) throws -> Int {
        let entity = try fetchOrCreateProfile()
        entity.coins += max(0, amount)
        try modelContext.save()
        return entity.coins
    }

    /// Guest story rewards and their receipt commit together. A failed save can
    /// be retried without either losing the grant or crediting it twice.
    public func claimLocalStoryReward(storyID: String, coins: Int) throws -> Bool {
        do {
            let profile = try fetchOrCreateProfile()
            let existing = try modelContext.fetch(FetchDescriptor<StoryProgressEntity>(
                predicate: #Predicate { $0.storyID == storyID }
            )).first
            if existing?.completedAt != nil { return false }
            let receipt = existing ?? StoryProgressEntity(storyID: storyID)
            if existing == nil { modelContext.insert(receipt) }
            receipt.completedAt = .now
            receipt.currentNodeID = nil
            profile.coins += max(0, coins)
            try ContentMutationJournal.upsert(
                in: modelContext, resourceType: .storyProgress, resourceID: storyID, parentID: nil,
                payloadJSON: try ContentMutationJournal.encode(ContentStoryProgressPayload(
                    completedAt: receipt.completedAt, currentNodeId: nil,
                    flags: StoryProgressStore.decodeFlags(receipt.flagsJSON)
                ))
            )
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    @discardableResult
    public func spendCoins(_ amount: Int) throws -> Int {
        let entity = try fetchOrCreateProfile()
        guard entity.coins >= amount else { throw EconomyError.insufficientCoins }
        entity.coins -= amount
        try modelContext.save()
        return entity.coins
    }

    public func unlockRegion(_ regionID: String) throws {
        let entity = try fetchOrCreateProfile()
        if !entity.unlockedRegionIDs.contains(regionID) {
            entity.unlockedRegionIDs.append(regionID)
        }
        try modelContext.save()
    }

    /// 用服务器权威快照替换本地显示缓存。不能通过此入口增量修改资产。
    public func replaceAuthoritativeProfile(_ profile: UserProfileDTO) throws {
        let entity = try fetchOrCreateProfile()
        entity.displayName = profile.displayName
        entity.currentRegionID = profile.currentRegionID
        entity.coins = profile.coins
        entity.subscriptionTierRaw = profile.subscriptionTier.rawValue
        entity.friendSlotLimit = profile.friendSlotLimit
        entity.unlockedRegionIDs = profile.unlockedRegionIDs
        entity.difficultyLevelRaw = profile.difficultyLevel.rawValue
        entity.hasCompletedOnboarding = profile.hasCompletedOnboarding
        entity.learningGoalRaw = profile.learningGoal.rawValue
        entity.studyStageRaw = profile.studyStage?.rawValue
        entity.proficiencySourceRaw = profile.proficiencySource.rawValue
        entity.placementScore = profile.placementScore
        entity.placementCompletedAt = profile.placementCompletedAt
        entity.hasCompletedProfileSetup = profile.hasCompletedProfileSetup
        try fetchOrCreateJourneyState().starterRegionID = profile.starterRegionID
        try modelContext.save()
    }

    /// 缓存服务端统一权益。订阅等级与权益派生配额不能由普通档案修改接口写入。
    public func applyAuthoritativeEntitlement(
        tier: SubscriptionTier,
        friendSlotLimit: Int?
    ) throws {
        let entity = try fetchOrCreateProfile()
        entity.subscriptionTierRaw = tier.rawValue
        if let friendSlotLimit {
            entity.friendSlotLimit = max(0, friendSlotLimit)
        }
        try modelContext.save()
    }

    /// 切换到另一个账号前清除服务器权威状态缓存，防止跨账号短暂串读。
    public func clearAuthoritativeCache() throws {
        try modelContext.delete(model: UserProfileEntity.self)
        try modelContext.delete(model: JourneyStateEntity.self)
        try modelContext.save()
    }

    // MARK: - 私有

    private func fetchOrCreateProfile() throws -> UserProfileEntity {
        if let existing = try modelContext.fetch(FetchDescriptor<UserProfileEntity>()).first {
            return existing
        }
        let profile = UserProfileEntity()
        modelContext.insert(profile)
        try modelContext.save()
        return profile
    }

    private func fetchOrCreateJourneyState() throws -> JourneyStateEntity {
        if let existing = try modelContext.fetch(FetchDescriptor<JourneyStateEntity>()).first {
            return existing
        }
        let state = JourneyStateEntity()
        modelContext.insert(state)
        return state
    }

    private func dto(from entity: UserProfileEntity) throws -> UserProfileDTO {
        UserProfileDTO(
            displayName: entity.displayName,
            currentRegionID: entity.currentRegionID,
            starterRegionID: try fetchOrCreateJourneyState().starterRegionID,
            coins: entity.coins,
            subscriptionTier: SubscriptionTier(rawValue: entity.subscriptionTierRaw) ?? .free,
            friendSlotLimit: entity.friendSlotLimit,
            unlockedRegionIDs: entity.unlockedRegionIDs,
            difficultyLevel: DifficultyLevel(rawValue: entity.difficultyLevelRaw) ?? .junior3,
            hasCompletedOnboarding: entity.hasCompletedOnboarding,
            learningGoal: LearningGoal(rawValue: entity.learningGoalRaw) ?? .dailyConversation,
            studyStage: entity.studyStageRaw.flatMap(StudyStage.init(rawValue:)),
            proficiencySource: ProficiencySource(rawValue: entity.proficiencySourceRaw) ?? .selfReported,
            placementScore: entity.placementScore,
            placementCompletedAt: entity.placementCompletedAt,
            hasCompletedProfileSetup: entity.hasCompletedProfileSetup
        )
    }
}
