import AVFoundation
import CoreKit
import Foundation
import Testing
@testable import SpeechKit

@Suite("剧情配音生命周期", .serialized) @MainActor
struct NarrativeAudioPlayerTests {
    private func eventually(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    @Test("只在整句播放结束后标记完成，快速切句不排队、不被旧完成回调覆盖")
    func latestPageWins() async {
        let speech = NarrativeSpeechSpy()
        let player = NarrativeAudioPlayer(speech: speech, audioSession: AudioSessionCoordinator(), soundEffects: false)
        player.play(id: "first", request: SpeechRequest(text: "first"), rainVolume: 0)
        #expect(await eventually { await speech.current == "first" })
        #expect(player.completedID == nil)
        player.play(id: "skipped", request: SpeechRequest(text: "skipped"), rainVolume: 0)
        player.play(id: "latest", request: SpeechRequest(text: "latest"), rainVolume: 0)
        #expect(await eventually { await speech.current == "latest" })
        #expect(player.completedID == nil)
        #expect(await speech.requests == ["first", "latest"])
        await speech.finish()
        #expect(await eventually { player.completedID == "latest" })
        player.stop()
        await player.waitUntilStopped()
    }

    @Test("查词接管、静音和退出停止旧语音，取消不误报整句完成")
    func lookupAndStop() async {
        let speech = NarrativeSpeechSpy()
        let player = NarrativeAudioPlayer(speech: speech, audioSession: AudioSessionCoordinator(), soundEffects: false)
        player.play(id: "line", request: SpeechRequest(text: "line"), rainVolume: 0)
        #expect(await eventually { await speech.current == "line" })
        player.play(id: "lookup", request: SpeechRequest(text: "word", purpose: .pronunciation), rainVolume: 0, pageTurn: false)
        #expect(await eventually { await speech.current == "word" })
        player.stop()
        await player.waitUntilStopped()
        #expect(await speech.current == nil)
        #expect(player.completedID == nil)
    }

    @Test("退出发生在语音合并窗口内时不再启动配音")
    func exitBeforeStart() async {
        let speech = NarrativeSpeechSpy()
        let player = NarrativeAudioPlayer(speech: speech, audioSession: AudioSessionCoordinator(), soundEffects: false)
        player.play(id: "line", request: SpeechRequest(text: "cancelled"), rainVolume: 0)
        player.stop()
        await player.waitUntilStopped()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(await speech.requests.isEmpty)
        #expect(player.completedID == nil)
    }

    @Test("原创雨声与翻页声可解码、有非零采样、无削波且生成可复现")
    func soundAssets() throws {
        for (data, duration) in [(NarrativeSoundBank.rain(), 8.0), (NarrativeSoundBank.page(), 0.13)] {
            let player = try AVAudioPlayer(data: data)
            #expect(abs(player.duration - duration) < 0.001)
            let bytes = Array(data.dropFirst(44))
            let samples = stride(from: 0, to: bytes.count, by: 2).map {
                Double(Int16(bitPattern: UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8)) / 32768
            }
            let peak = samples.map(abs).max() ?? 0
            let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Double(samples.count))
            #expect(peak < 0.5)
            #expect(rms > 0.02)
            #expect(abs(samples.first ?? 1) < 0.001)
            #expect(abs(samples.last ?? 1) < 0.001)
        }
        #expect(NarrativeSoundBank.rain() == NarrativeSoundBank.rain())
    }

    @Test("固定角色音色：Oliver 男声，Nora 和旁白不共用一个音色")
    func castVoices() {
        func profile(_ id: String, _ gender: String) -> Supertonic3VoiceCatalog.Profile {
            Supertonic3VoiceCatalog.profile(for: SpeechRequest(text: "One page.", purpose: .characterDialogue,
                voiceHint: SpeechVoiceHint(stableID: "london.\(id)", gender: gender)))
        }
        #expect(profile("oliver", "male").voiceID.hasPrefix("M"))
        #expect(profile("nora", "female").voiceID.hasPrefix("F"))
        #expect(profile("nora", "female").voiceID != profile("narrator", "female").voiceID)
    }
}

private actor NarrativeSpeechSpy: SpeechService {
    private(set) var requests: [String] = []
    private(set) var current: String?
    private var waiter: CheckedContinuation<Void, Never>?
    func speak(_ request: SpeechRequest) async { await speakAndWait(request) }
    func speakAndWait(_ request: SpeechRequest) async {
        current = request.text
        requests.append(request.text)
        await withCheckedContinuation { waiter = $0 }
    }
    func finish() { current = nil; waiter?.resume(); waiter = nil }
    func stopSpeaking() { finish() }
    func refreshVoices() { }
}
