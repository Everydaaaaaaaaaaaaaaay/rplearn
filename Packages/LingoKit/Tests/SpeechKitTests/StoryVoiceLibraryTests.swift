import AVFoundation
import CoreKit
import CryptoKit
import Foundation
import Testing
@testable import SpeechKit

@Suite("预制剧情音频") @MainActor
struct StoryVoiceLibraryTests {
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private func fixture(file: String = "sv-test-line.m4a", duplicate: Bool = false) throws -> (URL, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let audio = NarrativeSoundBank.page()
        try audio.write(to: folder.appendingPathComponent("sv-test-line.m4a"))
        let row: [String: Any] = ["story": "test", "node": "line", "speaker": "Oliver", "sourceText": "One page.",
            "sourceSHA256": digest(Data("Oliver\nOne page.".utf8)), "file": file, "seconds": 0.09,
            "audioSHA256": digest(audio), "voice": "M5", "rate": 1.0]
        let url = folder.appendingPathComponent("story-voice-library.json")
        try JSONSerialization.data(withJSONObject: ["version": 1, "clips": duplicate ? [row, row] : [row]]).write(to: url)
        return (folder, url)
    }

    @Test("绑定剧本、节点、说话人和原文，错配或损坏资源不播放")
    func bindingAndIntegrity() throws {
        let (folder, url) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try StoryVoiceLibrary(manifestURL: url)
        #expect(library.clip(story: "test", node: "line", speaker: "Oliver", text: "One page.") != nil)
        #expect(library.clip(story: "other", node: "line", speaker: "Oliver", text: "One page.") == nil)
        #expect(library.clip(story: "test", node: "line", speaker: "Nora", text: "One page.") == nil)
        #expect(library.clip(story: "test", node: "line", speaker: "Oliver", text: "Two pages.") == nil)
        try Data("corrupt".utf8).write(to: folder.appendingPathComponent("sv-test-line.m4a"))
        #expect(library.clip(story: "test", node: "line", speaker: "Oliver", text: "One page.") == nil)
        // Missing audio can retain authored casting on the live fallback.
        #expect(library.request(story: "test", node: "line", speaker: "Oliver", text: "One page.")?.voiceHint?.supertonicVoice == .m5)
    }

    @Test("旧预制音色不再匹配角色时使用正确音色实时合成")
    func staleCastingFallsBack() throws {
        let (folder, url) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var clips = try #require(manifest["clips"] as? [[String: Any]])
        clips[0]["voice"] = "M1"
        manifest["clips"] = clips
        try JSONSerialization.data(withJSONObject: manifest).write(to: url)
        let library = try StoryVoiceLibrary(manifestURL: url)
        #expect(library.clip(story: "test", node: "line", speaker: "Oliver", text: "One page.") == nil)
        #expect(library.request(story: "test", node: "line", speaker: "Oliver", text: "One page.")?.voiceHint?.supertonicVoice == .m5)
    }

    @Test("重复映射和跨目录文件使清单失效")
    func rejectAmbiguity() throws {
        for (filename, duplicate) in [("../sv-other.m4a", false), ("sv-test-line.m4a", true)] {
            let (folder, url) = try fixture(file: filename, duplicate: duplicate)
            defer { try? FileManager.default.removeItem(at: folder) }
            #expect(throws: (any Error).self) { try StoryVoiceLibrary(manifestURL: url) }
        }
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    @Test("实际音频完成后才推进；缺失文件回退；快速切页不泄露旧完成")
    func preparedPlayback() async throws {
        let (folder, url) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clip = try #require(StoryVoiceLibrary(manifestURL: url).clip(story: "test", node: "line", speaker: "Oliver", text: "One page."))
        let spy = LibrarySpeechSpy()
        let player = NarrativeAudioPlayer(speech: spy, audioSession: AudioSessionCoordinator(), soundEffects: false)
        player.play(id: "prepared", request: SpeechRequest(text: "fallback"), rainVolume: 0, prepared: clip)
        #expect(player.completedID == nil)
        #expect(await eventually { player.completedID == "prepared" })
        #expect(await spy.requests.isEmpty)
        player.pause()
        player.play(id: "prepared", request: SpeechRequest(text: "fallback"), rainVolume: 0, prepared: clip)
        #expect(await eventually { player.completedID == "prepared" }) // Completed page does not replay after lookup.
        player.play(id: "old", request: nil, rainVolume: 0, prepared: clip)
        player.play(id: "new", request: nil, rainVolume: 0)
        #expect(await eventually { player.completedID == "new" })
        try FileManager.default.removeItem(at: clip.url)
        player.play(id: "missing", request: SpeechRequest(text: "fallback"), rainVolume: 0, prepared: clip)
        #expect(await eventually { player.completedID == "missing" })
        #expect(await spy.requests == ["fallback"])
        player.stop(); await player.waitUntilStopped()
    }

    @Test("中途暂停和查词后续播，停止和换页丢弃旧进度")
    func preparedResume() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("long.wav")
        // Use the real decoder with a one-second sound; avoid live synthesis in tests.
        var data = NarrativeSoundBank.rain()
        data = Data(data.prefix(44 + 22_050 * 2))
        func put(_ value: UInt32, at offset: Int) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.replaceSubrange(offset..<offset + 4, with: $0) }
        }
        put(UInt32(data.count - 8), at: 4); put(UInt32(data.count - 44), at: 40)
        try data.write(to: url)
        let clip = PreparedNarration(url: url, seconds: 1)
        let player = NarrativeAudioPlayer(speech: LibrarySpeechSpy(), audioSession: AudioSessionCoordinator(), soundEffects: false)
        player.play(id: "line", request: nil, rainVolume: 0, prepared: clip)
        try await Task.sleep(for: .milliseconds(650))
        player.pause()
        #expect(player.completedID == nil)
        player.play(id: "lookup", request: SpeechRequest(text: "word", purpose: .pronunciation), rainVolume: 0)
        #expect(await eventually { player.completedID == "lookup" })
        let began = Date()
        player.play(id: "line", request: nil, rainVolume: 0, prepared: clip)
        #expect(await eventually { player.completedID == "line" })
        #expect(Date().timeIntervalSince(began) < 0.8)
        player.stop(); await player.waitUntilStopped()
    }
}

private actor LibrarySpeechSpy: SpeechService {
    private(set) var requests: [String] = []
    func speak(_ request: SpeechRequest) { requests.append(request.text) }
    func speakAndWait(_ request: SpeechRequest) { requests.append(request.text) }
    func stopSpeaking() { }
    func refreshVoices() { }
}
