// Offline macOS production using the SAME SDK, model files and inference parameters
// as Supertonic3SpeechEngine. Build via produce-story-voices-mac.sh; never an app gate.
import CoreML
import FluidAudio
import Foundation

struct Plan: Decodable {
    struct Clip: Decodable {
        struct Segment: Decodable {
            let id: String; let text: String; let speaker: String
            let voice: String; let rate: Float; let breath: Bool
        }
        let segments: [Segment]
    }
    let clips: [Clip]
}

@main struct Producer {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Usage: VoiceProducer OUTPUT MODELS_ROOT") }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let plan = try JSONDecoder().decode(Plan.self, from: Data(contentsOf: output.appendingPathComponent("production-plan.json")))
        let control = (try? JSONSerialization.jsonObject(with: Data(contentsOf: output.appendingPathComponent("render-control.json")))) as? [String: Any] ?? [:]
        let filter = control["segments"] as? [String]
        let start = control["takeStart"] as? Int ?? 0
        let end = control["takeEnd"] as? Int ?? 4
        let manager = Supertonic3Manager(directory: root, computeUnits: .cpuAndNeuralEngine, vectorEstimator: .aneBucketed(.int4))
        try await manager.initialize()
        let stylesRoot = root.appendingPathComponent(Repo.supertonic3.folderName).appendingPathComponent("voice_styles")
        var styles: [String: Supertonic3VoiceStyle] = [:]
        for segment in plan.clips.flatMap(\.segments) {
            if let filter, !filter.contains(segment.id) { continue }
            if styles[segment.voice] == nil { styles[segment.voice] = try Supertonic3VoiceStyle.load(from: stylesRoot.appendingPathComponent(segment.voice + ".json")) }
            for take in start..<end {
                let variant = take % 4
                let steps = variant == 2 ? 8 : 12
                let speed = variant == 3 && !segment.breath ? min(1.12, segment.rate + 0.02) : segment.rate
                let expression = segment.breath && variant != 3 ? "breath" : "none"
                let text = (expression == "breath" ? "<breath> " : "") + segment.text
                guard text.decomposedStringWithCompatibilityMapping.unicodeScalars.count <= 70 else { fatalError("Chunk too long: \(segment.id)") }
                let name = "candidate-\(segment.id)-\(take)"
                let metadata = output.appendingPathComponent(name + ".json")
                let wavURL = output.appendingPathComponent(name + ".wav")
                if let old = try? JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any],
                   old["text"] as? String == segment.text, old["voice"] as? String == segment.voice,
                   old["speed"] as? Float == speed, old["steps"] as? Int == steps,
                   old["expression"] as? String == expression,
                   FileManager.default.fileExists(atPath: wavURL.path) { continue }
                let began = Date()
                let result = try await manager.synthesize(text: text, language: "en", style: styles[segment.voice]!, totalSteps: steps, speed: speed, silenceDuration: 0.05)
                let samples = result.samples
                guard !samples.isEmpty, samples.allSatisfy(\.isFinite), samples.contains(where: { abs($0) > 0.001 }) else { fatalError("Invalid audio: \(name)") }
                try wav(samples).write(to: wavURL, options: .atomic)
                let row: [String: Any] = ["segment": segment.id, "take": take, "file": name + ".wav", "text": segment.text,
                    "speaker": segment.speaker, "voice": segment.voice, "speed": speed, "steps": steps, "expression": expression,
                    "seconds": Double(samples.count)/44100, "elapsedSeconds": Date().timeIntervalSince(began),
                    "renderer": "macOS CoreML / cpuAndNeuralEngine / aneBucketed-int4"]
                try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]).write(to: metadata, options: .atomic)
                print("STORY_VOICE \(name) \(Date().timeIntervalSince(began))s")
                fflush(stdout)
            }
        }
        await manager.cleanup()
    }
    static func wav(_ samples: [Float]) -> Data {
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
