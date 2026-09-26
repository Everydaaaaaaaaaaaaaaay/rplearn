import Foundation
import SwiftData

extension ContentSyncStore {
// MARK: - Remote apply

    func apply(_ record: RemoteContentRecord) throws {
        if record.deletedAt != nil {
            try deleteLocal(record)
            try upsertMetadata(
                record,
                localKey: try metadata(
                    resourceType: record.resourceType,
                    resourceID: record.resourceID
                )?.localKey ?? record.resourceID
            )
            return
        }
        switch record.resourceType {
        case .character:
            try applyCharacter(record)
        case .conversation:
            try applyConversation(record)
        case .favorite:
            try applyFavorite(record)
        case .memory:
            try applyMemory(record)
        case .message:
            try applyMessage(record)
        case .storyProgress:
            try applyStoryProgress(record)
        }
    }

    func applyCharacter(_ record: RemoteContentRecord) throws {
        guard let id = UUID(uuidString: record.resourceID) else {
            throw SyncStoreError.invalidPayload
        }
        let payload: ContentCharacterPayload = try decode(record.payloadJSON)
        let existingReadingVoice = try character(id: id)
            .flatMap { CharacterCard.decode(fromJSON: $0.cardJSON)?.readingVoice }
        let existingActivityProfile = try character(id: id)
            .flatMap { CharacterCard.decode(fromJSON: $0.cardJSON)?.activityProfile }
        let card = CharacterCard(
            name: payload.card.name,
            age: payload.card.age,
            gender: CharacterGender(rawValue: payload.card.gender) ?? .other,
            nationality: payload.card.nationality,
            regionID: payload.card.regionId,
            occupation: payload.card.occupation,
            hobbies: payload.card.hobbies,
            appearance: payload.card.appearance,
            personality: payload.card.personality,
            speechStyle: payload.card.speechStyle,
            background: payload.card.background,
            avatarAssetName: payload.card.avatarAssetName,
            avatarID: payload.card.avatarId,
            avatarRemoteURL: payload.card.avatarRemoteUrl,
            signature: payload.card.signature,
            birthday: payload.card.birthday,
            hometown: payload.card.hometown,
            languages: payload.card.languages,
            readingVoice: payload.card.readingVoice ?? existingReadingVoice,
            personaVoice: payload.card.personaVoice,
            // Absence means a legacy server/device payload, not a request to erase the newer
            // persona field. This also keeps rolling-version sync from repeatedly downgrading it.
            activityProfile: payload.card.activityProfile ?? existingActivityProfile
        )
        let entity = try character(id: id) ?? {
            let created = CharacterEntity(
                characterID: id,
                travelerID: payload.travelerId,
                publicIdentityRegistered: payload.publicIdentityRegistered ?? false,
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
                difficultyLevelRaw: payload.difficulty,
                isMainCharacter: payload.isMainCharacter,
                isFriend: payload.isFriend,
                contactStatusRaw: payload.contactStatus,
                isFavorite: payload.isFavorite ?? false,
                remarkName: payload.remarkName,
                privateNote: payload.privateNote,
                proactiveMessagesEnabled: payload.proactiveMessagesEnabled ?? true,
                mutedUntil: payload.mutedUntil,
                relationshipJSON: (payload.relationship ?? .initial).encodedJSON(),
                growthJSON: (payload.growth ?? .initial).encodedJSON(),
                cardJSON: card.encodedJSON(),
                metAt: payload.metAt
            )
            modelContext.insert(created)
            return created
        }()
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
        entity.difficultyLevelRaw = payload.difficulty
        entity.isMainCharacter = payload.isMainCharacter
        entity.isFriend = payload.isFriend
        entity.contactStatusRaw = payload.contactStatus
            ?? (payload.isFriend ? ContactStatus.friend.rawValue : ContactStatus.candidate.rawValue)
        entity.isFavorite = payload.isFavorite ?? false
        entity.remarkName = payload.remarkName
        entity.privateNote = payload.privateNote
        entity.proactiveMessagesEnabled = payload.proactiveMessagesEnabled ?? true
        entity.mutedUntil = payload.mutedUntil
        entity.publicIdentityRegistered = payload.publicIdentityRegistered ?? false
        if let relationship = payload.relationship {
            entity.relationshipJSON = relationship.encodedJSON()
        }
        if let growth = payload.growth {
            entity.growthJSON = growth.encodedJSON()
        }
        entity.cardJSON = card.encodedJSON()
        entity.metAt = payload.metAt
        try upsertMetadata(record, localKey: record.resourceID)
    }

