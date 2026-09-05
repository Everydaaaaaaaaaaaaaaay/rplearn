import CoreKit
import Foundation
import SwiftData

public extension Notification.Name {
    /// 特别关心状态完成持久化后发送；object 为角色 UUID，userInfo 包含 isFavorite。
    static let rosterFavoriteDidChange = Notification.Name("LingoTripRosterFavoriteDidChange")
    /// 一次关系状态完成持久化后发送；object 为角色 UUID。
    static let rosterRelationshipDidChange = Notification.Name("LingoTripRosterRelationshipDidChange")
    /// 联系人状态或偏好保存完成后发送；object 为角色 UUID。
    static let rosterContactDidChange = Notification.Name("LingoTripRosterContactDidChange")
    /// 私有人格成长分支保存完成后发送；object 为角色 UUID。
    static let rosterGrowthDidChange = Notification.Name("LingoTripRosterGrowthDidChange")
}

/// 角色名册仓库：主角色导入、角色查询、好友管理。所有写操作经此 actor。
@ModelActor
public actor RosterStore {
    public enum RosterError: Error {
        case characterNotFound
        case friendSlotsFull
        case identityConflict
    }

    /// 首启导入 3 主角色（幂等：按 name+isMainCharacter 去重）。
    /// 角色先作为候选写入名册，只有首选伙伴与主线中相遇的伙伴会进入好友列表。
    public func importMainCharactersIfNeeded(cards: [CharacterCard], difficulty: DifficultyLevel = .junior3) throws {
        let allExisting = try modelContext.fetch(FetchDescriptor<CharacterEntity>())
        var backfilledIdentity = false
        for entity in allExisting {
            if entity.travelerID == nil || entity.travelerID?.isEmpty == true {
                entity.travelerID = TravelerIDGenerator.make(from: entity.characterID)
                backfilledIdentity = true
            }
            if entity.contactStatusRaw == nil || entity.contactStatusRaw?.isEmpty == true {
                entity.contactStatusRaw = entity.isFriend
                    ? ContactStatus.friend.rawValue
                    : ContactStatus.candidate.rawValue
                backfilledIdentity = true
            }
        }
        let existing = try modelContext.fetch(
            FetchDescriptor<CharacterEntity>(predicate: #Predicate { $0.isMainCharacter })
        )
        let existingNames = Set(existing.map(\.name))
        for entity in existing {
            if let stableID = Self.mainCharacterID(avatarAssetName: entity.avatarAssetName) {
                entity.characterID = stableID
                entity.travelerID = TravelerIDGenerator.make(from: stableID)
            }
        }
        var importedCount = 0
        for card in cards where !existingNames.contains(card.name) {
            let entity = CharacterEntity(
                characterID: Self.mainCharacterID(avatarAssetName: card.avatarAssetName) ?? UUID(),
                name: card.name,
                age: card.age,
                genderRaw: card.gender.rawValue,
                nationality: card.nationality,
                regionID: card.regionID,
                occupation: card.occupation,
                hobbies: card.hobbies,
                appearance: card.appearance,
                personality: card.personality,
                avatarAssetName: card.avatarAssetName,
                difficultyLevelRaw: difficulty.rawValue,
                isMainCharacter: true,
                isFriend: false,
                contactStatusRaw: ContactStatus.candidate.rawValue,
                cardJSON: card.encodedJSON()
            )
            modelContext.insert(entity)
            importedCount += 1
        }
        if importedCount > 0 || !existing.isEmpty || backfilledIdentity {
            try modelContext.save()
        }
        if importedCount > 0 {
            Log.persistence.info("导入主角色 \(importedCount) 名")
        }
    }

    private static func mainCharacterID(avatarAssetName: String?) -> UUID? {
        switch avatarAssetName {
        case "avatar_oliver":
            UUID(uuidString: "8B3A2B24-8A4E-5A73-A2C4-0F5E8F05E001")
        case "avatar_ruby":
            UUID(uuidString: "8B3A2B24-8A4E-5A73-A2C4-0F5E8F05E002")
        case "avatar_marcus":
            UUID(uuidString: "8B3A2B24-8A4E-5A73-A2C4-0F5E8F05E003")
        default:
            nil
        }
    }

    /// 保存一个（偶遇生成的）新角色。
    public func addCharacter(
        characterID: UUID = UUID(),
        travelerID: String? = nil,
        card: CharacterCard,
        difficulty: DifficultyLevel,
        isFriend: Bool
    ) throws -> UUID {
        if let existing = try modelContext.fetch(
            FetchDescriptor<CharacterEntity>(
                predicate: #Predicate { $0.characterID == characterID }
            )
        ).first {
            return existing.characterID
        }
        if let travelerID,
           let collision = try modelContext.fetch(
               FetchDescriptor<CharacterEntity>(
                   predicate: #Predicate { $0.travelerID == travelerID }
               )
           ).first,
           collision.characterID != characterID {
            throw RosterError.identityConflict
        }
        let entity = CharacterEntity(
            characterID: characterID,
            travelerID: travelerID ?? TravelerIDGenerator.make(from: characterID),
            publicIdentityRegistered: travelerID != nil,
            name: card.name,
            age: card.age,
            genderRaw: card.gender.rawValue,
            nationality: card.nationality,
            regionID: card.regionID,
            occupation: card.occupation,
            hobbies: card.hobbies,
            appearance: card.appearance,
            personality: card.personality,
            avatarAssetName: card.avatarAssetName,
            difficultyLevelRaw: difficulty.rawValue,
            isMainCharacter: false,
            isFriend: isFriend,
            contactStatusRaw: isFriend ? ContactStatus.friend.rawValue : ContactStatus.candidate.rawValue,
            cardJSON: card.encodedJSON()
        )
        modelContext.insert(entity)
        try journal(entity)
        try modelContext.save()
        return entity.characterID
    }

    public func allCharacters() throws -> [CharacterDTO] {
        var descriptor = FetchDescriptor<CharacterEntity>()
        descriptor.sortBy = [SortDescriptor(\.metAt)]
        return try modelContext.fetch(descriptor).map(Self.dto(from:))
    }

    public func friends() throws -> [CharacterDTO] {
        var descriptor = FetchDescriptor<CharacterEntity>(predicate: #Predicate { $0.isFriend })
        descriptor.sortBy = [SortDescriptor(\.metAt)]
        return try modelContext.fetch(descriptor).map(Self.dto(from:))
    }

    /// 用户明确移除但仍保留聊天与共同经历的联系人。
    public func formerContacts() throws -> [CharacterDTO] {
        let removed = ContactStatus.removed.rawValue
        var descriptor = FetchDescriptor<CharacterEntity>(
            predicate: #Predicate { $0.contactStatusRaw == removed }
        )
        descriptor.sortBy = [SortDescriptor(\CharacterEntity.metAt, order: .reverse)]
        return try modelContext.fetch(descriptor).map(Self.dto(from:))
    }

    /// 端侧精确搜索；公共社区上线后同一接口由服务端公共 NPC 注册表补全。
    public func character(travelerID: String) throws -> CharacterDTO? {
        let normalized = travelerID.filter(\.isNumber)
        guard TravelerIDGenerator.isValid(normalized) else { return nil }
        return try modelContext.fetch(
            FetchDescriptor<CharacterEntity>(predicate: #Predicate { $0.travelerID == normalized })
        ).first.map(Self.dto(from:))
    }

    /// 登记成功后把服务端全局旅伴号和永久头像回填到同一角色，不触碰用户私有关系分支。
    public func applyPublicIdentity(
        characterID: UUID,
        travelerID: String,
        card: CharacterCard
    ) throws {
        guard TravelerIDGenerator.isValid(travelerID) else {
            throw RosterError.identityConflict
        }
        guard let entity = try modelContext.fetch(
            FetchDescriptor<CharacterEntity>(
                predicate: #Predicate { $0.characterID == characterID }
            )
        ).first else {
            throw RosterError.characterNotFound
        }
        if let collision = try modelContext.fetch(
            FetchDescriptor<CharacterEntity>(
                predicate: #Predicate { $0.travelerID == travelerID }
            )
        ).first,
           collision.characterID != characterID {
            throw RosterError.identityConflict
        }
        entity.travelerID = travelerID
        entity.publicIdentityRegistered = true
        entity.name = card.name
        entity.age = card.age
        entity.genderRaw = card.gender.rawValue
        entity.nationality = card.nationality
        entity.regionID = card.regionID
        entity.occupation = card.occupation
        entity.hobbies = card.hobbies
        entity.appearance = card.appearance
        entity.personality = card.personality
        entity.avatarAssetName = card.avatarAssetName
        entity.cardJSON = card.encodedJSON()
        try journal(entity)
        try modelContext.save()
    }

    public func character(id: UUID) throws -> CharacterDTO? {
        try fetchEntity(id: id).map(Self.dto(from:))
    }

    /// 以主线权威进度重建三位主角的可见状态，并让对话等级跟随当前学习者档案。
    public func configureMainCharacters(
        unlockedRegionIDs: Set<String>,
        difficulty: DifficultyLevel
    ) throws {
        let entities = try modelContext.fetch(
            FetchDescriptor<CharacterEntity>(predicate: #Predicate { $0.isMainCharacter })
        )
        var changed = false
        for entity in entities {
            let shouldBeFriend = unlockedRegionIDs.contains(entity.regionID)
            let currentStatus = Self.contactStatus(from: entity)
            let targetStatus: ContactStatus = currentStatus == .removed
                ? .removed
                : (shouldBeFriend ? .friend : .candidate)
            let targetFriend = targetStatus == .friend
            let needsFriendUpdate = entity.isFriend != targetFriend
                || entity.contactStatusRaw != targetStatus.rawValue
            let needsDifficultyUpdate = entity.difficultyLevelRaw != difficulty.rawValue
            guard needsFriendUpdate || needsDifficultyUpdate else { continue }
            if needsFriendUpdate {
                entity.isFriend = targetFriend
                entity.contactStatusRaw = targetStatus.rawValue
            }
            if needsDifficultyUpdate {
                entity.difficultyLevelRaw = difficulty.rawValue
            }
            try journal(entity)
            changed = true
        }
        if changed {
            try modelContext.save()
        }
    }

    public func unlockMainCharacter(regionID: String) throws {
        let entities = try modelContext.fetch(
            FetchDescriptor<CharacterEntity>(
                predicate: #Predicate { $0.isMainCharacter && $0.regionID == regionID }
            )
        )
        guard let entity = entities.first,
              Self.contactStatus(from: entity) != .removed,
              !entity.isFriend
        else { return }
        entity.isFriend = true
        entity.contactStatusRaw = ContactStatus.friend.rawValue
        try journal(entity)
        try modelContext.save()
    }

    /// 占用的好友位数量（主角色不占位）。
    public func occupiedFriendSlots() throws -> Int {
        try modelContext.fetchCount(
            FetchDescriptor<CharacterEntity>(predicate: #Predicate { $0.isFriend && !$0.isMainCharacter })
        )
    }

    /// 加好友（校验好友位）。
    public func makeFriend(characterID: UUID, slotLimit: Int) throws {
        guard let entity = try fetchEntity(id: characterID) else {
            throw RosterError.characterNotFound
        }
        guard !entity.isFriend else { return }
        if !entity.isMainCharacter {
            let occupied = try occupiedFriendSlots()
            guard occupied < slotLimit else { throw RosterError.friendSlotsFull }
        }
        entity.isFriend = true
        entity.contactStatusRaw = ContactStatus.friend.rawValue
        try journal(entity)
        try modelContext.save()
        postContactChange(characterID)
    }

    /// 只移除好友关系；聊天、记忆和共同经历继续保留在“过往联系人”。
    public func removeFriend(characterID: UUID) throws {
        guard let entity = try fetchEntity(id: characterID) else {
            throw RosterError.characterNotFound
        }
        guard Self.contactStatus(from: entity) != .removed else { return }
        entity.isFriend = false
        entity.contactStatusRaw = ContactStatus.removed.rawValue
        entity.isFavorite = false
        entity.proactiveMessagesEnabled = false
        entity.mutedUntil = nil
        try journal(entity)
        try modelContext.save()
        postContactChange(characterID)
    }

    public func updateContactPreferences(
        characterID: UUID,
        preferences: ContactPreferences
    ) throws {
        guard let entity = try fetchEntity(id: characterID) else {
            throw RosterError.characterNotFound
        }
        entity.remarkName = Self.normalizedOptional(preferences.remarkName, maximumLength: 40)
        entity.privateNote = Self.normalizedOptional(preferences.privateNote, maximumLength: 500)
        entity.proactiveMessagesEnabled = preferences.proactiveMessagesEnabled
        entity.mutedUntil = preferences.mutedUntil
        try journal(entity)
        try modelContext.save()
        postContactChange(characterID)
    }

    public func setDifficulty(characterID: UUID, level: DifficultyLevel) throws {
        guard let entity = try fetchEntity(id: characterID) else {
            throw RosterError.characterNotFound
        }
        entity.difficultyLevelRaw = level.rawValue
        try journal(entity)
        try modelContext.save()
    }

    /// 设置联系人是否为“特别关心”。重复设置同一状态时保持幂等。
    public func setFavorite(characterID: UUID, isFavorite: Bool) throws {
        guard let entity = try fetchEntity(id: characterID) else {
            throw RosterError.characterNotFound
        }
        guard entity.isFriend, entity.isFavorite != isFavorite else { return }
        entity.isFavorite = isFavorite
        try journal(entity)
        try modelContext.save()
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .rosterFavoriteDidChange,
                object: characterID,
                userInfo: ["isFavorite": isFavorite]
            )
        }
        postContactChange(characterID)
    }

    /// 以乐观并发方式保存一次关系结算。后台点评乱序返回时不会覆盖更新的状态。
    @discardableResult
    public func updateRelationship(
        characterID: UUID,
        snapshot: RelationshipSnapshot,
        expectedRevision: Int
    ) throws -> Bool {
        guard let entity = try fetchEntity(id: characterID) else {
            throw RosterError.characterNotFound
        }
        let current = Self.relationship(from: entity)
        guard current.revision == expectedRevision else { return false }
        entity.relationshipJSON = snapshot.encodedJSON()
        try journal(entity)
        try modelContext.save()
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .rosterRelationshipDidChange,
                object: characterID
            )
        }
        return true
    }

    /// 在名册 actor 内原子读取、变换并保存关系，避免多个后台结算在客户端重试窗口内互相挤掉。
    @discardableResult
    public func mutateRelationship(
        characterID: UUID,
        mutation: @Sendable (RelationshipSnapshot) -> RelationshipSnapshot
    ) throws -> RelationshipSnapshot {
        guard let entity = try fetchEntity(id: characterID) else {
            throw RosterError.characterNotFound
        }
        let current = Self.relationship(from: entity)
        let updated = mutation(current)
        guard updated != current else { return current }

        entity.relationshipJSON = updated.encodedJSON()
        try journal(entity)
        try modelContext.save()
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .rosterRelationshipDidChange,
                object: characterID
            )
        }
        return updated
    }

    /// 在角色 actor 内原子推进当前用户专属的成长分支。
    @discardableResult
    public func mutateGrowth(
        characterID: UUID,
        mutation: @Sendable (CharacterGrowthSnapshot) -> CharacterGrowthSnapshot
    ) throws -> CharacterGrowthSnapshot {
        guard let entity = try fetchEntity(id: characterID) else {
            throw RosterError.characterNotFound
        }
        let current = Self.growth(from: entity)
        let updated = mutation(current)
        guard updated != current else { return current }
        entity.growthJSON = updated.encodedJSON()
        try journal(entity)
        try modelContext.save()
        Task { @MainActor in
            NotificationCenter.default.post(name: .rosterGrowthDidChange, object: characterID)
        }
        return updated
    }

    // MARK: - 私有

    private func fetchEntity(id: UUID) throws -> CharacterEntity? {
        try modelContext.fetch(
            FetchDescriptor<CharacterEntity>(predicate: #Predicate { $0.characterID == id })
        ).first
    }

    private func journal(_ entity: CharacterEntity) throws {
        let card = CharacterCard.decode(fromJSON: entity.cardJSON)
        let payload = ContentCharacterPayload(
            card: .init(
                age: entity.age,
                appearance: entity.appearance,
                avatarAssetName: entity.avatarAssetName,
                avatarId: card?.avatarID,
                avatarRemoteUrl: card?.avatarRemoteURL,
                background: card?.background,
                birthday: card?.birthday,
                gender: entity.genderRaw,
                hobbies: entity.hobbies,
                hometown: card?.hometown,
                languages: card?.languages,
                name: entity.name,
                nationality: entity.nationality,
                occupation: entity.occupation,
                personality: entity.personality,
                regionId: entity.regionID,
                speechStyle: card?.speechStyle,
                signature: card?.signature,
                personaVoice: card?.personaVoice
            ),
            difficulty: entity.difficultyLevelRaw,
            isFriend: entity.isFriend,
            isFavorite: entity.isFavorite,
            isMainCharacter: entity.isMainCharacter,
            metAt: entity.metAt,
            relationship: Self.relationship(from: entity),
            travelerId: entity.travelerID,
            publicIdentityRegistered: entity.publicIdentityRegistered,
            contactStatus: entity.contactStatusRaw,
            remarkName: entity.remarkName,
            privateNote: entity.privateNote,
            proactiveMessagesEnabled: entity.proactiveMessagesEnabled,
            mutedUntil: entity.mutedUntil,
            growth: Self.growth(from: entity)
        )
        try ContentMutationJournal.upsert(
            in: modelContext,
            resourceType: .character,
            resourceID: entity.characterID.uuidString.lowercased(),
            parentID: nil,
            payloadJSON: try ContentMutationJournal.encode(payload)
        )
    }

    static func dto(from entity: CharacterEntity) -> CharacterDTO {
        let card = CharacterCard.decode(fromJSON: entity.cardJSON) ?? CharacterCard(
            name: entity.name,
            age: entity.age,
            gender: CharacterGender(rawValue: entity.genderRaw) ?? .other,
            nationality: entity.nationality,
            regionID: entity.regionID,
            occupation: entity.occupation,
            hobbies: entity.hobbies,
            appearance: entity.appearance,
            personality: entity.personality,
            avatarAssetName: entity.avatarAssetName
        )
        return CharacterDTO(
            id: entity.characterID,
            card: card,
            difficultyLevel: DifficultyLevel(rawValue: entity.difficultyLevelRaw) ?? .junior3,
            isMainCharacter: entity.isMainCharacter,
            isFriend: entity.isFriend,
            metAt: entity.metAt,
            isFavorite: entity.isFavorite,
            relationship: relationship(from: entity)
            ,
            travelerID: entity.travelerID,
            publicIdentityRegistered: entity.publicIdentityRegistered,
            contactStatus: contactStatus(from: entity),
            contactPreferences: ContactPreferences(
                remarkName: entity.remarkName,
                privateNote: entity.privateNote,
                proactiveMessagesEnabled: entity.proactiveMessagesEnabled,
                mutedUntil: entity.mutedUntil
            ),
            growth: growth(from: entity)
        )
    }

    private static func relationship(from entity: CharacterEntity) -> RelationshipSnapshot {
        RelationshipSnapshot.decode(fromJSON: entity.relationshipJSON) ?? .initial
    }

    private static func growth(from entity: CharacterEntity) -> CharacterGrowthSnapshot {
        CharacterGrowthSnapshot.decode(fromJSON: entity.growthJSON) ?? .initial
    }

    private static func contactStatus(from entity: CharacterEntity) -> ContactStatus {
        entity.contactStatusRaw.flatMap(ContactStatus.init(rawValue:))
            ?? (entity.isFriend ? .friend : .candidate)
    }

    private static func normalizedOptional(_ value: String?, maximumLength: Int) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(maximumLength))
    }

    private nonisolated func postContactChange(_ characterID: UUID) {
        Task { @MainActor in
            NotificationCenter.default.post(name: .rosterContactDidChange, object: characterID)
        }
    }
}
