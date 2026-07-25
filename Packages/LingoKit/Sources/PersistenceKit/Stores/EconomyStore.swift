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
        try Self.dto(from: fetchOrCreateProfile())
    }

    public func updateProfile(_ mutate: @Sendable (inout UserProfileDTO) -> Void) throws -> UserProfileDTO {
        let entity = try fetchOrCreateProfile()
        var dto = Self.dto(from: entity)
        mutate(&dto)
        entity.displayName = dto.displayName
        entity.currentRegionID = dto.currentRegionID
        entity.subscriptionTierRaw = dto.subscriptionTier.rawValue
        entity.friendSlotLimit = dto.friendSlotLimit
        entity.quizGloballyEnabled = dto.quizGloballyEnabled
        entity.unlockedRegionIDs = dto.unlockedRegionIDs
        entity.difficultyLevelRaw = dto.difficultyLevel.rawValue
        entity.hasCompletedOnboarding = dto.hasCompletedOnboarding
        // 金币不经此通道改动，走 addCoins/spendCoins 保证不为负。
        try modelContext.save()
        return Self.dto(from: entity)
    }

    @discardableResult
    public func addCoins(_ amount: Int) throws -> Int {
        let entity = try fetchOrCreateProfile()
        entity.coins += max(0, amount)
        try modelContext.save()
        return entity.coins
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
        entity.quizGloballyEnabled = profile.quizGloballyEnabled
        entity.unlockedRegionIDs = profile.unlockedRegionIDs
        entity.difficultyLevelRaw = profile.difficultyLevel.rawValue
        entity.hasCompletedOnboarding = profile.hasCompletedOnboarding
        try modelContext.save()
    }

    /// 切换到另一个账号前清除服务器权威状态缓存，防止跨账号短暂串读。
    public func clearAuthoritativeCache() throws {
        try modelContext.delete(model: UserProfileEntity.self)
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

    static func dto(from entity: UserProfileEntity) -> UserProfileDTO {
        UserProfileDTO(
            displayName: entity.displayName,
            currentRegionID: entity.currentRegionID,
            coins: entity.coins,
            subscriptionTier: SubscriptionTier(rawValue: entity.subscriptionTierRaw) ?? .free,
            friendSlotLimit: entity.friendSlotLimit,
            quizGloballyEnabled: entity.quizGloballyEnabled,
            unlockedRegionIDs: entity.unlockedRegionIDs,
            difficultyLevel: DifficultyLevel(rawValue: entity.difficultyLevelRaw) ?? .junior3,
            hasCompletedOnboarding: entity.hasCompletedOnboarding
        )
    }
}
