import CoreKit
import Foundation
import SwiftData

/// 角色名册仓库：主角色导入、角色查询、好友管理。所有写操作经此 actor。
@ModelActor
public actor RosterStore {
    public enum RosterError: Error {
        case characterNotFound
        case friendSlotsFull
    }

    /// 首启导入 3 主角色（幂等：按 name+isMainCharacter 去重）。
    /// 角色先作为候选写入名册，只有首选伙伴与主线中相遇的伙伴会进入好友列表。
    public func importMainCharactersIfNeeded(cards: [CharacterCard], difficulty: DifficultyLevel = .junior3) throws {
        let existing = try modelContext.fetch(
            FetchDescriptor<CharacterEntity>(predicate: #Predicate { $0.isMainCharacter })
        )
        let existingNames = Set(existing.map(\.name))
        for entity in existing {
            if let stableID = Self.mainCharacterID(avatarAssetName: entity.avatarAssetName) {
                entity.characterID = stableID
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
                cardJSON: card.encodedJSON()
            )
            modelContext.insert(entity)
            importedCount += 1
        }
        if importedCount > 0 || !existing.isEmpty {
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
    public func addCharacter(card: CharacterCard, difficulty: DifficultyLevel, isFriend: Bool) throws -> UUID {
        let entity = CharacterEntity(
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
            let needsFriendUpdate = entity.isFriend != shouldBeFriend
            let needsDifficultyUpdate = entity.difficultyLevelRaw != difficulty.rawValue
            guard needsFriendUpdate || needsDifficultyUpdate else { continue }
            if needsFriendUpdate {
                entity.isFriend = shouldBeFriend
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
        guard let entity = entities.first, !entity.isFriend else { return }
        entity.isFriend = true
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
        try journal(entity)
        try modelContext.save()
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
                background: card?.background,
                gender: entity.genderRaw,
                hobbies: entity.hobbies,
                name: entity.name,
                nationality: entity.nationality,
                occupation: entity.occupation,
                personality: entity.personality,
                regionId: entity.regionID,
                speechStyle: card?.speechStyle
            ),
            difficulty: entity.difficultyLevelRaw,
            isFriend: entity.isFriend,
            isFavorite: entity.isFavorite,
            isMainCharacter: entity.isMainCharacter,
            metAt: entity.metAt
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
            isFavorite: entity.isFavorite
        )
    }
}
