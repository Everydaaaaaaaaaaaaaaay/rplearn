import CoreKit
import Foundation
import XCTest
@testable import SpeechKit

/// Explicit offline asset production; ordinary test runs never synthesize a library.
final class StoryVoiceLibraryProductionTests: XCTestCase {
    struct Plan: Decodable {
        struct Clip: Decodable {
            struct Segment: Decodable {
                let id: String
                let text: String
                let speaker: String
                let voice: String
                let rate: Float
                let breath: Bool
            }
            let segments: [Segment]
        }
        let clips: [Clip]
    }

    @MainActor func testProduceLibrary() async throws {
        let bundle = Bundle(for: Self.self)
        guard bundle.object(forInfoDictionaryKey: "LingoTripSpeechSampleEnabled") as? String == "1",
              let path = bundle.object(forInfoDictionaryKey: "LingoTripSpeechLibraryOutput") as? String,
              path.hasPrefix("/"), !path.contains("$(") else {
            throw XCTSkip("Explicit RUN_SPEECH_SAMPLE=1 and STORY_VOICE_OUTPUT absolute directory required")
        }
        executionTimeAllowance = 3600
        let output = URL(fileURLWithPath: path, isDirectory: true)
        let plan = try JSONDecoder().decode(Plan.self, from: Data(contentsOf: output.appendingPathComponent("production-plan.json")))
        let root = Bundle.main.bundleURL.appendingPathComponent("LingoKit_SpeechKit.bundle/Supertonic3/Models")
        let session = AudioSessionCoordinator()
        let engine = Supertonic3SpeechEngine(modelsRoot: root,
            audioCacheDirectory: output.appendingPathComponent("cache"), audioSession: session,
            apple: AppleTTSService(audioSession: session))
        try await engine.prepare()
        let controlURL = output.appendingPathComponent("render-control.json")
        let control = (try? JSONSerialization.jsonObject(with: Data(contentsOf: controlURL))) as? [String: Any] ?? [:]
        let filter = control["segments"] as? [String]
        let start = control["takeStart"] as? Int ?? 0
        let end = control["takeEnd"] as? Int ?? 4
        for segment in plan.clips.flatMap(\.segments) {
            if let filter, !filter.contains(segment.id) { continue }
            for take in start..<end {
                let variant = take % 4
                let steps = variant == 2 ? 8 : 12
                let speed = variant == 3 && !segment.breath ? min(1.12, segment.rate + 0.02) : segment.rate
                let expression: SpeechDelivery.Expression? = segment.breath && variant != 3 ? .breath : nil
                let voice = try XCTUnwrap(SupertonicVoice(rawValue: segment.voice))
                let request = SpeechRequest(text: segment.text, language: "en", purpose: .characterDialogue,
                    voiceHint: SpeechVoiceHint(stableID: segment.speaker, supertonicVoice: voice), engine: .supertonic3,
                    delivery: SpeechDelivery(speedMultiplier: speed, expression: expression))
                XCTAssertEqual(request.synthesisSegments.count, 1)
                XCTAssertLessThanOrEqual(request.synthesisSegments[0].text.decomposedStringWithCompatibilityMapping.unicodeScalars.count, 70)
                let name = "candidate-\(segment.id)-\(take)"
                let metadata = output.appendingPathComponent(name + ".json")
                let wavURL = output.appendingPathComponent(name + ".wav")
                if let existing = try? JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any],
                   existing["text"] as? String == segment.text,
                   existing["voice"] as? String == segment.voice,
                   existing["speed"] as? Float == speed,
                   existing["steps"] as? Int == steps,
                   existing["expression"] as? String == (expression?.rawValue ?? "none"),
                   FileManager.default.fileExists(atPath: wavURL.path) { continue }
                let began = Date()
                let samples = try await engine.synthesizeSamples(request, totalSteps: steps)
                guard !samples.isEmpty, samples.allSatisfy(\.isFinite), samples.contains(where: { abs($0) > 0.001 }) else {
                    XCTFail("Invalid audio: \(name)"); return
                }
                try wav(samples).write(to: wavURL, options: .atomic)
                let row: [String: Any] = ["segment": segment.id, "take": take, "file": name + ".wav",
                    "text": segment.text, "speaker": segment.speaker, "voice": segment.voice,
                    "speed": speed, "steps": steps, "expression": expression?.rawValue ?? "none",
                    "seconds": Double(samples.count)/44100, "elapsedSeconds": Date().timeIntervalSince(began)]
                try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]).write(to: metadata, options: .atomic)
                print("STORY_VOICE \(name) done")
            }
        }
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
