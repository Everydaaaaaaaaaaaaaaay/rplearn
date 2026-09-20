import Foundation
import SwiftData

extension ContentSyncStore {
// MARK: - Local export

    func exportLocalRecords() throws -> [LocalContentRecord] {
        var records: [LocalContentRecord] = []
        for entity in try modelContext.fetch(FetchDescriptor<CharacterEntity>()) {
            let card = CharacterCard.decode(fromJSON: entity.cardJSON)
            var cardPayload = ContentCharacterPayload.Card(
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
            )
            cardPayload.readingVoice = card?.resolvedReadingVoice
            cardPayload.activityProfile = card?.activityProfile
            let payload = ContentCharacterPayload(
                card: cardPayload,
                difficulty: entity.difficultyLevelRaw,
                isFriend: entity.isFriend,
                isFavorite: entity.isFavorite,
                isMainCharacter: entity.isMainCharacter,
                metAt: entity.metAt,
                relationship: RelationshipSnapshot.decode(fromJSON: entity.relationshipJSON) ?? .initial,
                travelerId: entity.travelerID,
                publicIdentityRegistered: entity.publicIdentityRegistered,
                contactStatus: entity.contactStatusRaw,
                remarkName: entity.remarkName,
                privateNote: entity.privateNote,
                proactiveMessagesEnabled: entity.proactiveMessagesEnabled,
                mutedUntil: entity.mutedUntil,
                growth: CharacterGrowthSnapshot.decode(fromJSON: entity.growthJSON) ?? .initial
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
                            isPinned: entity.isPinned,
                            lastMessageAt: entity.lastMessageAt,
                            lastReadAt: entity.lastReadAt,
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
            let media = try voiceMediaLink(messageID: entity.messageID)
            records.append(
                LocalContentRecord(
                    resourceType: .message,
                    resourceID: entity.messageID.uuidString.lowercased(),
                    parentID: parent.uuidString.lowercased(),
                    payloadJSON: try ContentMutationJournal.encode(
                        ContentMessagePayload(
                            audioAssetId: media?.isRemoteReady == true ? media?.assetID : nil,
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
                        source: entity.sourceRaw,
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
}