    func applyConversation(_ record: RemoteContentRecord) throws {
        guard let id = UUID(uuidString: record.resourceID),
              let parent = record.parentID.flatMap(UUID.init(uuidString:)),
              let character = try character(id: parent)
        else {
            throw SyncStoreError.missingParent
        }
        let payload: ContentConversationPayload = try decode(record.payloadJSON)
        let entity = try conversation(id: id) ?? {
            let created = ConversationEntity(
                conversationID: id,
                createdAt: payload.createdAt,
                lastMessageAt: payload.lastMessageAt,
                turnCount: payload.turnCount,
                lastSummarizedMessageIndex: payload.lastSummarizedMessageIndex,
                isEncounterSession: payload.isEncounterSession,
                isArchived: payload.isArchived,
                isPinned: payload.isPinned ?? false,
                lastReadAt: payload.lastReadAt
            )
            modelContext.insert(created)
            return created
        }()
        entity.character = character
        entity.createdAt = payload.createdAt
        entity.lastMessageAt = payload.lastMessageAt
        entity.turnCount = payload.turnCount
        entity.lastSummarizedMessageIndex = payload.lastSummarizedMessageIndex
        entity.isEncounterSession = payload.isEncounterSession
        entity.isArchived = payload.isArchived
        entity.isPinned = payload.isPinned ?? false
        entity.lastReadAt = payload.lastReadAt
        try upsertMetadata(record, localKey: record.resourceID)
    }

    func applyMessage(_ record: RemoteContentRecord) throws {
        guard let id = UUID(uuidString: record.resourceID),
              let parent = record.parentID.flatMap(UUID.init(uuidString:)),
              let conversation = try conversation(id: parent)
        else {
            throw SyncStoreError.missingParent
        }
        let payload: ContentMessagePayload = try decode(record.payloadJSON)
        let entity = try message(id: id) ?? {
            let created = MessageEntity(
                messageID: id,
                roleRaw: payload.role,
                kindRaw: payload.kind,
                text: payload.text,
                audioDuration: payload.audioDuration,
                orderIndex: payload.orderIndex,
                tokenEstimate: payload.tokenEstimate,
                keywordRangesJSON: payload.keywordRangesJson,
                coachReviewJSON: payload.coachReviewJson,
                speechReviewJSON: payload.speechReviewJson,
                translationZh: payload.translationZh,
                isInterrupted: payload.isInterrupted,
                createdAt: payload.createdAt
            )
            modelContext.insert(created)
            return created
        }()
        entity.conversation = conversation
        entity.roleRaw = payload.role
        entity.kindRaw = payload.kind
        entity.text = payload.text
        let existingMedia = try voiceMediaLink(messageID: id)
        if let assetID = payload.audioAssetId {
            let link = existingMedia ?? {
                let created = VoiceMediaLinkEntity(messageID: id)
                modelContext.insert(created)
                return created
            }()
            if link.assetID != assetID {
                link.localFileName = nil
            }
            link.assetID = assetID
            link.isRemoteReady = true
            link.updatedAt = record.updatedAt
            entity.audioFileName = link.localFileName
        } else if try voiceMediaUpload(messageID: id) == nil {
            existingMedia?.assetID = nil
            existingMedia?.isRemoteReady = false
            existingMedia?.updatedAt = record.updatedAt
            entity.audioFileName = existingMedia?.localFileName
        }
        entity.audioDuration = payload.audioDuration
        entity.orderIndex = payload.orderIndex
        entity.tokenEstimate = payload.tokenEstimate
        entity.keywordRangesJSON = payload.keywordRangesJson
        entity.coachReviewJSON = payload.coachReviewJson
        entity.speechReviewJSON = payload.speechReviewJson
        entity.translationZh = payload.translationZh
        entity.isInterrupted = payload.isInterrupted
        entity.createdAt = payload.createdAt
        try upsertMetadata(record, localKey: record.resourceID)
    }

