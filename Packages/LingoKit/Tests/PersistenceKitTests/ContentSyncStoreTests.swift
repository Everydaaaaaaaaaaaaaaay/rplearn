import Foundation
import Testing
@testable import PersistenceKit

@Suite("ContentSyncStore")
struct ContentSyncStoreTests {
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
        let characterPayload = ContentCharacterPayload(
            card: .init(
                age: 28,
                appearance: "Brown hair",
                avatarAssetName: nil,
                background: "Guide",
                gender: "female",
                hobbies: ["books"],
                name: "Alice",
                nationality: "British",
                occupation: "Guide",
                personality: "Warm",
                regionId: "london",
                speechStyle: "Friendly"
            ),
            difficulty: DifficultyLevel.junior3.rawValue,
            isFriend: true,
            isMainCharacter: false,
            metAt: now
        )
        let conversationPayload = ContentConversationPayload(
            createdAt: now,
            isArchived: false,
            isEncounterSession: false,
            lastMessageAt: now,
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

        #expect(try await roster.character(id: characterID)?.card.name == "Alice")
        #expect(try await chat.conversation(id: conversationID)?.turnCount == 1)
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

