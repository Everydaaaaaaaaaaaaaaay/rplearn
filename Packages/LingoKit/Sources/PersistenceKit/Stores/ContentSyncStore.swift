import Foundation
import SwiftData

public struct RemoteContentRecord: Sendable, Equatable {
    public let createdAt: Date
    public let deletedAt: Date?
    public let parentID: String?
    public let payloadJSON: String
    public let resourceID: String
    public let resourceType: ContentResourceKind
    public let updatedAt: Date
    public let version: Int

    public init(
        createdAt: Date,
        deletedAt: Date?,
        parentID: String?,
        payloadJSON: String,
        resourceID: String,
        resourceType: ContentResourceKind,
        updatedAt: Date,
        version: Int
    ) {
        self.createdAt = createdAt
        self.deletedAt = deletedAt
        self.parentID = parentID
        self.payloadJSON = payloadJSON
        self.resourceID = resourceID
        self.resourceType = resourceType
        self.updatedAt = updatedAt
        self.version = version
    }
}

public struct PendingContentMutation: Sendable, Equatable {
    public let commandID: UUID
    public let expectedVersion: Int
    public let operation: ContentMutationOperation
    public let parentID: String?
    public let payloadJSON: String?
    public let resourceID: String
    public let resourceType: ContentResourceKind
}