    func applyFavorite(_ record: RemoteContentRecord) throws {
        guard let id = UUID(uuidString: record.resourceID) else {
            throw SyncStoreError.invalidPayload
        }
        let payload: ContentFavoritePayload = try decode(record.payloadJSON)
        let descriptor = FetchDescriptor<FavoriteEntity>(
            predicate: #Predicate { $0.favoriteID == id }
        )
        let entity = try modelContext.fetch(descriptor).first ?? {
            let created = FavoriteEntity(
                favoriteID: id,
                sentence: payload.sentence,
                sourceMessageID: payload.sourceMessageId,
                characterName: payload.characterName,
                translationZh: payload.translationZh,
                createdAt: payload.createdAt
            )
            modelContext.insert(created)
            return created
        }()
        entity.sentence = payload.sentence
        entity.sourceMessageID = payload.sourceMessageId
        entity.characterName = payload.characterName
        entity.translationZh = payload.translationZh
        entity.createdAt = payload.createdAt
        try upsertMetadata(record, localKey: record.resourceID)
    }

    func applyMemory(_ record: RemoteContentRecord) throws {
        guard let parent = record.parentID.flatMap(UUID.init(uuidString:)),
              let character = try character(id: parent)
        else {
            throw SyncStoreError.missingParent
        }
        let payload: ContentMemoryPayload = try decode(record.payloadJSON)
        let existingMetadata = try metadata(
            resourceType: .memory,
            resourceID: record.resourceID
        )
        let existing = try existingMetadata.flatMap { try memory(localKey: $0.localKey) }
        let entity = existing ?? {
            let created = MemoryEntity(
                tierRaw: payload.tier,
                sourceRaw: payload.source ?? MemorySource.chat.rawValue,
                content: payload.content,
                importance: payload.importance,
                sourceUpToIndex: payload.sourceUpToIndex,
                createdAt: payload.createdAt
            )
            modelContext.insert(created)
            return created
        }()
        entity.character = character
        entity.tierRaw = payload.tier
        entity.sourceRaw = payload.source ?? MemorySource.chat.rawValue
        entity.content = payload.content
        entity.importance = payload.importance
        entity.sourceUpToIndex = payload.sourceUpToIndex
        entity.createdAt = payload.createdAt
        try modelContext.save()
        try upsertMetadata(record, localKey: persistentKey(entity.persistentModelID))
    }

    func applyStoryProgress(_ record: RemoteContentRecord) throws {
        let payload: ContentStoryProgressPayload = try decode(record.payloadJSON)
        let id = record.resourceID
        let descriptor = FetchDescriptor<StoryProgressEntity>(
            predicate: #Predicate { $0.storyID == id }
        )
        let entity = try modelContext.fetch(descriptor).first ?? {
            let created = StoryProgressEntity(storyID: id)
            modelContext.insert(created)
            return created
        }()
        entity.currentNodeID = payload.currentNodeId
        entity.flagsJSON = Self.encodeFlags(payload.flags)
        entity.completedAt = payload.completedAt
        try upsertMetadata(record, localKey: record.resourceID)
    }



    func deleteLocal(_ record: RemoteContentRecord) throws {
        switch record.resourceType {
        case .character:
            if let id = UUID(uuidString: record.resourceID),
               let entity = try character(id: id) {
                modelContext.delete(entity)
            }
        case .conversation:
            if let id = UUID(uuidString: record.resourceID),
               let entity = try conversation(id: id) {
                modelContext.delete(entity)
            }
        case .favorite:
            if let id = UUID(uuidString: record.resourceID) {
                let descriptor = FetchDescriptor<FavoriteEntity>(
                    predicate: #Predicate { $0.favoriteID == id }
                )
                if let entity = try modelContext.fetch(descriptor).first {
                    modelContext.delete(entity)
                }
            }
        case .memory:
            if let localKey = try metadata(
                resourceType: .memory,
                resourceID: record.resourceID
            )?.localKey, let entity = try memory(localKey: localKey) {
                modelContext.delete(entity)
            }
        case .message:
            if let id = UUID(uuidString: record.resourceID) {
                if let upload = try voiceMediaUpload(messageID: id) {
                    modelContext.delete(upload)
                }
                if let link = try voiceMediaLink(messageID: id) {
                    modelContext.delete(link)
                }
                if let entity = try message(id: id) {
                    modelContext.delete(entity)
                }
            }
        case .storyProgress:
            let id = record.resourceID
            let descriptor = FetchDescriptor<StoryProgressEntity>(
                predicate: #Predicate { $0.storyID == id }
            )
            if let entity = try modelContext.fetch(descriptor).first {
                modelContext.delete(entity)
            }
        }
    }
}
