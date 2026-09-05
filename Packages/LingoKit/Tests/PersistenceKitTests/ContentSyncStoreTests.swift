import Foundation
import Testing
@testable import PersistenceKit

@Suite("ContentSyncStore")
struct ContentSyncStoreTests {
    @Test("头像身份和署名随角色卡导出")
    func avatarCreditsSurviveExport() async throws {
        var card = characterCard(name: "Alice")
        card.avatarID = UUID().uuidString.lowercased()
        card.avatarRemoteURL = "https://example.com/avatar.webp"
        card.avatarAttribution = "Artist · CC BY 4.0 · cropped"
        card.avatarSourceURL = "https://example.com/source"
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let sync = ContentSyncStore(modelContainer: container)
        let roster = RosterStore(modelContainer: container)
        try await sync.activateOwner(userID: UUID())
        _ = try await roster.addCharacter(card: card, difficulty: .junior3, isFriend: false)
        let command = try #require(try await sync.takePending().first)
        let encoded = try #require(command.payloadJSON)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(ContentCharacterPayload.self, from: Data(encoded.utf8))
        #expect(payload.card.avatarAttribution == card.avatarAttribution)
        #expect(payload.card.avatarSourceUrl == card.avatarSourceURL)
        #expect(payload.card.avatarId == card.avatarID)
    }

    @Test("发送中再次编辑会生成下一版本，确认后清空 outbox")
    func versionsInFlightEdits() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let sync = ContentSyncStore(modelContainer: container)
        let roster = RosterStore(modelContainer: container)
        let userID = UUID()
        try await sync.activateOwner(userID: userID)
        let characterID = try await roster.addCharacter(
            card: characterCard(name: "Alice"),
            difficulty: .junior3,
            isFriend: false
        )

        let first = try #require(try await sync.takePending().first)
        #expect(first.resourceType == .character)
        #expect(first.expectedVersion == 0)

        try await roster.setDifficulty(characterID: characterID, level: .advanced)
        let second = try #require(try await sync.takePending().first)
        #expect(second.expectedVersion == 1)
        #expect(second.commandID != first.commandID)

