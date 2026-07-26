import BackendKit
import CryptoKit
import Foundation
import PersistenceKit
import SpeechKit
import Testing
@testable import MediaKit

@Suite("VoiceMediaCoordinator")
struct VoiceMediaCoordinatorTests {
    private final class MemoryOwnerStore: VoiceMediaOwnerStore, @unchecked Sendable {
        private let lock = NSLock()
        private var userID: UUID?

        func load() -> UUID? {
            lock.withLock { userID }
        }

        func save(_ userID: UUID) {
            lock.withLock { self.userID = userID }
        }
    }

    private actor FakeBackend: VoiceMediaBackend {
        private struct Record {
            let byteSize: Int
            let checksum: String
            let contentType: String
        }

        private var records: [UUID: Record] = [:]
        private(set) var completed: [UUID] = []
        private(set) var deleted: [UUID] = []

        func reserveVoiceMedia(
            assetID: UUID,
            byteSize: Int,
            checksumSha256: String,
            contentType: String
        ) async throws -> BackendMediaReservation {
            records[assetID] = Record(
                byteSize: byteSize,
                checksum: checksumSha256,
                contentType: contentType
            )
            return BackendMediaReservation(
                asset: asset(id: assetID, status: "pending"),
                upload: BackendMediaTransfer(
                    expiresAt: "2030-01-01T00:00:00.000Z",
                    headers: ["content-type": contentType],
                    method: "PUT",
                    url: URL(string: "https://objects.example.com/\(assetID)")!
                )
            )
        }

        func completeVoiceMedia(assetID: UUID) async throws -> BackendMediaAsset {
            completed.append(assetID)
            return asset(id: assetID, status: "ready")
        }

        func voiceMediaDownload(assetID: UUID) async throws -> BackendMediaDownload {
            BackendMediaDownload(
                asset: asset(id: assetID, status: "ready"),
                download: BackendMediaDownloadTransfer(
                    expiresAt: "2030-01-01T00:00:00.000Z",
                    url: URL(string: "https://objects.example.com/\(assetID)")!
                )
            )
        }

        func deleteVoiceMedia(assetID: UUID) async throws {
            deleted.append(assetID)
        }

        private func asset(id: UUID, status: String) -> BackendMediaAsset {
            let record = records[id]!
            return BackendMediaAsset(
                byteSize: record.byteSize,
                checksumSha256: record.checksum,
                contentType: record.contentType,
                createdAt: "2026-01-01T00:00:00.000Z",
                deletedAt: nil,
                id: id,
                pendingExpiresAt: "2030-01-01T00:00:00.000Z",
                purpose: "voice_message",
                readyAt: status == "ready" ? "2026-01-01T00:00:01.000Z" : nil,
                status: status
            )
        }
    }

    private actor FakeBinaryTransport: VoiceMediaBinaryTransport {
        private(set) var uploads: [Data] = []
        private var downloadData = Data()

        func setDownloadData(_ data: Data) {
            downloadData = data
        }

        func download(from url: URL) async throws -> Data {
            downloadData
        }

        func upload(
            _ data: Data,
            to url: URL,
            method: String,
            headers: [String: String]
        ) async throws {
            uploads.append(data)
        }
    }

    @Test("上传完成后才发布引用，并校验按需下载内容")
    func uploadsThenPublishesAndDownloads() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let chat = ChatStore(modelContainer: container)
        let queue = VoiceMediaQueueStore(modelContainer: container)
        let roster = RosterStore(modelContainer: container)
        let backend = FakeBackend()
        let binary = FakeBinaryTransport()
        let userID = UUID()
        defer {
            VoiceMessageStorage.removeAccountDirectory(userID: userID)
        }
        let coordinator = VoiceMediaCoordinator(
            backend: backend,
            chatStore: chat,
            queueStore: queue,
            binaryTransport: binary,
            ownerStore: MemoryOwnerStore()
        )
        let characterID = try await addCharacter(roster)
        let conversation = try await chat.openConversation(characterID: characterID)
        let sourceFileName = VoiceMessageStorage.newFileName()
        let voiceData = Data("valid-caf-fixture".utf8)
        try voiceData.write(to: VoiceMessageStorage.url(for: sourceFileName))
        let message = try await chat.appendMessage(
            conversationID: conversation.id,
            role: .user,
            kind: .voice,
            text: "Voice message",
            audioFileName: sourceFileName,
            audioDuration: 1
        )

        await coordinator.activate(userID: userID)
        let assetID = try await coordinator.enqueue(
            messageID: message.id,
            sourceFileName: sourceFileName
        )

        try await waitUntil {
            try await queue.pendingCount(ownerUserID: userID) == 0
        }
        let ready = try #require(
            try await chat.messages(conversationID: conversation.id).first
        )
        #expect(ready.audioAssetID == assetID)
        #expect(await backend.completed == [assetID])
        #expect(await binary.uploads == [voiceData])

        let scopedFile = try #require(ready.audioFileName)
        VoiceMessageStorage.delete(fileName: scopedFile)
        await binary.setDownloadData(Data("corrupt".utf8))
        await #expect(throws: VoiceMediaError.integrityMismatch) {
            _ = try await coordinator.localFile(
                messageID: message.id,
                assetID: assetID,
                existingFileName: nil
            )
        }
        #expect(!VoiceMessageStorage.exists(fileName: scopedFile))

        await binary.setDownloadData(voiceData)
        let downloaded = try await coordinator.localFile(
            messageID: message.id,
            assetID: assetID,
            existingFileName: nil
        )
        #expect(downloaded == scopedFile)
        #expect(VoiceMessageStorage.exists(fileName: downloaded))
        #expect(try Data(contentsOf: VoiceMessageStorage.url(for: downloaded)) == voiceData)
        await coordinator.deactivate()
    }

    private func waitUntil(
        _ predicate: @escaping @Sendable () async throws -> Bool
    ) async throws {
        for _ in 0..<100 {
            if try await predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("等待媒体队列清空超时")
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
