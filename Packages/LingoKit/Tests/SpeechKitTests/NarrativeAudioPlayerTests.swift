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
        for (data, duration) in [(NarrativeSoundBank.rain(), 48.0), (NarrativeSoundBank.page(), 0.09)] {
            let player = try AVAudioPlayer(data: data)
            #expect(abs(player.duration - duration) < 0.001)
            let bytes = Array(data.dropFirst(44))
            let samples = stride(from: 0, to: bytes.count, by: 2).map {
                Double(Int16(bitPattern: UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8)) / 32768
            }
            let peak = samples.map(abs).max() ?? 0
            let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Double(samples.count))
            #expect(peak < 0.5)
            if duration > 1 {
                #expect(rms > 0.02)
                // Measure the actual circular boundary, not silent endpoints: no
                // low-energy dip in any 20ms window across multiple loop joins.
                let edge = Array(samples.suffix(2205)) + Array(samples.prefix(2205))
                for offset in stride(from: 0, through: edge.count - 441, by: 110) {
                    let window = edge[offset..<(offset + 441)]
                    let localRMS = sqrt(window.reduce(0) { $0 + $1 * $1 } / Double(window.count))
                    #expect(localRMS > rms * 0.65)
                    #expect(localRMS < rms * 1.4)
                }
                let ordinaryMaxStep = zip(samples, samples.dropFirst()).map { abs($0 - $1) }.max() ?? 0
                #expect(abs(samples[0] - samples[samples.count - 1]) <= ordinaryMaxStep)
            } else {
                #expect(rms > 0.001 && rms < 0.015)
                #expect(peak < 0.08)
                #expect(abs(samples.first ?? 1) < 0.001)
                #expect(abs(samples.last ?? 1) < 0.001)
            }
        }
        #expect(NarrativeSoundBank.rain() == NarrativeSoundBank.rain())
    }

    @Test("雨声循环没有周期性涨落，接缝前后响度与高低频能量保持平稳")
    func rainHasStationaryLoudnessAndTimbre() {
        let bytes = Array(NarrativeSoundBank.rain().dropFirst(44))
        let samples = stride(from: 0, to: bytes.count, by: 2).map {
            Double(Int16(bitPattern: UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8)) / 32768
        }
        func level(_ values: ArraySlice<Double>) -> Double {
            10 * log10(values.reduce(0) { $0 + $1 * $1 } / Double(values.count))
        }
        let rate = NarrativeSoundBank.sampleRate
        // Long-window check catches a smooth but clearly audible volume cycle,
        // which a sample-continuity or 20ms gap test cannot detect.
        let levels = stride(from: 0, to: samples.count, by: rate * 2).map {
            level(samples[$0..<min($0 + rate * 2, samples.count)])
        }
        #expect((levels.max() ?? 0) - (levels.min() ?? 0) < 0.75)

        // Separate low/high bands with a circular one-pole crossover (~350Hz).
        // Test the *rendered PCM*, including windows that straddle the join.
        var low = 0.0
        let coefficient = 1 - exp(-2 * Double.pi * 350 / Double(rate))
        for sample in samples { low += coefficient * (sample - low) }
        var bass = [Double](), treble = [Double]()
        for sample in samples {
            low += coefficient * (sample - low)
            bass.append(low)
            treble.append(sample - low)
        }
        for band in [samples, bass, treble] {
            let reference = level(band[...])
            let joined = Array(band.suffix(rate * 2)) + Array(band.prefix(rate * 2))
            for offset in stride(from: 0, through: joined.count - rate, by: rate / 4) {
                #expect(abs(level(joined[offset..<offset + rate]) - reference) < 0.5)
            }
            #expect(abs(level(band.prefix(rate)) - level(band.suffix(rate))) < 0.5)
        }
    }

    @Test("样章显式选择 Supertonic，不受全局系统引擎偏好影响")
    func pilotSupertonicRouting() {
        let request = SpeechRequest(text: "One page.", language: "en", purpose: .characterDialogue,
                                    engine: .supertonic3)
        #expect(SpeechEngineRouter.resolve(request: request, selectedEngine: .system,
                                          supertonicIsAvailable: true) == .supertonic3)
    }

    @Test("英音要求强制路由到系统引擎，不冒充 Supertonic 的 en 为 en-GB")
    func exactAccentRouting() {
        let request = SpeechRequest(text: "One page.", language: "en-GB", purpose: .characterDialogue,
                                    requiresExactLocale: true)
        #expect(SpeechEngineRouter.resolve(request: request, selectedEngine: .supertonic3,
                                          supertonicIsAvailable: true) == .system)
        let voices = AVSpeechSynthesisVoice.speechVoices()
        for gender in ["male", "female"] {
            let selected = AppleTTSService.exactLocaleVoice(from: voices, language: "en-GB", gender: gender)
            // A missing installed locale is allowed; another accent is not.
            #expect(selected == nil || selected?.language == "en-GB")
            if voices.contains(where: { $0.language == "en-GB" }) { #expect(selected != nil) }
        }
    }

    @Test("其他功能仍保留固定 Supertonic 音色")
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
