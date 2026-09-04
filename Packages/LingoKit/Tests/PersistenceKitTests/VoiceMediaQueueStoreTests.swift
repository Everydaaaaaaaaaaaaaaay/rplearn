import Foundation
import Testing
@testable import PersistenceKit

@Suite("Voice media persistence")
struct VoiceMediaQueueStoreTests {
    @Test("媒体完成前不发布远端引用，完成后写入同步负载")
    func publishesOnlyReadyAsset() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let chat = ChatStore(modelContainer: container)
        let roster = RosterStore(modelContainer: container)
        let sync = ContentSyncStore(modelContainer: container)
        let userID = UUID()
        try await sync.activateOwner(userID: userID)
        let characterID = try await addCharacter(roster)
        let conversation = try await chat.openConversation(characterID: characterID)
        let message = try await chat.appendMessage(
            conversationID: conversation.id,
            role: .user,
            kind: .voice,
            text: "Hello",
            audioFileName: "temporary.caf",
            audioDuration: 1.2
        )
        let assetID = UUID()
        let upload = pending(
            assetID: assetID,
            messageID: message.id,
            ownerUserID: userID
        )

        try await chat.stageVoiceMediaUpload(upload)
        let staged = try #require(
            try await chat.messages(conversationID: conversation.id).first
        )
        #expect(staged.audioAssetID == nil)
        #expect(staged.audioFileName == upload.localFileName)

        #expect(try await chat.markVoiceMediaReady(
            messageID: message.id,
            assetID: assetID
        ))
        let ready = try #require(
            try await chat.messages(conversationID: conversation.id).first
        )
        #expect(ready.audioAssetID == assetID)

        let messageMutation = try #require(
            try await sync.takePending(limit: 20)
                .last(where: {
                    $0.resourceType == .message && $0.resourceID == message.id.uuidString.lowercased()
                })
        )
        let payloadJSON = try #require(messageMutation.payloadJSON)
        let payload = try #require(
            JSONSerialization.jsonObject(
                with: Data(payloadJSON.utf8)
            ) as? [String: Any]
        )
        #expect(
            (payload["audioAssetId"] as? String).flatMap(UUID.init(uuidString:))
                == assetID
        )
    }

    @Test("队列按账号隔离并在失败后遵守重试时间")
    func isolatesOwnerAndSchedulesRetry() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let queue = VoiceMediaQueueStore(modelContainer: container)
        let firstOwner = UUID()
        let secondOwner = UUID()
        let first = pending(
            assetID: UUID(),
            messageID: UUID(),
            ownerUserID: firstOwner
        )
        let second = pending(
            assetID: UUID(),
            messageID: UUID(),
            ownerUserID: secondOwner
        )
        try await queue.enqueue(first)
        try await queue.enqueue(second)

        #expect(try await queue.next(ownerUserID: firstOwner)?.assetID == first.assetID)
        #expect(try await queue.next(ownerUserID: secondOwner)?.assetID == second.assetID)

        let retryAt = Date.now.addingTimeInterval(60)
        try await queue.fail(
            assetID: first.assetID,
            errorCode: String(repeating: "x", count: 200),
            retryAt: retryAt
        )
        #expect(try await queue.next(ownerUserID: firstOwner) == nil)
        let retried = try #require(
            try await queue.next(
                ownerUserID: firstOwner,
                now: retryAt.addingTimeInterval(1)
            )
        )
        #expect(retried.attemptCount == 1)
        #expect(retried.nextAttemptAt == retryAt)

        try await queue.complete(assetID: first.assetID)
        #expect(try await queue.pendingCount(ownerUserID: firstOwner) == 0)
        #expect(try await queue.pendingCount(ownerUserID: secondOwner) == 1)
    }

    @Test("远端删除严格等待消息墓碑同步完成")
    func deletionWaitsForMessageTombstone() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let chat = ChatStore(modelContainer: container)
        let roster = RosterStore(modelContainer: container)
        let sync = ContentSyncStore(modelContainer: container)
        let queue = VoiceMediaQueueStore(modelContainer: container)
        let userID = UUID()
        try await sync.activateOwner(userID: userID)
        let characterID = try await addCharacter(roster)
        let conversation = try await chat.openConversation(characterID: characterID)
        let message = try await chat.appendMessage(
            conversationID: conversation.id,
            role: .user,
            kind: .voice,
            text: "Delete me",
            audioFileName: "delete.caf",
            audioDuration: 1
        )
        let assetID = UUID()
        try await chat.stageVoiceMediaUpload(
            pending(assetID: assetID, messageID: message.id, ownerUserID: userID)
        )
        #expect(try await chat.markVoiceMediaReady(messageID: message.id, assetID: assetID))

        try await acknowledgeAll(sync)
        _ = try await chat.clearConversationHistory(characterID: characterID)

        #expect(try await queue.pendingDeletionCount(ownerUserID: userID) == 1)
        #expect(try await queue.nextDeletion(ownerUserID: userID) == nil)

        try await acknowledgeAll(sync)
        let deletion = try #require(try await queue.nextDeletion(ownerUserID: userID))
        #expect(deletion.assetID == assetID)
        #expect(deletion.messageID == message.id)
        try await queue.completeDeletion(assetID: assetID)
        #expect(try await queue.pendingDeletionCount(ownerUserID: userID) == 0)
    }

    private func acknowledgeAll(_ sync: ContentSyncStore) async throws {
        for mutation in try await sync.takePending(limit: 100) {
            try await sync.complete(
                commandID: mutation.commandID,
                record: RemoteContentRecord(
                    createdAt: .now,
                    deletedAt: mutation.operation == .delete ? .now : nil,
                    parentID: mutation.parentID,
                    payloadJSON: mutation.payloadJSON ?? "{}",
                    resourceID: mutation.resourceID,
                    resourceType: mutation.resourceType,
                    updatedAt: .now,
                    version: mutation.expectedVersion + 1
                )
            )
        }
    }

    private func pending(
        assetID: UUID,
        messageID: UUID,
        ownerUserID: UUID
    ) -> PendingVoiceMediaUpload {
        PendingVoiceMediaUpload(
            assetID: assetID,
            attemptCount: 0,
            byteSize: 128,
            checksumSha256: "checksum",
            contentType: "audio/x-caf",
            localFileName: "\(ownerUserID.uuidString.lowercased())/\(assetID.uuidString.lowercased()).caf",
            messageID: messageID,
            nextAttemptAt: .now,
            ownerUserID: ownerUserID
        )
    }

    private func addCharacter(_ roster: RosterStore) async throws -> UUID {
        try await roster.addCharacter(
            card: CharacterCard(
                name: "Media Partner",
                age: 24,
                gender: .female,
                nationality: "Australian",
                regionID: "sydney",
                occupation: "designer",
                hobbies: ["music"],
                appearance: "brown hair",
                personality: "patient"
            ),
            difficulty: .junior3,
            isFriend: true
        )
    }
}
