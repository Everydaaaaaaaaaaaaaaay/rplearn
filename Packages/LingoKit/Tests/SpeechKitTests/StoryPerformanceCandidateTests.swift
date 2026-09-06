import CoreKit
import Foundation
import XCTest
import StoryEngine
@testable import SpeechKit

/// Offline production sample, explicitly enabled. Every candidate uses the same
/// bundled renderer as playback; the build/export step finishes before audition.
final class StoryPerformanceCandidateTests: XCTestCase {
    struct Plan: Decodable {
        struct Segment: Decodable {
            let id: String
            let text: String
            let sourceNodes: [String]
            let speaker: String
            let rate: Float
            let gapAfter: Double
            let intention: String
            let breath: Bool
        }
        let sourceNodes: [String]
        let segments: [Segment]
    }

    @MainActor func testRenderCandidates() async throws {
        guard Bundle(for: Self.self).object(forInfoDictionaryKey: "LingoTripSpeechSampleEnabled") as? String == "1" else {
            throw XCTSkip("Opt in with RUN_SPEECH_SAMPLE=1")
        }
        let planURL = try XCTUnwrap(Bundle.main.url(forResource: "london_voice_performance_sample", withExtension: "json"))
        let planData = try Data(contentsOf: planURL)
        let plan = try JSONDecoder().decode(Plan.self, from: planData)
        let storyURL = try XCTUnwrap(Bundle.main.url(forResource: "departures_london_v1", withExtension: "json"))
        let story = try StoryEpisode.load(data: Data(contentsOf: storyURL))
        // Repartitioning may cross panels, but must preserve every spoken word,
        // its order, and speaker identity; never cross a player choice.
        let original = try plan.sourceNodes.map { id in try XCTUnwrap(story.node(id)).text }.joined(separator: " ")
        XCTAssertEqual(plan.segments.map(\.text).joined(separator: " "), original)
        XCTAssertEqual(Set(plan.segments.map(\.id)).count, plan.segments.count)
        for segment in plan.segments {
            XCTAssertTrue((0...1.2).contains(segment.gapAfter))
            for id in segment.sourceNodes {
                let node = try XCTUnwrap(story.node(id))
                XCTAssertEqual(node.speaker, segment.speaker)
                XCTAssertNil(node.choices)
            }
        }
        let root = Bundle.main.bundleURL.appendingPathComponent("LingoKit_SpeechKit.bundle/Supertonic3/Models")
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let session = AudioSessionCoordinator()
        let engine = Supertonic3SpeechEngine(modelsRoot: root, audioCacheDirectory: cache,
                                             audioSession: session, apple: AppleTTSService(audioSession: session))
        try await engine.prepare()
        var metrics: [[String: Any]] = []
        for segment in plan.segments {
            for take in 0..<4 {
                let oliver = segment.speaker == "Oliver"
                // Two samples at preferred rate / 12 steps, an 8-step comparison,
                // and a modest pace alternative. The breath cue also has a
                // no-tag alternative; unsupported acting labels are never used.
                let steps = take == 2 ? 8 : 12
                let speed = take == 3 && !segment.breath ? segment.rate + 0.02 : segment.rate
                let expression: SpeechDelivery.Expression? = segment.breath && take != 3 ? .breath : nil
                let request = SpeechRequest(text: segment.text, language: "en", purpose: .characterDialogue,
                    voiceHint: SpeechVoiceHint(stableID: oliver ? "london.oliver" : segment.speaker == "Nora" ? "london.nora" : "london.narrator",
                                              supertonicVoice: oliver ? .m5 : .f5),
                    delivery: SpeechDelivery(speedMultiplier: speed, expression: expression))
                XCTAssertEqual(request.synthesisSegments.count, 1)
                XCTAssertLessThanOrEqual(request.synthesisSegments[0].text.decomposedStringWithCompatibilityMapping.unicodeScalars.count, 70)
                let started = Date()
                let samples = try await engine.synthesizeSamples(request, totalSteps: steps)
                XCTAssertFalse(samples.isEmpty)
                XCTAssertTrue(samples.allSatisfy(\.isFinite))
                XCTAssertGreaterThan(samples.map { abs($0) }.max() ?? 0, 0.001)
                let name = "candidate-\(segment.id)-\(take).wav"
                attach(wav(samples), name: name, type: "com.microsoft.waveform-audio")
                metrics.append(["segment": segment.id, "take": take, "file": name,
                                "text": segment.text, "speaker": segment.speaker,
                                "voice": oliver ? "M5" : "F5", "speed": speed, "steps": steps,
                                "expression": expression?.rawValue ?? "none",
                                "seconds": Double(samples.count) / 44100,
                                "elapsedSeconds": Date().timeIntervalSince(started)])
                print("PERFORMANCE_CANDIDATE \(segment.id) take=\(take) done")
            }
        }
        attach(planData, name: "performance-plan.json", type: "public.json")
        attach(try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys]),
               name: "performance-candidates.json", type: "public.json")
        attach(NarrativeSoundBank.rain(), name: "performance-rain.wav", type: "com.microsoft.waveform-audio")
    }

    @MainActor private func attach(_ data: Data, name: String, type: String) {
        let item = XCTAttachment(data: data, uniformTypeIdentifier: type)
        item.name = name; item.lifetime = .keepAlways; add(item)
    }

    private func wav(_ samples: [Float]) -> Data {
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        append(UInt32(36 + samples.count * 4)); data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(3)); append(UInt16(1)); append(UInt32(44100))
        append(UInt32(176400)); append(UInt16(4)); append(UInt16(32))
        data.append(Data("data".utf8)); append(UInt32(samples.count * 4))
        for sample in samples { append(sample.bitPattern) }
        return data
    }
}
