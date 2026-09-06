import Foundation

/// Performance cues for one line, separate from visible/searchable dialogue.
/// Identity stays in SpeechVoiceHint. A cue never changes the selected speaker.
public struct SpeechDelivery: Sendable, Equatable {
    public enum Expression: String, Sendable, CaseIterable {
        case breath, sigh, laugh
        var tag: String { "<\(rawValue)>" }
    }

    public let speedMultiplier: Float
    public let leadingPause: Double
    public let trailingPause: Double
    public let expression: Expression?
    /// An exact prefix ending at a sentence boundary. Optional: retain whole-line
    /// prosody unless an intentional dramatic beat warrants separate synthesis.
    public let pauseAfter: String?
    public let pauseDuration: Double

    public init(speedMultiplier: Float = 1, leadingPause: Double = 0,
                trailingPause: Double = 0, expression: Expression? = nil,
                pauseAfter: String? = nil, pauseDuration: Double = 0) {
        self.speedMultiplier = speedMultiplier.isFinite ? min(1.12, max(0.88, speedMultiplier)) : 1
        self.leadingPause = Self.boundedPause(leadingPause)
        self.trailingPause = Self.boundedPause(trailingPause)
        self.expression = expression
        self.pauseAfter = pauseAfter
        self.pauseDuration = Self.boundedPause(pauseDuration)
    }

    private static func boundedPause(_ value: Double) -> Double {
        value.isFinite ? min(1.2, max(0, value)) : 0
    }
}

struct SpeechSynthesisSegment: Sendable, Equatable {
    let text: String
    let silenceAfter: Double
}

extension SpeechRequest {
    /// Dictionary/general speech never inherits dramatic effects. Apple fallback
    /// uses the original text, so unsupported tags can never be read aloud there.
    var narrativeDelivery: SpeechDelivery? {
        purpose == .characterDialogue ? delivery : nil
    }

    var synthesisSegments: [SpeechSynthesisSegment] {
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return [] }
        let cue = narrativeDelivery
        var parts = [SpeechSynthesisSegment(text: plain, silenceAfter: 0)]
        if let prefix = cue?.pauseAfter, !prefix.isEmpty, plain.hasPrefix(prefix),
           let last = prefix.last, ".!?…".contains(last), prefix.count < plain.count {
            let rest = plain.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty {
                parts = [SpeechSynthesisSegment(text: prefix, silenceAfter: cue?.pauseDuration ?? 0),
                         SpeechSynthesisSegment(text: rest, silenceAfter: 0)]
            }
        }
        if let tag = cue?.expression?.tag {
            parts[0] = SpeechSynthesisSegment(text: tag + " " + parts[0].text,
                                               silenceAfter: parts[0].silenceAfter)
        }
        return parts
    }

    var deliveryCacheIdentity: String {
        // Exact scalar values, not rounded decimal strings: two different audible
        // deliveries must not hit the same cached PCM. Length-prefix text anchors.
        guard let cue = narrativeDelivery else { return "plain" }
        let anchor = cue.pauseAfter ?? ""
        return "\(cue.speedMultiplier.bitPattern):\(cue.leadingPause.bitPattern):\(cue.trailingPause.bitPattern):\(cue.expression?.rawValue ?? "none"):\(cue.pauseDuration.bitPattern):\(anchor.utf8.count):\(anchor)"
    }
}