@ModelActor
public actor ContentSyncStore {
    public enum SyncStoreError: Error {
        case invalidPayload
        case missingParent
        case unknownResource
    }

    public func activateOwner(userID: UUID) throws {
        if let owner = try modelContext.fetch(FetchDescriptor<ContentSyncOwnerEntity>()).first {
            guard owner.userID == userID else {
                throw SyncStoreError.invalidPayload
            }
            return
        }
        modelContext.insert(ContentSyncOwnerEntity(userID: userID))
        try modelContext.save()
    }

    public func needsBootstrap(userID: UUID) throws -> Bool {
        guard let owner = try owner(), owner.userID == userID else { return true }
        return !owner.hasBootstrapped
    }

    public func bootstrap(
        records: [RemoteContentRecord],
        syncCursor: String
    ) throws {
        guard let owner = try owner() else {
            throw SyncStoreError.invalidPayload
        }
        let serverKeys = Set(records.map { metadataKey($0.resourceType, $0.resourceID) })
        for record in records {
            try apply(record)
        }
        for local in try exportLocalRecords()
        where !serverKeys.contains(metadataKey(local.resourceType, local.resourceID)) {
            try ContentMutationJournal.upsert(
                in: modelContext,
                resourceType: local.resourceType,
                resourceID: local.resourceID,
                parentID: local.parentID,
                payloadJSON: local.payloadJSON
            )
        }
        owner.syncCursor = syncCursor
        owner.hasBootstrapped = true
        try modelContext.save()
    }

    public func apply(
        records: [RemoteContentRecord],
        nextCursor: String
    ) throws {
        for record in records {
            try apply(record)
        }
        guard let owner = try owner() else {
            throw SyncStoreError.invalidPayload
        }
        owner.syncCursor = nextCursor
        try modelContext.save()
    }

    public func syncCursor() throws -> String? {
        try owner()?.syncCursor
    }

    public func takePending(limit: Int = 50) throws -> [PendingContentMutation] {
        guard let owner = try owner() else { return [] }
        let userID = owner.userID
        var descriptor = FetchDescriptor<ContentOutboxEntity>(
            predicate: #Predicate {
                $0.ownerUserID == userID
                    && !$0.isInFlight
                    && $0.lastErrorCode == nil
            }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt)]
        descriptor.fetchLimit = max(1, min(limit, 100))
        let entities = try modelContext.fetch(descriptor)
        for entity in entities {
            entity.isInFlight = true
            entity.attemptCount += 1
        }
        try modelContext.save()
        return try entities.map(Self.pending(from:))
    }

    public func complete(commandID: UUID, record: RemoteContentRecord) throws {
        guard let command = try outbox(commandID: commandID) else { return }
        let localKey = try metadata(
            resourceType: record.resourceType,
            resourceID: record.resourceID
        )?.localKey ?? record.resourceID
        try upsertMetadata(
            record,
            localKey: localKey
        )
        modelContext.delete(command)
        try modelContext.save()
    }

    public func reject(
        commandID: UUID,
        code: String,
        current: RemoteContentRecord?
    ) throws {
        guard let failed = try outbox(commandID: commandID) else { return }
        if code == "CONTENT_VERSION_CONFLICT", let current {
            let desiredOperation = ContentMutationOperation(rawValue: failed.operationRaw)
            let desiredPayload = failed.payloadJSON
            let desiredParent = failed.parentID
            let later = try pendingForResource(
                ownerUserID: failed.ownerUserID,
                resourceTypeRaw: failed.resourceTypeRaw,
                resourceID: failed.resourceID
            ).filter { $0.commandID != failed.commandID }
            modelContext.delete(failed)
            try apply(current)
            if later.isEmpty,
               let kind = ContentResourceKind(rawValue: current.resourceType.rawValue),
               let desiredOperation
            {
                if desiredOperation == .upsert, let desiredPayload {
                    try ContentMutationJournal.upsert(
                        in: modelContext,
                        resourceType: kind,
                        resourceID: current.resourceID,
                        parentID: desiredParent,
                        payloadJSON: desiredPayload
                    )
                } else if desiredOperation == .delete {
                    try ContentMutationJournal.delete(
                        in: modelContext,
                        resourceType: kind,
                        resourceID: current.resourceID
                    )
                }
            } else {
                for (offset, pending) in later.enumerated() {
                    pending.commandID = UUID()
                    pending.expectedVersion = current.version + offset
                    pending.isInFlight = false
                    pending.lastErrorCode = nil
                }
            }
        } else {
            failed.isInFlight = false
            failed.lastErrorCode = code
        }
        try modelContext.save()
    }

    public func resetInFlight(commandIDs: [UUID]) throws {
        let ids = Set(commandIDs)
        let entities = try modelContext.fetch(FetchDescriptor<ContentOutboxEntity>())
        for entity in entities where ids.contains(entity.commandID) {
            entity.isInFlight = false
        }
        try modelContext.save()
    }

    public func unresolvedErrorCount() throws -> Int {
        try modelContext.fetchCount(
            FetchDescriptor<ContentOutboxEntity>(
                predicate: #Predicate { $0.lastErrorCode != nil }
            )
        )
    }

    // MARK: - Remote apply

    private func apply(_ record: RemoteContentRecord) throws {
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
        case .quizRecord:
            try applyQuizRecord(record)
        case .storyProgress:
            try applyStoryProgress(record)
        }
    }

    private func applyCharacter(_ record: RemoteContentRecord) throws {
        guard let id = UUID(uuidString: record.resourceID) else {
            throw SyncStoreError.invalidPayload
        }
        let payload: ContentCharacterPayload = try decode(record.payloadJSON)
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
            avatarAssetName: payload.card.avatarAssetName
        )
        let entity = try character(id: id) ?? {
            let created = CharacterEntity(
                characterID: id,
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
        entity.cardJSON = card.encodedJSON()
        entity.metAt = payload.metAt
        try upsertMetadata(record, localKey: record.resourceID)
    }

    private func applyConversation(_ record: RemoteContentRecord) throws {
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
                turnsSinceQuiz: payload.turnsSinceQuiz,
                quizOptOut: payload.quizOptOut,
                lastSummarizedMessageIndex: payload.lastSummarizedMessageIndex,
                isEncounterSession: payload.isEncounterSession,
                isArchived: payload.isArchived
            )
            modelContext.insert(created)
            return created
        }()
        entity.character = character
        entity.createdAt = payload.createdAt
        entity.lastMessageAt = payload.lastMessageAt
        entity.turnCount = payload.turnCount
        entity.turnsSinceQuiz = payload.turnsSinceQuiz
        entity.quizOptOut = payload.quizOptOut
        entity.lastSummarizedMessageIndex = payload.lastSummarizedMessageIndex
        entity.isEncounterSession = payload.isEncounterSession
        entity.isArchived = payload.isArchived
        try upsertMetadata(record, localKey: record.resourceID)
    }

    private func applyMessage(_ record: RemoteContentRecord) throws {
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
                quizJSON: payload.quizJson,
                quizChosenIndex: payload.quizChosenIndex,
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
        entity.audioFileName = nil
        entity.audioDuration = payload.audioDuration
        entity.orderIndex = payload.orderIndex
        entity.tokenEstimate = payload.tokenEstimate
        entity.keywordRangesJSON = payload.keywordRangesJson
        entity.coachReviewJSON = payload.coachReviewJson
        entity.speechReviewJSON = payload.speechReviewJson
        entity.quizJSON = payload.quizJson
        entity.quizChosenIndex = payload.quizChosenIndex
        entity.translationZh = payload.translationZh
        entity.isInterrupted = payload.isInterrupted
        entity.createdAt = payload.createdAt
        try upsertMetadata(record, localKey: record.resourceID)
    }

    private func applyFavorite(_ record: RemoteContentRecord) throws {
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

    private func applyMemory(_ record: RemoteContentRecord) throws {
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
        entity.content = payload.content
        entity.importance = payload.importance
        entity.sourceUpToIndex = payload.sourceUpToIndex
        entity.createdAt = payload.createdAt
        try modelContext.save()
        try upsertMetadata(record, localKey: persistentKey(entity.persistentModelID))
    }

    private func applyStoryProgress(_ record: RemoteContentRecord) throws {
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

    private func applyQuizRecord(_ record: RemoteContentRecord) throws {
        let payload: ContentQuizRecordPayload = try decode(record.payloadJSON)
        let existingMetadata = try metadata(
            resourceType: .quizRecord,
            resourceID: record.resourceID
        )
        let existing = try existingMetadata.flatMap {
            try quizRecord(localKey: $0.localKey)
        }
        let entity = existing ?? {
            let created = QuizRecordEntity(
                question: payload.question,
                optionsJSON: payload.optionsJson,
                correctIndex: payload.correctIndex,
                chosenIndex: payload.chosenIndex,
                characterName: payload.characterName,
                createdAt: payload.createdAt
            )
            modelContext.insert(created)
            return created
        }()
        entity.question = payload.question
        entity.optionsJSON = payload.optionsJson
        entity.correctIndex = payload.correctIndex
        entity.chosenIndex = payload.chosenIndex
        entity.characterName = payload.characterName
        entity.createdAt = payload.createdAt
        try modelContext.save()
        try upsertMetadata(record, localKey: persistentKey(entity.persistentModelID))
    }

    private func deleteLocal(_ record: RemoteContentRecord) throws {
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
            if let id = UUID(uuidString: record.resourceID),
               let entity = try message(id: id) {
                modelContext.delete(entity)
            }
        case .quizRecord:
            if let localKey = try metadata(
                resourceType: .quizRecord,
                resourceID: record.resourceID
            )?.localKey, let entity = try quizRecord(localKey: localKey) {
                modelContext.delete(entity)
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

    // MARK: - Local export

    private func exportLocalRecords() throws -> [LocalContentRecord] {
        var records: [LocalContentRecord] = []
        for entity in try modelContext.fetch(FetchDescriptor<CharacterEntity>()) {
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
                isMainCharacter: entity.isMainCharacter,
                metAt: entity.metAt
            )
            records.append(
                LocalContentRecord(
                    resourceType: .character,
                    resourceID: entity.characterID.uuidString.lowercased(),
                    parentID: nil,
                    payloadJSON: try ContentMutationJournal.encode(payload)
                )
            )
        }
        for entity in try modelContext.fetch(FetchDescriptor<ConversationEntity>()) {
            guard let parent = entity.character?.characterID else { continue }
            records.append(
                LocalContentRecord(
                    resourceType: .conversation,
                    resourceID: entity.conversationID.uuidString.lowercased(),
                    parentID: parent.uuidString.lowercased(),
                    payloadJSON: try ContentMutationJournal.encode(
                        ContentConversationPayload(
                            createdAt: entity.createdAt,
                            isArchived: entity.isArchived,
                            isEncounterSession: entity.isEncounterSession,
                            lastMessageAt: entity.lastMessageAt,
                            lastSummarizedMessageIndex: entity.lastSummarizedMessageIndex,
                            quizOptOut: entity.quizOptOut,
                            turnCount: entity.turnCount,
                            turnsSinceQuiz: entity.turnsSinceQuiz
                        )
                    )
                )
            )
        }
        for entity in try modelContext.fetch(FetchDescriptor<MessageEntity>()) {
            guard let parent = entity.conversation?.conversationID else { continue }
            records.append(
                LocalContentRecord(
                    resourceType: .message,
                    resourceID: entity.messageID.uuidString.lowercased(),
                    parentID: parent.uuidString.lowercased(),
                    payloadJSON: try ContentMutationJournal.encode(
                        ContentMessagePayload(
                            audioDuration: entity.audioDuration,
                            coachReviewJson: entity.coachReviewJSON,
                            createdAt: entity.createdAt,
                            isInterrupted: entity.isInterrupted,
                            keywordRangesJson: entity.keywordRangesJSON,
                            kind: entity.kindRaw,
                            orderIndex: entity.orderIndex,
                            quizChosenIndex: entity.quizChosenIndex,
                            quizJson: entity.quizJSON,
                            role: entity.roleRaw,
                            speechReviewJson: entity.speechReviewJSON,
                            text: entity.text,
                            tokenEstimate: entity.tokenEstimate,
                            translationZh: entity.translationZh
                        )
                    )
                )
            )
        }
        for entity in try modelContext.fetch(FetchDescriptor<FavoriteEntity>()) {
            records.append(
                LocalContentRecord(
                    resourceType: .favorite,
                    resourceID: entity.favoriteID.uuidString.lowercased(),
                    parentID: nil,
                    payloadJSON: try ContentMutationJournal.encode(
                        ContentFavoritePayload(
                            characterName: entity.characterName,
                            createdAt: entity.createdAt,
                            sentence: entity.sentence,
                            sourceMessageId: entity.sourceMessageID,
                            translationZh: entity.translationZh
                        )
                    )
                )
            )
        }
        for entity in try modelContext.fetch(FetchDescriptor<MemoryEntity>()) {
            guard let parent = entity.character?.characterID else { continue }
            let localKey = persistentKey(entity.persistentModelID)
            let resourceID = try ContentMutationJournal.resourceID(
                in: modelContext,
                resourceType: .memory,
                localKey: localKey
            )
            records.append(
                LocalContentRecord(
                    resourceType: .memory,
                    resourceID: resourceID,
                    parentID: parent.uuidString.lowercased(),
                    payloadJSON: try ContentMutationJournal.encode(
                        ContentMemoryPayload(
                            content: entity.content,
                            createdAt: entity.createdAt,
                            importance: entity.importance,
                            sourceUpToIndex: entity.sourceUpToIndex,
                            tier: entity.tierRaw
                        )
                    )
                )
            )
        }
        for entity in try modelContext.fetch(FetchDescriptor<StoryProgressEntity>()) {
            records.append(
                LocalContentRecord(
                    resourceType: .storyProgress,
                    resourceID: entity.storyID,
                    parentID: nil,
                    payloadJSON: try ContentMutationJournal.encode(
                        ContentStoryProgressPayload(
                            completedAt: entity.completedAt,
                            currentNodeId: entity.currentNodeID,
                            flags: Self.decodeFlags(entity.flagsJSON)
                        )
                    )
                )
            )
        }
        for entity in try modelContext.fetch(FetchDescriptor<QuizRecordEntity>()) {
            guard let chosenIndex = entity.chosenIndex else { continue }
            let localKey = persistentKey(entity.persistentModelID)
            let resourceID = try ContentMutationJournal.resourceID(
                in: modelContext,
                resourceType: .quizRecord,
                localKey: localKey
            )
            records.append(
                LocalContentRecord(
                    resourceType: .quizRecord,
                    resourceID: resourceID,
                    parentID: nil,
                    payloadJSON: try ContentMutationJournal.encode(
                        ContentQuizRecordPayload(
                            characterName: entity.characterName,
                            chosenIndex: chosenIndex,
                            correctIndex: entity.correctIndex,
                            createdAt: entity.createdAt,
                            optionsJson: entity.optionsJSON,
                            question: entity.question
                        )
                    )
                )
            )
        }
        return records
    }

    // MARK: - Queries

    private func owner() throws -> ContentSyncOwnerEntity? {
        try modelContext.fetch(FetchDescriptor<ContentSyncOwnerEntity>()).first
    }

    private func outbox(commandID: UUID) throws -> ContentOutboxEntity? {
        let descriptor = FetchDescriptor<ContentOutboxEntity>(
            predicate: #Predicate { $0.commandID == commandID }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func pendingForResource(
        ownerUserID: UUID,
        resourceTypeRaw: String,
        resourceID: String
    ) throws -> [ContentOutboxEntity] {
        var descriptor = FetchDescriptor<ContentOutboxEntity>(
            predicate: #Predicate {
                $0.ownerUserID == ownerUserID
                    && $0.resourceTypeRaw == resourceTypeRaw
                    && $0.resourceID == resourceID
            }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt)]
        return try modelContext.fetch(descriptor)
    }

    private func metadata(
        resourceType: ContentResourceKind,
        resourceID: String
    ) throws -> ContentSyncMetadataEntity? {
        let key = metadataKey(resourceType, resourceID)
        let descriptor = FetchDescriptor<ContentSyncMetadataEntity>(
            predicate: #Predicate { $0.metadataKey == key }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func upsertMetadata(
        _ record: RemoteContentRecord,
        localKey: String
    ) throws {
        if let metadata = try metadata(
            resourceType: record.resourceType,
            resourceID: record.resourceID
        ) {
            metadata.localKey = localKey
            metadata.version = record.version
            metadata.updatedAt = record.updatedAt
        } else {
            modelContext.insert(
                ContentSyncMetadataEntity(
                    resourceType: record.resourceType,
                    resourceID: record.resourceID,
                    localKey: localKey,
                    version: record.version,
                    updatedAt: record.updatedAt
                )
            )
        }
    }

    private func character(id: UUID) throws -> CharacterEntity? {
        let descriptor = FetchDescriptor<CharacterEntity>(
            predicate: #Predicate { $0.characterID == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func conversation(id: UUID) throws -> ConversationEntity? {
        let descriptor = FetchDescriptor<ConversationEntity>(
            predicate: #Predicate { $0.conversationID == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func message(id: UUID) throws -> MessageEntity? {
        let descriptor = FetchDescriptor<MessageEntity>(
            predicate: #Predicate { $0.messageID == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func memory(localKey: String) throws -> MemoryEntity? {
        try modelContext.fetch(FetchDescriptor<MemoryEntity>()).first {
            persistentKey($0.persistentModelID) == localKey
        }
    }

    private func quizRecord(localKey: String) throws -> QuizRecordEntity? {
        try modelContext.fetch(FetchDescriptor<QuizRecordEntity>()).first {
            persistentKey($0.persistentModelID) == localKey
        }
    }

    private func persistentKey(_ id: PersistentIdentifier) -> String {
        ContentMutationJournal.persistentKey(id)
    }

    private func metadataKey(
        _ resourceType: ContentResourceKind,
        _ resourceID: String
    ) -> String {
        "\(resourceType.rawValue):\(resourceID)"
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }
            if let date = ISO8601DateFormatter().date(from: value) {
                return date
            }
            throw SyncStoreError.invalidPayload
        }
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    private static func pending(
        from entity: ContentOutboxEntity
    ) throws -> PendingContentMutation {
        guard let operation = ContentMutationOperation(rawValue: entity.operationRaw),
              let type = ContentResourceKind(rawValue: entity.resourceTypeRaw)
        else {
            throw SyncStoreError.unknownResource
        }
        return PendingContentMutation(
            commandID: entity.commandID,
            expectedVersion: entity.expectedVersion,
            operation: operation,
            parentID: entity.parentID,
            payloadJSON: entity.payloadJSON,
            resourceID: entity.resourceID,
            resourceType: type
        )
    }

    private static func encodeFlags(_ flags: [String: Bool]) -> String {
        guard let data = try? JSONEncoder().encode(flags) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeFlags(_ json: String) -> [String: Bool] {
        (try? JSONDecoder().decode([String: Bool].self, from: Data(json.utf8))) ?? [:]
    }
}
