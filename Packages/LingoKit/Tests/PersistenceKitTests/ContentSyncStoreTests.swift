import Foundation
import SwiftData
import Testing
@testable import PersistenceKit

@Suite("ContentSyncStore")
struct ContentSyncStoreTests {
    @Test("共享会话快照保留全局游标，迟到的同步事件不能回退服务器顺序")
    func sharedSnapshotDoesNotAdvanceCursorOrRegressOrder() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let sync = ContentSyncStore(modelContainer: container)
        let roster = RosterStore(modelContainer: container)
        let chat = ChatStore(modelContainer: container)
        try await sync.activateOwner(userID: UUID())
        let characterID = try await roster.addCharacter(
            card: characterCard(name: "Shared friend"), difficulty: .junior3, isFriend: true)
        let conversation = try await chat.openConversation(characterID: characterID)
        let message = try await chat.appendMessage(
            conversationID: conversation.id, role: .user, text: "Accepted text", sharedOrdering: true)
        let pending = try await sync.takePending(limit: 100)
        let messageMutation = try #require(
            pending.first { $0.resourceID == message.id.uuidString.lowercased() })
        let stale = remote(from: messageMutation, version: 1)
        for mutation in pending {
            try await sync.complete(commandID: mutation.commandID, record: remote(from: mutation, version: 1))
        }
        try await sync.apply(records: [], nextCursor: "unchanged-global-cursor")
        var payload = try #require(
            JSONSerialization.jsonObject(with: Data(stale.payloadJSON.utf8)) as? [String: Any])
        payload["orderIndex"] = 99
        let canonical = RemoteContentRecord(
            createdAt: stale.createdAt, deletedAt: nil, parentID: stale.parentID,
            payloadJSON: String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self),
            resourceID: stale.resourceID,
            resourceType: .message, updatedAt: .now, version: 2)
        try await sync.applySharedChat(records: [canonical], coveredMessageIDs: [message.id])
        #expect(try await sync.syncCursor() == "unchanged-global-cursor")
        #expect(try await chat.messages(conversationID: conversation.id).first?.orderIndex == 99)
        try await sync.apply(records: [stale], nextCursor: "next-global-cursor")
        #expect(try await chat.messages(conversationID: conversation.id).first?.orderIndex == 99)
        #expect(try await chat.messages(conversationID: conversation.id).first?.isInterrupted == false)
    }

    @Test("磁盘库重新打开后恢复未确认上传，保留原操作 ID")
    func recoversInFlightAfterReopeningDiskStore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sync-restart-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(versionedSchema: LingoSchema.self)
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("sync.store"))
        let userID = UUID()
        let pending: PendingContentMutation
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let store = ContentSyncStore(modelContainer: container)
            try await store.activateOwner(userID: userID)
            _ = try await RosterStore(modelContainer: container).addCharacter(card: characterCard(name: "Survives restart"), difficulty: .junior3, isFriend: false)
            pending = try #require(try await store.takePending().first)
            // Repeated activation of the live store must not release an active request.
            try await store.activateOwner(userID: userID)
            #expect(try await store.takePending().isEmpty)
        }
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let store = ContentSyncStore(modelContainer: reopened)
        try await store.activateOwner(userID: userID)
        let retry = try #require(try await store.takePending().first)
        #expect(retry.commandID == pending.commandID)
        #expect(retry.expectedVersion == pending.expectedVersion)
        #expect(retry.payloadJSON == pending.payloadJSON)
        try await store.complete(commandID: retry.commandID, record: remote(from: retry, version: 1))
        #expect(try await store.takePending().isEmpty)
    }

    @Test("游客首站完成与云端检查点合并，保留双方剧情标记")
    func mergesGuestStoryAchievements() throws {
        let local = LocalContentRecord(resourceType: .storyProgress, resourceID: "mainline_london", parentID: nil,
            payloadJSON: "{\"completedAt\":10,\"flags\":{\"guest\":true,\"shared\":true}}")
        let remote = RemoteContentRecord(createdAt: .now, deletedAt: nil, parentID: nil,
            payloadJSON: "{\"schemaVersion\":1,\"currentNodeId\":\"start\",\"flags\":{\"cloud\":true,\"shared\":false}}",
            resourceID: "mainline_london", resourceType: .storyProgress, updatedAt: .now, version: 4)
        let merged = try #require(try ContentSyncStore.mergeGuest(local: local, remote: remote))
        let payload = try JSONDecoder().decode(ContentStoryProgressPayload.self, from: Data(merged.payloadJSON.utf8))
        #expect(payload.completedAt != nil)
        #expect(payload.flags == ["guest": true, "cloud": true, "shared": true])
        #expect(merged.version == 4)
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

    @Test("回执丢失后修改置顶，重试保留原操作和原内容")
    func editedConversationKeepsUnacknowledgedUploadImmutable() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let sync = ContentSyncStore(modelContainer: container)
        let roster = RosterStore(modelContainer: container)
        let chat = ChatStore(modelContainer: container)
        try await sync.activateOwner(userID: UUID())
        let character = try await roster.addCharacter(
            card: characterCard(name: "Pinned after retry"), difficulty: .junior3, isFriend: true)
        let conversation = try await chat.openConversation(characterID: character)
        let initial = try await sync.takePending()
        let attempted = try #require(initial.first { $0.resourceType == .conversation })
        for mutation in initial where mutation.commandID != attempted.commandID {
            try await sync.complete(commandID: mutation.commandID, record: remote(from: mutation, version: 1))
        }
        try await sync.resetInFlight(commandIDs: [attempted.commandID])

        try await chat.setPinned(conversationID: conversation.id, isPinned: true)

        let retry = try #require(try await sync.takePending(serialPerResource: true).first)
        #expect(retry.commandID == attempted.commandID)
        #expect(retry.payloadJSON == attempted.payloadJSON)
        try await sync.complete(commandID: retry.commandID, record: remote(from: attempted, version: 1))
        let update = try #require(try await sync.takePending(serialPerResource: true).first)
        #expect(update.commandID != attempted.commandID)
        #expect(update.expectedVersion == 1)
        let payload = try #require(update.payloadJSON)
        let record = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        #expect(record?["isPinned"] as? Bool == true)
    }

    @Test("已卡住的会话更新在下次打开账号时用新编号恢复")
    func recoversRejectedConversationWithoutDroppingTheEdit() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let user = UUID()
        let sync = ContentSyncStore(modelContainer: container)
        try await sync.activateOwner(userID: user)
        let character = try await RosterStore(modelContainer: container).addCharacter(
            card: characterCard(name: "Retry the pinned update"), difficulty: .junior3, isFriend: true)
        let chat = ChatStore(modelContainer: container)
        let conversation = try await chat.openConversation(characterID: character)
        for mutation in try await sync.takePending() {
            try await sync.complete(commandID: mutation.commandID, record: remote(from: mutation, version: 1))
        }
        try await chat.setPinned(conversationID: conversation.id, isPinned: true)
        let submitted = try #require(try await sync.takePending().first)
        try await sync.reject(commandID: submitted.commandID, code: "IDEMPOTENCY_KEY_CONFLICT", current: nil)

        let reopened = ContentSyncStore(modelContainer: container)
        try await reopened.activateOwner(userID: user)
        let retry = try #require(try await reopened.takePending(serialPerResource: true).first)
        #expect(retry.commandID != submitted.commandID)
        #expect(retry.expectedVersion == submitted.expectedVersion)
        #expect(retry.payloadJSON == submitted.payloadJSON)
        try await reopened.complete(commandID: retry.commandID, record: remote(from: retry, version: 2))
        #expect(try await reopened.unresolvedErrorCount() == 0)
        #expect(try await chat.conversation(id: conversation.id)?.isPinned == true)
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
        var remoteCard = ContentCharacterPayload.Card(
            age: 28,
            appearance: "Brown hair",
            avatarAssetName: nil,
            avatarId: "portrait-0042",
            avatarRemoteUrl: "https://example.invalid/portrait-0042.webp",
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
        )
        remoteCard.readingVoice = .f5
        remoteCard.activityProfile = NPCActivityProfile(
            timeZoneIdentifier: "Europe/London",
            rhythm: .earlyBird,
            focusDurationMinutes: 8
        )
        let characterPayload = ContentCharacterPayload(
            card: remoteCard,
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

            turnCount: 1
        )
        let messagePayload = ContentMessagePayload(
            audioDuration: nil,
            coachReviewJson: nil,
            createdAt: now,
            isInterrupted: false,
            keywordRangesJson: nil,
            kind: MessageKind.text.rawValue,
            orderIndex: 0,
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
        #expect(restoredCharacter.card.signature == "Take the scenic route.")
        #expect(restoredCharacter.card.personaVoice?.values == ["curiosity"])
        #expect(restoredCharacter.card.readingVoice == .f5)
        #expect(restoredCharacter.card.activityProfile?.rhythm == .earlyBird)
        #expect(restoredCharacter.card.activityProfile?.focusDurationMinutes == 8)
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

    @Test("旧设备的角色载荷不会清除本机已有作息")
    func legacyCharacterPayloadPreservesActivityProfile() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let sync = ContentSyncStore(modelContainer: container)
        let roster = RosterStore(modelContainer: container)
        try await sync.activateOwner(userID: UUID())
        let expectedProfile = NPCActivityProfile(
            timeZoneIdentifier: "Europe/London",
            rhythm: .nightOwl,
            focusDurationMinutes: 9
        )
        var localCard = characterCard(name: "Alice")
        localCard.activityProfile = expectedProfile
        localCard.settingVersion = 1
        localCard.settingReleaseID = "places-v1"
        localCard.regionID = "newyork"
        let characterID = try await roster.addCharacter(
            card: localCard,
            difficulty: .junior3,
            isFriend: true
        )
        let legacyPayload = ContentCharacterPayload(
            card: ContentCharacterPayload.Card(
                age: 28,
                appearance: "Brown hair",
                avatarAssetName: nil,
                background: nil,
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
            metAt: .now
        )

        try await sync.apply(
            records: [
                remote(
                    type: .character,
                    id: characterID.uuidString,
                    parentID: nil,
                    payload: try ContentMutationJournal.encode(legacyPayload),
                    version: 2
                ),
            ],
            nextCursor: "next"
        )

        #expect(try await roster.character(id: characterID)?.card.activityProfile == expectedProfile)
        #expect(try await roster.character(id: characterID)?.card.settingReleaseID == "places-v1")
        #expect(try await roster.character(id: characterID)?.card.regionID == "newyork")
    }

    @Test func importsGuestIntoExistingAccountIdempotentlyAndPreservesRemovedContacts() async throws {
        let accountContainer = try ModelContainerFactory.makeContainer(inMemory: true)
        let guestContainer = try ModelContainerFactory.makeContainer(inMemory: true)
        let account = ContentSyncStore(modelContainer: accountContainer)
        let guest = ContentSyncStore(modelContainer: guestContainer)
        let roster = RosterStore(modelContainer: accountContainer)
        let guestRoster = RosterStore(modelContainer: guestContainer)
        try await account.activateOwner(userID: UUID())
        let id = UUID(), newID = UUID()
        let card = characterCard(name: "Alice")
        _ = try await roster.addCharacter(characterID: id, card: card, difficulty: .junior3, isFriend: true)
        try await roster.removeFriend(characterID: id)
        _ = try await guestRoster.addCharacter(characterID: id, card: card, difficulty: .junior3, isFriend: true)
        _ = try await guestRoster.addCharacter(characterID: newID, card: characterCard(name: "Bob"), difficulty: .junior3, isFriend: true)
        let incoming = try await guest.guestRecords()
        for _ in 0..<2 { try await account.importGuestRecords(incoming) }
        #expect(try await roster.allCharacters().count == 2)
        #expect(try await roster.character(id: id)?.contactStatus == .removed)
        #expect(try await roster.character(id: id)?.isFriend == false)
        #expect(try await roster.character(id: newID)?.isFriend == true)
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