        try await sync.complete(
            commandID: first.commandID,
            record: remote(from: first, version: 1)
        )
        try await sync.complete(
            commandID: second.commandID,
            record: remote(from: second, version: 2)
        )
        #expect(try await sync.takePending().isEmpty)
    }

    @Test("远端角色、会话与消息可以重建干净设备")
    func bootstrapsRemoteHierarchy() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let sync = ContentSyncStore(modelContainer: container)
        let roster = RosterStore(modelContainer: container)
        let chat = ChatStore(modelContainer: container)
        try await sync.activateOwner(userID: UUID())

        let characterID = UUID()
        let conversationID = UUID()
        let messageID = UUID()
        let now = Date()
        let mutedUntil = now.addingTimeInterval(3_600)
        let growth = CharacterGrowthSnapshot(
            revision: 1,
            arcs: [
                CharacterGrowthArc(
                    trait: .openness,
                    direction: .increase,
                    progress: 0.2,
                    stage: .experimenting,
                    reasonZh: "愿意先听听陌生观点"
                ),
            ]
        )
        let characterPayload = ContentCharacterPayload(
            card: .init(
                age: 28,
                appearance: "Brown hair",
                avatarAssetName: nil,
                avatarId: "portrait-0042",
                avatarRemoteUrl: "https://example.invalid/portrait-0042.webp",
                avatarAttribution: "Artist · CC BY 4.0 · cropped",
                avatarSourceUrl: "https://example.com/source",
                background: "Guide",
                birthday: "08-24",
                gender: "female",
                hobbies: ["books"],
                hometown: "Bath",
                languages: ["English", "French"],
                name: "Alice",
                nationality: "British",
                occupation: "Guide",
                personality: "Warm",
                regionId: "london",
                speechStyle: "Friendly",
                signature: "Take the scenic route.",
                personaVoice: PersonaVoiceProfile(
                    values: ["curiosity"],
                    flaws: ["overplans"],
                    conversationalHabits: ["asks specific questions"]
                )
            ),
            difficulty: DifficultyLevel.junior3.rawValue,
            isFriend: true,
            isFavorite: true,
            isMainCharacter: false,
            metAt: now,
            relationship: .initial,
            travelerId: TravelerIDGenerator.make(from: characterID),
            publicIdentityRegistered: true,
            contactStatus: ContactStatus.friend.rawValue,
            remarkName: "小爱",
            privateNote: "在旧车站认识",
            proactiveMessagesEnabled: false,
            mutedUntil: mutedUntil,
            growth: growth
        )
        let conversationPayload = ContentConversationPayload(
            createdAt: now,
            isArchived: false,
            isEncounterSession: false,
            isPinned: true,
            lastMessageAt: now,
            lastReadAt: now,
            lastSummarizedMessageIndex: 0,
            quizOptOut: false,
            turnCount: 1,
            turnsSinceQuiz: 1
        )
        let messagePayload = ContentMessagePayload(
            audioDuration: nil,
            coachReviewJson: nil,
            createdAt: now,
            isInterrupted: false,
            keywordRangesJson: nil,
            kind: MessageKind.text.rawValue,
            orderIndex: 0,
            quizChosenIndex: nil,
            quizJson: nil,
            role: MessageRole.assistant.rawValue,
            speechReviewJson: nil,
            text: "Welcome!",
            tokenEstimate: 2,
            translationZh: "欢迎！"
        )

        try await sync.bootstrap(
            records: [
                remote(
                    type: .character,
                    id: characterID.uuidString,
                    parentID: nil,
                    payload: try ContentMutationJournal.encode(characterPayload)
                ),
                remote(
                    type: .conversation,
                    id: conversationID.uuidString,
                    parentID: characterID.uuidString,
                    payload: try ContentMutationJournal.encode(conversationPayload)
                ),
                remote(
                    type: .message,
                    id: messageID.uuidString,
                    parentID: conversationID.uuidString,
                    payload: try ContentMutationJournal.encode(messagePayload)
                ),
            ],
            syncCursor: "signed-cursor"
        )

        let restoredCharacter = try #require(try await roster.character(id: characterID))
        #expect(restoredCharacter.card.name == "Alice")
        #expect(restoredCharacter.card.avatarID == "portrait-0042")
        #expect(restoredCharacter.card.avatarAttribution == "Artist · CC BY 4.0 · cropped")
        #expect(restoredCharacter.card.avatarSourceURL == "https://example.com/source")
        #expect(restoredCharacter.card.signature == "Take the scenic route.")
        #expect(restoredCharacter.card.personaVoice?.values == ["curiosity"])
        #expect(restoredCharacter.travelerID == TravelerIDGenerator.make(from: characterID))
        #expect(restoredCharacter.publicIdentityRegistered)
        #expect(restoredCharacter.displayName == "小爱")
        #expect(restoredCharacter.contactPreferences.privateNote == "在旧车站认识")
        #expect(!restoredCharacter.contactPreferences.proactiveMessagesEnabled)
        #expect(restoredCharacter.growth.arcs.first?.trait == .openness)
        let restoredConversation = try #require(try await chat.conversation(id: conversationID))
        #expect(restoredConversation.turnCount == 1)
        #expect(restoredConversation.isPinned)
        // ISO-8601 content payloads intentionally round timestamps to whole seconds.
        #expect(abs(restoredConversation.lastReadAt!.timeIntervalSince(now)) < 1)
        let messages = try await chat.messages(conversationID: conversationID)
        #expect(messages.map(\.text) == ["Welcome!"])
        #expect(messages.first?.translationZh == "欢迎！")
        #expect(try await sync.takePending().isEmpty)
    }

    private func characterCard(name: String) -> CharacterCard {
        CharacterCard(
            name: name,
            age: 28,
            gender: .female,
            nationality: "British",
            regionID: "london",
            occupation: "Guide",
            hobbies: ["books"],
            appearance: "Brown hair",
            personality: "Warm"
        )
    }

    private func remote(
        from mutation: PendingContentMutation,
        version: Int
    ) -> RemoteContentRecord {
        remote(
            type: mutation.resourceType,
            id: mutation.resourceID,
            parentID: mutation.parentID,
            payload: mutation.payloadJSON ?? "{}",
            version: version
        )
    }

    private func remote(
        type: ContentResourceKind,
        id: String,
        parentID: String?,
        payload: String,
        version: Int = 1
    ) -> RemoteContentRecord {
        RemoteContentRecord(
            createdAt: .now,
            deletedAt: nil,
            parentID: parentID,
            payloadJSON: payload,
            resourceID: id.lowercased(),
            resourceType: type,
            updatedAt: .now,
            version: version
        )
    }
}
