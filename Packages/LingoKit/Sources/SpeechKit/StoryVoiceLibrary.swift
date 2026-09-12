import CryptoKit
import Foundation

/// Prepared speech is bound to an exact script node, speaker, and text. Edited
/// scripts safely fall back to live speech until their assets are produced again.
public struct PreparedNarration: Sendable {
    public let url: URL
    public let seconds: Double
}

public struct StoryVoiceLibrary: Sendable {
    private struct Manifest: Decodable {
        let version: Int
        let clips: [Entry]
    }
    private struct Entry: Decodable, Sendable {
        let story: String
        let node: String
        let sourceText: String
        let speaker: String
        let sourceSHA256: String
        let file: String
        let seconds: Double
        let audioSHA256: String
        let voice: String
        let rate: Float
    }
    private let directory: URL
    private let entries: [String: Entry]

    public static let bundled: StoryVoiceLibrary? = {
        guard let url = Bundle.main.url(forResource: "story-voice-library", withExtension: "json") else { return nil }
        return try? StoryVoiceLibrary(manifestURL: url)
    }()

    public init(manifestURL: URL) throws {
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        directory = manifestURL.deletingLastPathComponent()
        var result = [String: Entry]()
        for entry in manifest.clips {
            let key = entry.story + "/" + entry.node
            guard result[key] == nil, !entry.file.contains("/"), !entry.file.contains("\\"),
                  entry.file.hasPrefix("sv-"), entry.file.hasSuffix(".m4a"),
                  entry.seconds.isFinite, entry.seconds > 0,
                  SupertonicVoice(rawValue: entry.voice) != nil, entry.rate.isFinite, (0.88...1.12).contains(entry.rate),
                  Self.digest(Data((entry.speaker + "\n" + entry.sourceText).utf8)) == entry.sourceSHA256 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            result[key] = entry
        }
        entries = result
    }

    public func clip(story: String, node: String, speaker: String, text: String) -> PreparedNarration? {
        guard let entry = entries[story + "/" + node], entry.speaker == speaker, entry.sourceText == text else { return nil }
        guard let voice = SupertonicVoice(rawValue: entry.voice),
              StoryVoiceCasting.voice(speaker: speaker, proposed: voice) == voice else { return nil }
        let url = directory.appendingPathComponent(entry.file)
        // Small compressed per-page files. A damaged/missing package must never
        // play stale speech or make auto mode wait for an impossible completion.
        guard let data = try? Data(contentsOf: url), Self.digest(data) == entry.audioSHA256 else { return nil }
        return PreparedNarration(url: url, seconds: entry.seconds)
    }

    public func request(story: String, node: String, speaker: String, text: String) -> SpeechRequest? {
        guard let entry = entries[story + "/" + node], entry.speaker == speaker, entry.sourceText == text else { return nil }
        return SpeechRequest(text: text, language: "en", purpose: .characterDialogue,
            voiceHint: SpeechVoiceHint(
                stableID: StoryVoiceCasting.isNarrator(speaker) ? StoryVoiceCasting.narratorID : speaker,
                gender: entry.voice.hasPrefix("M") ? "male" : "female",
                supertonicVoice: StoryVoiceCasting.voice(speaker: speaker, proposed: SupertonicVoice(rawValue: entry.voice) ?? .f2)),
            engine: .supertonic3, delivery: SpeechDelivery(speedMultiplier: entry.rate))
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
