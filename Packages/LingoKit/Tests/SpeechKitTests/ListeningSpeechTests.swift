import CoreKit
import Foundation
@testable import SpeechKit
import Testing

@Suite("实时听力的音色、分段与失败边界")
struct ListeningSpeechTests {
    @Test("F1先读，M5第二遍，不受角色旁白选声影响")
    func casting() {
        #expect(ListeningVoicePolicy.voice(completedPlays: 0) == .f1)
        #expect(ListeningVoicePolicy.voice(completedPlays: 1) == .m5)
        #expect(ListeningVoicePolicy.maximumPlayCount == 2)
        for voice in [SupertonicVoice.f1, .m5] {
            let request = SpeechRequest(text: "Listen.", language: "en", purpose: .characterDialogue,
                voiceHint: .init(stableID: "listening." + voice.rawValue, supertonicVoice: voice),
                engine: .supertonic3, allowsSystemFallback: false)
            #expect(Supertonic3VoiceCatalog.profile(for: request).voiceID == voice.rawValue)
        }
    }
    @Test("分段保留顺序、否定和数字，并限制单段长度")
    func chunking() {
        let text = "Don't take bus 12. Take bus 20 instead! " + Array(repeating: "Keep this detail", count: 70).joined(separator: " ")
        let chunks = ListeningVoicePolicy.chunks(text)
        #expect(chunks.allSatisfy { $0.count <= 320 })
        #expect(chunks.joined(separator: " ") == text)
        #expect(ListeningVoicePolicy.chunks("  ").isEmpty)
        let pcm = ListeningPCM.wave([0, 0.25, -0.25], sampleRate: 44_100)
        #expect(pcm.prefix(4) == Data("RIFF".utf8))
        #expect(pcm.count == 56)
    }
    @Test("模型缺失时明确失败，不能假装播完或换系统声音")
    func noFallback() async {
        let service = AdaptiveSpeechService(audioSession: AudioSessionCoordinator(),
            supertonicModelDirectory: URL(fileURLWithPath: "/nonexistent-listening-model-test"))
        await #expect(throws: (any Error).self) {
            _ = try await service.synthesizeListening("The door is open.", voice: .f1)
        }
    }
}

import XCTest

final class ListeningRuntimeSmokeTests: XCTestCase {
    @MainActor func testSynthesizeBothVoicesWithoutWritingAudio() async throws {
        guard Bundle(for: Self.self).object(forInfoDictionaryKey: "LingoTripSpeechSampleEnabled") as? String == "1" else {
            throw XCTSkip("Opt in with RUN_SPEECH_SAMPLE=1 for local Supertonic model verification")
        }
        let service = AdaptiveSpeechService(audioSession: AudioSessionCoordinator())
        for voice in [SupertonicVoice.f1, .m5] {
            let began = Date()
            let data = try await service.synthesizeListening("The book swap will start after lunch.", voice: voice)
            XCTAssertEqual(data.prefix(4), Data("RIFF".utf8))
            let seconds = Double(data.count - 44) / 176_400
            XCTAssertGreaterThan(seconds, 1); XCTAssertLessThan(seconds, 20)
            let peak = data.withUnsafeBytes { bytes in
                stride(from: 44, to: data.count, by: 4).map { Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: $0, as: UInt32.self))) }.map(abs).max() ?? 0
            }
            XCTAssertGreaterThan(peak, 0.001)
            print("LIVE_LISTENING_CHECK voice=\(voice.rawValue) seconds=\(seconds) elapsed=\(Date().timeIntervalSince(began)) audioWritten=false")
        }
    }
}
