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
}
