import CoreKit
import Foundation
import XCTest
import StoryEngine
@testable import StoryFeature
@testable import SpeechKit

/// Explicit local model evaluation, not a standing unit-test gate. Exports audio
/// for human listening; nonempty PCM is not evidence that an emotion sounds right.
final class SpeechDeliveryAuditionTests: XCTestCase {
    @MainActor func testRenderLondonSample() async throws {
        guard Bundle(for: Self.self).object(forInfoDictionaryKey: "LingoTripSpeechSampleEnabled") as? String == "1" else {
            throw XCTSkip("Opt in with RUN_SPEECH_SAMPLE=1; local synthesis + audio attachments")
        }
        let storyURL = try XCTUnwrap(Bundle.main.url(forResource: "departures_london_v1", withExtension: "json"))
        let story = try StoryEpisode.load(data: Data(contentsOf: storyURL))
        let ids = ["small", "small_part2", "own_voice", "agreement", "agreement_part2", "not_test",
                   "silence", "silence_part2", "two_ways", "two_ways_part2"]
        let root = Bundle.main.bundleURL.appendingPathComponent("LingoKit_SpeechKit.bundle/Supertonic3/Models")
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let session = AudioSessionCoordinator()
        let engine = Supertonic3SpeechEngine(modelsRoot: root, audioCacheDirectory: cache,
                                             audioSession: session, apple: AppleTTSService(audioSession: session))
        try await engine.prepare()
        let rate = Supertonic3AssetSelection.sampleRate
        var rhythm: [String: [Float]] = [:]
        var reports: [[String: Any]] = []
        for variant in LondonEpisodeNarration.Variant.allCases {
            var sequence = [Float]()
            for id in ids {
                let node = try XCTUnwrap(story.node(id))
                let request = LondonEpisodeNarration.request(for: node, variant: variant)
                let started = Date()
                let samples: [Float]
                // Share identical rhythm/expressive lines to isolate the one tag
                // from diffusion sampling variability in the rest of the scene.
                if variant == .expressive, node.speech?.expression == nil, let cached = rhythm[id] {
                    samples = cached
                } else { samples = try await engine.synthesizeSamples(request) }
                if variant == .rhythm { rhythm[id] = samples }
                XCTAssertFalse(samples.isEmpty)
                XCTAssertTrue(samples.allSatisfy(\.isFinite))
                XCTAssertTrue(samples.contains { abs($0) > 0.001 })
                let rms = sqrt(samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count))
                let peak = samples.map { abs($0) }.max() ?? 0
                reports.append(["node": id, "variant": variant.rawValue, "text": node.text,
                                "spokenSegments": request.synthesisSegments.map(\.text),
                                "voice": request.voiceHint?.supertonicVoice?.rawValue ?? "",
                                "speed": request.delivery?.speedMultiplier ?? 1,
                                "seconds": Double(samples.count) / rate, "rms": rms, "peak": peak,
                                "elapsedSeconds": Date().timeIntervalSince(started)])
                attach(wav(samples), name: "\(variant.rawValue)-\(id).wav", type: "com.microsoft.waveform-audio")
                sequence.append(contentsOf: samples)
                // Same 0.6s page hold as autoplay. Silent player prompts omitted
                // from this dialogue-only audition, documented in its transcript.
                sequence.append(contentsOf: repeatElement(0, count: Int(rate * 0.6)))
            }
            attach(wav(sequence), name: "scene-\(variant.rawValue).wav", type: "com.microsoft.waveform-audio")
        }
        let data = try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
        attach(data, name: "speech-audition-metrics.json", type: "public.json")
    }

    @MainActor private func attach(_ data: Data, name: String, type: String) {
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: type)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func wav(_ samples: [Float]) -> Data {
        // IEEE float WAV preserves original amplitudes; do not normalize each
        // version independently and accidentally bias the comparison's loudness.
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        append(UInt32(36 + samples.count * 4)); data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(3)); append(UInt16(1)); append(UInt32(44_100))
        append(UInt32(176_400)); append(UInt16(4)); append(UInt16(32))
        data.append(Data("data".utf8)); append(UInt32(samples.count * 4))
        for sample in samples { append(sample.bitPattern) }
        return data
    }
}
