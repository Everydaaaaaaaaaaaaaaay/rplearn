import Foundation
import Testing
@testable import SpeechKit

@Suite("VoiceMessageStorage")
struct VoiceMessageStorageTests {
    @Test("目录创建、文件名唯一、URL 落在 VoiceMessages 下")
    func directoryAndNaming() throws {
        let dir = try VoiceMessageStorage.directory()
        #expect(dir.lastPathComponent == "VoiceMessages")
        #expect(FileManager.default.fileExists(atPath: dir.path))

        let nameA = VoiceMessageStorage.newFileName()
        let nameB = VoiceMessageStorage.newFileName()
        #expect(nameA != nameB)
        #expect(nameA.hasSuffix(".caf"))

        let url = try VoiceMessageStorage.url(for: nameA)
        #expect(url.deletingLastPathComponent() == dir)
    }

    @Test("删除文件幂等")
    func deleteIdempotent() throws {
        let name = VoiceMessageStorage.newFileName()
        let url = try VoiceMessageStorage.url(for: name)
        try Data("test".utf8).write(to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
        VoiceMessageStorage.delete(fileName: name)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        VoiceMessageStorage.delete(fileName: name) // 再删不抛错
    }

    @Test("文件迁入账号目录且账号清理互不影响")
    func accountScopedStorage() throws {
        let firstUser = UUID()
        let secondUser = UUID()
        let firstAsset = UUID()
        let secondAsset = UUID()
        defer {
            VoiceMessageStorage.removeAccountDirectory(userID: firstUser)
            VoiceMessageStorage.removeAccountDirectory(userID: secondUser)
        }
        let sourceName = VoiceMessageStorage.newFileName()
        try Data("voice".utf8).write(to: VoiceMessageStorage.url(for: sourceName))

        let adopted = try VoiceMessageStorage.adopt(
            fileName: sourceName,
            userID: firstUser,
            assetID: firstAsset
        )
        let other = try VoiceMessageStorage.store(
            Data("other".utf8),
            userID: secondUser,
            assetID: secondAsset
        )

        #expect(!VoiceMessageStorage.exists(fileName: sourceName))
        #expect(VoiceMessageStorage.exists(fileName: adopted))
        #expect(VoiceMessageStorage.exists(fileName: other))

        VoiceMessageStorage.removeAccountDirectory(userID: firstUser)
        #expect(!VoiceMessageStorage.exists(fileName: adopted))
        #expect(VoiceMessageStorage.exists(fileName: other))
    }

    @Test("拒绝路径穿越与伪造账号目录")
    func rejectsUnsafePaths() {
        #expect(throws: VoiceMessageStorage.StorageError.self) {
            _ = try VoiceMessageStorage.url(for: "../\(UUID().uuidString).caf")
        }
        #expect(throws: VoiceMessageStorage.StorageError.self) {
            _ = try VoiceMessageStorage.url(for: "not-a-user/\(UUID().uuidString).caf")
        }
        #expect(throws: VoiceMessageStorage.StorageError.self) {
            _ = try VoiceMessageStorage.url(for: "/\(UUID().uuidString).caf")
        }
    }
}
